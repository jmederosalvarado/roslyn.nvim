local roslyn_lsp_rpc = require("roslyn.lsp")

local function fix_diagnostics_tags(diagnostics)
	for _, diagnostic in ipairs(diagnostics) do
		if diagnostic.tags ~= nil then
			diagnostic.tags = vim.tbl_filter(function(tag)
				return tag == vim.lsp.protocol.DiagnosticTag.Unnecessary
					and tag == vim.lsp.protocol.DiagnosticTag.Deprecated
			end, diagnostic.tags)
		end
	end
end

local M = {}

---Creates a new OmniSharper lsp server
---@param cmd string
---@param target string
---@param on_attach function
---@param capabilities table
function M.spawn(cmd, target, on_attach, capabilities)
	local server_path = vim.fs.joinpath(vim.fn.stdpath("data"), "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")
	if not vim.uv.fs_stat(server_path) then
		vim.notify_once("Roslyn LSP server not installed", vim.log.levels.ERROR, { title = "Roslyn" })
		return
	end

	local server_args = {
		server_path,
		"--logLevel=Information",
		"--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
	}

	-- capabilities = vim.tbl_deep_extend("keep", capabilities, {
	-- 	workspace = {
	-- 		configuration = true,
	-- 	},
	-- })

	local on_diagnostic = vim.lsp.diagnostic.on_diagnostic
	local on_publish_diagnostic = vim.lsp.diagnostic.on_publish_diagnostics

	return vim.lsp.start_client({
		name = "roslyn",
		capabilities = capabilities,
		-- cmd = vim.lsp.rpc.connect("127.0.0.1", 8080),
		cmd = roslyn_lsp_rpc.start_uds(cmd, server_args),
		on_init = function(client)
			vim.notify(
				"Roslyn client initialized for target " .. vim.fn.fnamemodify(target, ":~:."),
				vim.log.levels.INFO
			)

			client.notify("solution/open", {
				["solution"] = vim.uri_from_fname(target),
			})
		end,
		on_attach = vim.schedule_wrap(on_attach),
		handlers = {
			["textDocument/publishDiagnostics"] = function(err, res, ctx, config)
				if res.items ~= nil then
					fix_diagnostics_tags(res.items)
				end
				return on_publish_diagnostic(err, res, ctx, config)
			end,
			["textDocument/diagnostic"] = function(err, res, ctx, config)
				if res.items ~= nil then
					fix_diagnostics_tags(res.items)
				end
				return on_diagnostic(err, res, ctx, config)
			end,
			["workspace/projectInitializationComplete"] = function()
				vim.notify("Roslyn project initialization complete", vim.log.levels.INFO)
			end,
		},
		on_exit = function()
			M.client_by_target[target] = nil
		end,
	})
end

return M
