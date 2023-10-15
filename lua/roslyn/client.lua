local roslyn_lsp_rpc = require("roslyn.lsp")
local hacks = require("roslyn.hacks")

---@class RoslynClient
---@field id number
---@field target string
---@field private _bufnrs number[] | nil
local RoslynClient = {}

function RoslynClient:initialize()
	for _, bufnr in ipairs(self._bufnrs) do
		if vim.lsp.buf_attach_client(bufnr, self.id) == false then
			local target = vim.fn.fnamemodify(self.target, ":~:.")
			local bufname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":~:.")
			vim.notify(string.format("Failed to attach Roslyn(%s) for %s", target, bufname), vim.log.levels.ERROR)
		end
	end
	self._bufnrs = nil
end

---Attaches(or schedules to attach) the client to a buffer
---@param self RoslynClient
---@param bufnr integer
---@return boolean
function RoslynClient:attach(bufnr)
	if self._bufnrs then
		table.insert(self._bufnrs, bufnr)
		return true
	else
		return vim.lsp.buf_attach_client(bufnr, self.id)
	end
end

---@param target string
---@return RoslynClient
function RoslynClient.new(target)
	return setmetatable({
		target = target,

		id = nil,
		_bufnrs = {},
		_initialized = false,
	}, {
		__index = RoslynClient,
	})
end

local M = {}

---Creates a new Roslyn lsp server
---@param cmd string
---@param target string
---@param on_attach function
---@param capabilities table
function M.spawn(cmd, target, on_exit, on_attach, capabilities)
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

	local target_uri = vim.uri_from_fname(target)

	local on_diagnostic = vim.lsp.diagnostic.on_diagnostic
	local on_publish_diagnostic = vim.lsp.diagnostic.on_publish_diagnostics

	capabilities.workspace = vim.tbl_deep_extend("force", capabilities, {
		workspace = {
			didChangeWatchedFiles = {
				dynamicRegistration = false,
			},
		},
	})

	local client = RoslynClient.new(target)

	client.id = vim.lsp.start_client({
		name = "roslyn",
		capabilities = capabilities,
		-- see https://github.com/dotnet/roslyn/issues/70392
		cmd = hacks.wrap_server_cmd(vim.lsp.rpc.connect("127.0.0.1", 8080)),
		-- cmd = hacks.wrap_server_cmd(roslyn_lsp_rpc.start_uds(cmd, server_args)),
		root_dir = vim.fn.getcwd(),
		on_init = function(client)
			vim.notify(
				"Roslyn client initialized for target " .. vim.fn.fnamemodify(target, ":~:."),
				vim.log.levels.INFO
			)

			client.notify("solution/open", {
				["solution"] = target_uri,
			})
		end,
		on_attach = vim.schedule_wrap(on_attach),
		handlers = {
			["textDocument/publishDiagnostics"] = function(err, res, ctx, config)
				if res.items ~= nil then
					fixes.fix_diagnostics_tags(res.items)
				end
				return on_publish_diagnostic(err, res, ctx, config)
			end,
			["textDocument/diagnostic"] = function(err, res, ctx, config)
				if res.items ~= nil then
					fixes.fix_diagnostics_tags(res.items)
				end
				return on_diagnostic(err, res, ctx, config)
			end,
			["workspace/projectInitializationComplete"] = function()
				vim.notify("Roslyn project initialization complete", vim.log.levels.INFO)
				client:initialize()
			end,
		},
		on_exit = on_exit,
	})

	if client.id == nil then
		return nil
	end

	return client
end

return M
