local hacks = require("roslyn.hacks")

local server_config = {
	capabilities = nil,
}

local function bufname_valid(bufname)
	return bufname:match("^/")
		or bufname:match("^[a-zA-Z]:")
		or bufname:match("^zipfile://")
		or bufname:match("^tarfile:")
end

local function lsp_start(target)
	vim.lsp.start({
		name = "roslyn",
		-- HACK: Roslyn requires the dynamicRegistration to be set to support diagnostics for some reason
		capabilities = vim.tbl_deep_extend("force", server_config.capabilities or {}, {
			textDocument = {
				diagnostic = {
					dynamicRegistration = true,
				},
			},
		}),
		cmd = require("roslyn.lsp").start_uds("dotnet", {
			vim.fs.joinpath(
				vim.fn.stdpath("data") --[[@as string]],
				"roslyn",
				"Microsoft.CodeAnalysis.LanguageServer.dll"
			),
			"--logLevel=Information",
			"--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
		}),
		root_dir = vim.fs.dirname(target),
		on_init = function(client)
			vim.notify("Roslyn client initialized for " .. target, vim.log.levels.INFO)
			client.notify("solution/open", {
				["solution"] = vim.uri_from_fname(target),
			})
		end,
		handlers = {
			[vim.lsp.protocol.Methods.client_registerCapability] = hacks.with_filtered_watchers(
				vim.lsp.handlers[vim.lsp.protocol.Methods.client_registerCapability]
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
end

-- Assigns the default capabilities from cmp if installed, and the capabilities from neovim
-- Merges it in with any user configured capabilities if provided
local function merge_config(config)
	local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
	local capabilities = ok
			and vim.tbl_deep_extend(
				"force",
				vim.lsp.protocol.make_client_capabilities(),
				cmp_nvim_lsp.default_capabilities()
			)
		or vim.lsp.protocol.make_client_capabilities()

	server_config.capabilities = capabilities
	server_config = vim.tbl_deep_extend("force", server_config, config or {})
end

local M = {}

function M.setup(config)
	server_config = merge_config(config)

	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
		pattern = { "cs" },
		callback = function(opt)
			local bufname = vim.api.nvim_buf_get_name(opt.buf)

			if vim.bo["buftype"] == "nofile" or not bufname_valid(bufname) then
				return
			end

			-- Finds possible targets
			local sln_dir = vim.fs.root(opt.buf, function(name)
				return name:match("%.sln$") ~= nil
			end)
			local targets = sln_dir and vim.fn.glob(vim.fs.joinpath(sln_dir, "*.sln"), true, true) or {}

			if #targets == 1 then
				return lsp_start(targets[1])
			elseif #targets > 1 then
				vim.notify("Multiple targets found. Use `CSTarget` to select target for buffer", vim.log.levels.INFO)
				vim.api.nvim_create_user_command("CSTarget", function()
					vim.ui.select(targets, { prompt = "Select target: " }, lsp_start)
				end, { desc = "Selects the target for the current buffer" })
			end
		end,
	})
end

return M
