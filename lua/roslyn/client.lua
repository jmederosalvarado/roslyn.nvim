local roslyn_lsp_rpc = require("roslyn.lsp")
local hacks = require("roslyn.hacks")

---@class RoslynClient
---@field id number?
---@field target string
---@field private _bufnrs number[] | nil
local RoslynClient = {}

function RoslynClient:initialize()
	for _, bufnr in ipairs(self._bufnrs) do
		if not vim.lsp.buf_attach_client(bufnr, self.id) then
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
function M.spawn(cmd, target, settings, on_exit, on_attach, capabilities)
	local data_path = vim.fn.stdpath("data") --[[@as string]]
	local server_path = vim.fs.joinpath(data_path, "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")
	if not vim.uv.fs_stat(server_path) then
		vim.notify_once(
			"Roslyn LSP server not installed. Run CSInstallRoslyn to install.",
			vim.log.levels.ERROR,
			{ title = "Roslyn" }
		)
		return
	end

	-- target should be a `.sln` file
	if target:sub(-4) ~= ".sln" then
		vim.notify("Roslyn target should be a `.sln` file", vim.log.levels.ERROR)
		return
	end

	local server_args = {
		server_path,
		"--logLevel=Information",
		"--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
	}

	local target_uri = vim.uri_from_fname(target)

	-- capabilities = vim.tbl_deep_extend("force", capabilities, {
	-- 	workspace = {
	-- 		didChangeWatchedFiles = {
	-- 			dynamicRegistration = false,
	-- 		},
	-- 	},
	-- })

	local spawned = RoslynClient.new(target)

	---@diagnostic disable-next-line: missing-fields
	spawned.id = vim.lsp.start_client({
		name = "roslyn",
		capabilities = capabilities,
		settings = settings,
		-- cmd = hacks.wrap_server_cmd(vim.lsp.rpc.connect("127.0.0.1", 8080)),
		cmd = hacks.wrap_server_cmd(roslyn_lsp_rpc.start_uds(cmd, server_args)),
		root_dir = vim.fn.getcwd(), ---@diagnostic disable-line: assign-type-mismatch
		on_init = function(client)
			vim.notify(
				"Roslyn client initialized for target " .. vim.fn.fnamemodify(target, ":~:."),
				vim.log.levels.INFO
			)

			client.notify("solution/open", {
				["solution"] = target_uri,
			})
		end,
		on_attach = vim.schedule_wrap(function(client, bufnr)
			on_attach(client, bufnr)

			-- vim.api.nvim_buf_attach(bufnr, false, {
			--     on_lines = function(_, bufnr, changedtick, firstline, lastline, new_lastline)
			--         -- we are only interested in one character insertions
			--         if firstline ~= lastline or new_lastline ~= lastline then
			--             return
			--         end
			--
			--         -- https://github.com/dotnet/vscode-csharp/blob/main/src/lsptoolshost/onAutoInsert.ts
			--     end,
			-- })
		end),
		handlers = {
			[vim.lsp.protocol.Methods.textDocument_publishDiagnostics] = hacks.with_fixed_diagnostics_tags(
				vim.lsp.handlers[vim.lsp.protocol.Methods.textDocument_publishDiagnostics]
			),
			[vim.lsp.protocol.Methods.textDocument_diagnostic] = hacks.with_fixed_diagnostics_tags(
				vim.lsp.handlers[vim.lsp.protocol.Methods.textDocument_diagnostic]
			),
			[vim.lsp.protocol.Methods.client_registerCapability] = hacks.with_filtered_watchers(
				vim.lsp.handlers[vim.lsp.protocol.Methods.client_registerCapability]
			),
			["workspace/projectInitializationComplete"] = function()
				vim.notify("Roslyn project initialization complete", vim.log.levels.INFO)
				spawned:initialize()
			end,
            ["workspace/_roslyn_projectHasUnresolvedDependencies"] = function()
                vim.notify("Detected missing dependencies. Run dotnet restore command.", vim.log.levels.ERROR)
                return vim.NIL
            end,
		},
		on_exit = on_exit,
	})

	if spawned.id == nil then
		return nil
	end

	return spawned
end

return M
