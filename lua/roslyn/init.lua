---@param bufname string
local function bufname_valid(bufname)
    return bufname:match("^/")
        or bufname:match("^[a-zA-Z]:")
        or bufname:match("^zipfile://")
        or bufname:match("^tarfile:")
end

local function get_mason_installation()
    local mason_installation = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "mason", "bin", "roslyn")
    return vim.uv.os_uname().sysname == "Windows_NT" and string.format("%s.cmd", mason_installation)
        or mason_installation
end

---@type string?
local _pipe_name = nil

---@type table<string, string>
---Key is solution directory, and value is sln target
local known_solutions = {}

---@param pipe string
---@param target string
---@param roslyn_config InternalRoslynNvimConfig
local function lsp_start(pipe, target, roslyn_config)
    local config = roslyn_config.config

    config.name = "roslyn"
    config.cmd = vim.lsp.rpc.connect(pipe)
    config.root_dir = vim.fs.dirname(target)
    config.handlers = vim.tbl_deep_extend("force", {
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
    }, config.handlers or {})
    config.on_init = function(client)
        vim.notify("Initializing Roslyn client for " .. target, vim.log.levels.INFO)
        client.notify("solution/open", {
            ["solution"] = vim.uri_from_fname(target),
        })
    end

    local client_id = vim.lsp.start(config)

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
---@param config InternalRoslynNvimConfig
local function run_roslyn(exe, target, config)
    local cmd = {
        "dotnet",
        exe,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
    }

    -- Check if we have a binary installed through mason. If we do, the prefer to use that
    local mason_installation = get_mason_installation()
    if vim.uv.fs_stat(mason_installation) then
        cmd = {
            mason_installation,
            "--logLevel=Information",
            "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
        }
    end

    vim.system(
        cmd,
        {
            detach = not vim.uv.os_uname().version:find("Windows"),
            stdout = function(_, data)
                if not data then
                    return
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
        },
        function()
            _pipe_name = nil
            vim.schedule(function()
                vim.notify("Roslyn server stopped", vim.log.levels.ERROR)
            end)
        end
    )
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

    -- Default value is true, so the user needs to explicitly pass `false` for this to happen
    -- `not filewatching` evaluates to true if the user don't provide a value for this
    if roslyn_config and roslyn_config.filewatching == false then
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

---@class InternalRoslynNvimConfig
---@field filewatching boolean
---@field exe string
---@field config vim.lsp.ClientConfig

---@class RoslynNvimConfig
---@field filewatching? boolean
---@field exe? string
---@field config? vim.lsp.ClientConfig

---@param config? RoslynNvimConfig
function M.setup(config)
    ---@type InternalRoslynNvimConfig
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

    ---@type InternalRoslynNvimConfig
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
            local mason_installation = get_mason_installation()
            if not vim.uv.fs_stat(exe) and not vim.uv.fs_stat(mason_installation) then
                return vim.notify(
                    string.format("%s not found. Refer to README on how to setup the language server", exe),
                    vim.log.levels.INFO
                )
            end

            local sln_directory = require("roslyn.slnutils").get_sln_directory(opt.buf)

            if not sln_directory then
                return
            end

            -- Roslyn is already running, so just call `vim.lsp.start` to handle everything
            if _pipe_name and known_solutions[sln_directory] then
                lsp_start(_pipe_name, known_solutions[sln_directory], roslyn_config)

                return
            end

            local all_sln_files = require("roslyn.slnutils").get_all_sln_files(opt.buf)

            if not all_sln_files then
                return
            end

            vim.api.nvim_create_user_command("CSTarget", function()
                vim.ui.select(all_sln_files, { prompt = "Select target solution: " }, function(sln_file)
                    known_solutions[sln_directory] = sln_file
                    if _pipe_name then
                        lsp_start(_pipe_name, sln_file, roslyn_config)
                    else
                        run_roslyn(exe, sln_file, roslyn_config)
                    end
                end)
            end, { desc = "Selects the sln file for the current buffer" })

            if #all_sln_files == 1 then
                run_roslyn(exe, all_sln_files[1], roslyn_config)
                known_solutions[sln_directory] = all_sln_files[1]

                return
            end

            -- Multiple sln files found, let's try to predict which one is the correct one for the current buffer
            local predicted_sln_file = require("roslyn.slnutils").predict_sln_file(opt.buf)

            if predicted_sln_file then
                run_roslyn(exe, predicted_sln_file, roslyn_config)
                known_solutions[sln_directory] = predicted_sln_file
            end

            vim.notify_once(
                "Multiple sln files found. You can use `CSTarget` to select target for buffer",
                vim.log.levels.INFO
            )
        end,
    })
end

return M
