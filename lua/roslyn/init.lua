---@param bufname string
local function bufname_valid(bufname)
    return bufname:match("^/")
        or bufname:match("^[a-zA-Z]:")
        or bufname:match("^zipfile://")
        or bufname:match("^tarfile:")
end

---@type string?
local _pipe_name = nil

---@type table<string, string>
---Key is solution directory, and value is csproj target
local solution = {}

---@param pipe string
---@param target string
---@param roslyn_config RoslynNvimConfig
local function lsp_start(pipe, target, roslyn_config)
    local client_id = vim.lsp.start({
        name = "roslyn",
        capabilities = roslyn_config.config.capabilities,
        settings = roslyn_config.config.settings,
        cmd = vim.lsp.rpc.connect(pipe),
        root_dir = vim.fs.dirname(target),
        on_attach = roslyn_config.config.on_attach,
        on_init = function(client)
            vim.notify("Roslyn client initialized for " .. target, vim.log.levels.INFO)
            client.notify("solution/open", {
                ["solution"] = vim.uri_from_fname(target),
            })
        end,
        handlers = {
            ["client/registerCapability"] = require("roslyn.hacks").with_filtered_watchers(
                vim.lsp.handlers["client/registerCapability"],
                roslyn_config
            ),
            ["workspace/projectInitializationComplete"] = function()
                vim.notify("Roslyn project initialization complete", vim.log.levels.INFO)
            end,
            ["workspace/_roslyn_projectHasUnresolvedDependencies"] = function()
                vim.notify("Detected missing dependencies. Run dotnet restore command.", vim.log.levels.ERROR)
                return vim.NIL
            end,
        },
    })

    -- Handle the error in some way
    if not client_id then
        return
    end

    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
        return
    end

    local commands = require("roslyn.commands")
    commands.fix_all_code_action(client)
    commands.nested_code_action(client)
end

---@param exe string
---@param target string
---@param config RoslynNvimConfig
local function run_roslyn(exe, target, config)
    vim.system({
        "dotnet",
        exe,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
    }, {
        detach = not vim.uv.os_uname().version:find("Windows"),
        stdout = function(_, data)
            if not data then
                return vim.notify("Failed to get data from roslyn")
            end

            -- try parse data as json
            local success, json_obj = pcall(vim.json.decode, data)
            if not success then
                return
            end

            local pipe_name = json_obj["pipeName"]
            if not pipe_name then
                return
            end

            -- Cache the pipe name so we only start roslyn once.
            _pipe_name = pipe_name

            vim.schedule(function()
                lsp_start(pipe_name, target, config)
            end)
        end,
        stderr_handler = function(_, chunk)
            local log = require("vim.lsp.log")
            if chunk and log.error() then
                log.error("rpc", "dotnet", "stderr", chunk)
            end
        end,
    })
end

-- Assigns the default capabilities from cmp if installed, and the capabilities from neovim
-- Merges it in with any user configured capabilities if provided
---@param roslyn_config? RoslynNvimConfig
local function get_default_capabilities(roslyn_config)
    local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
    local capabilities = ok
            and vim.tbl_deep_extend(
                "force",
                vim.lsp.protocol.make_client_capabilities(),
                cmp_nvim_lsp.default_capabilities()
            )
        or vim.lsp.protocol.make_client_capabilities()

    -- This actually tells the server that the client can do filewatching.
    -- We will then later just not watch any files. This is because the server
    -- will fallback to its own filewatching which is super slow.
    if roslyn_config and not roslyn_config.filewatching then
        capabilities = vim.tbl_deep_extend("force", capabilities, {
            workspace = {
                didChangeWatchedFiles = {
                    dynamicRegistration = true,
                },
            },
        })
    end

    -- HACK: Roslyn requires the dynamicRegistration to be set to support diagnostics for some reason
    return vim.tbl_deep_extend("force", capabilities, {
        textDocument = {
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    })
end

local M = {}

---@class RoslynNvimConfig
---@field filewatching boolean
---@field exe string
---@field config vim.lsp.ClientConfig

---@param config? RoslynNvimConfig
function M.setup(config)
    ---@type RoslynNvimConfig
    local default_config = {
        filewatching = true,
        exe = vim.fs.joinpath(
            vim.fn.stdpath("data") --[[@as string]],
            "roslyn",
            "Microsoft.CodeAnalysis.LanguageServer.dll"
        ),
        -- I don't know how to make this a partial type.
        ---@diagnostic disable-next-line: missing-fields
        config = {
            capabilities = get_default_capabilities(config),
        },
    }

    ---@type RoslynNvimConfig
    local roslyn_config = vim.tbl_deep_extend("force", default_config, config or {})

    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
        pattern = { "cs" },
        callback = function(opt)
            local bufname = vim.api.nvim_buf_get_name(opt.buf)

            if vim.bo["buftype"] == "nofile" or not bufname_valid(bufname) then
                return
            end

            local exe = roslyn_config.exe
            if not vim.uv.fs_stat(exe) then
                return vim.notify(
                    string.format("%s not found. Refer to README on how to setup the language server", exe),
                    vim.log.levels.INFO
                )
            end

            local sln_dir = vim.fs.root(opt.buf, function(name)
                return name:match("%.sln$") ~= nil
            end)
            if not sln_dir then
                return
            end

            -- We need to always check if there is more than one solution. If we have this check below the check for the pipe name
            -- Then we wouldn't give the users an option to change target if they navigate to a different project with multiple solutions
            -- after they have already started the roslyn language server, and a solution is chosen
            local targets = vim.fn.glob(vim.fs.joinpath(sln_dir, "*.sln"), true, true)
            if #targets > 1 then
                vim.notify_once(
                    "Multiple targets found. Use `CSTarget` to select target for buffer",
                    vim.log.levels.INFO
                )

                vim.api.nvim_create_user_command("CSTarget", function()
                    vim.ui.select(targets, { prompt = "Select target: " }, function(target)
                        solution[sln_dir] = target
                        if _pipe_name then
                            lsp_start(_pipe_name, target, roslyn_config)
                        else
                            run_roslyn(exe, target, roslyn_config)
                        end
                    end)
                end, { desc = "Selects the target for the current buffer" })
            end

            -- Roslyn is already running, so just call `vim.lsp.start` to handle everything
            if _pipe_name and solution[sln_dir] then
                return lsp_start(_pipe_name, solution[sln_dir], roslyn_config)
            end

            if #targets == 1 then
                run_roslyn(exe, targets[1], roslyn_config)
                solution[sln_dir] = targets[1]
            end
        end,
    })
end

return M
