local hacks = require("roslyn.hacks")
local roslyn_lsp_rpc = require("roslyn.lsp")

local server_config = {
	capabilities = nil,
}

local function bufname_valid(bufname)
	if
		bufname:match("^/")
		or bufname:match("^[a-zA-Z]:")
		or bufname:match("^zipfile://")
		or bufname:match("^tarfile:")
	then
		return true
	end
	return false
end

---Finds the possible Targets
---@param bufnr number @The bufnr of the file to find possible targets for
---@return string[], (string|nil) @The possible targets.
local function find_possible_targets(bufnr)
	local targets = {}

	local sln_dir = vim.fs.root(bufnr, function(name)
		return name:match("%.sln$") ~= nil
	end)
	if sln_dir then
		vim.list_extend(targets, vim.fn.glob(vim.fs.joinpath(sln_dir, "*.sln"), true, true))
	end

	return targets, targets[1]
end

local function lsp_start(target)
	local data_path = vim.fn.stdpath("data") --[[@as string]]
	local server_path = vim.fs.joinpath(data_path, "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")
	local server_args = {
		server_path,
		"--logLevel=Information",
		"--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
	}

	-- HACK: Roslyn requires the dynamicRegistration to be set to support diagnostics for some reason
	local capabilities = vim.tbl_deep_extend("force", server_config.capabilities or {}, {
		textDocument = {
			diagnostic = {
				dynamicRegistration = true,
			},
		},
	})

	vim.lsp.start({
		name = "roslyn",
		capabilities = capabilities,
		cmd = roslyn_lsp_rpc.start_uds("dotnet", server_args),
		root_dir = vim.fs.dirname(target),
		on_init = function(client)
			vim.notify("Roslyn client initialized for " .. target, vim.log.levels.INFO)

			client.notify("solution/open", {
				["solution"] = vim.uri_from_fname(target),
			})
		end,
		handlers = {
			-- [vim.lsp.protocol.Methods.textDocument_publishDiagnostics] = hacks.with_fixed_diagnostics_tags(
			-- 	vim.lsp.handlers[vim.lsp.protocol.Methods.textDocument_publishDiagnostics]
			-- ),
			-- [vim.lsp.protocol.Methods.textDocument_diagnostic] = hacks.with_fixed_diagnostics_tags(
			-- 	vim.lsp.handlers[vim.lsp.protocol.Methods.textDocument_diagnostic]
			-- ),
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

local targets_by_bufnr = {} ---@type table<number, string[]>

local M = {}

function M.setup(config)
	server_config = vim.tbl_deep_extend("force", server_config, config or {})

	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
		pattern = { "cs" },
		callback = function(opt)
			local bufnr = opt.buf
			local bufname = vim.api.nvim_buf_get_name(bufnr)

			if vim.bo["buftype"] == "nofile" or targets_by_bufnr[bufnr] ~= nil or not bufname_valid(bufname) then
				return
			end

			local targets, prefered_target = find_possible_targets(bufnr)
			if prefered_target then
				return lsp_start(prefered_target)
			elseif #targets > 1 then
				vim.ui.select(targets, { prompt = "Select target" }, lsp_start)
			end
			targets_by_bufnr[bufnr] = targets
		end,
	})
end

return M
