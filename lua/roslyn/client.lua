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
---@param target string
---@param capabilities table
function M.spawn(target, on_exit, capabilities)
	local data_path = vim.fn.stdpath("data") --[[@as string]]
	local server_path = vim.fs.joinpath(data_path, "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")
	if not vim.uv.fs_stat(server_path) then
		-- Either install it via vscode, and move it from ~/.vscode/extensions/ms-dotnettools.csharp-2.28.8-darwin-arm64/.roslyn to ~/.local/share/nvim/roslyn
		-- Or install it another way manually or something
		vim.notify_once(
			string.format("Roslyn LSP server not found. Looking for %s", server_path),
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

	local spawned = RoslynClient.new(target)

	-- HACK: Roslyn requires the dynamicRegistration to be set to support diagnostics for some reason
	capabilities = vim.tbl_deep_extend("force", capabilities or {}, {
		textDocument = {
			diagnostic = {
				dynamicRegistration = true,
			},
		},
	})

	spawned.id = vim.lsp.start_client({
		name = "roslyn",
		capabilities = capabilities,
		cmd = roslyn_lsp_rpc.start_uds("dotnet", server_args),
		root_dir = vim.uv.cwd(),
		on_init = function(client)
			vim.notify(
				"Roslyn client initialized for target " .. vim.fn.fnamemodify(target, ":~:."),
				vim.log.levels.INFO
			)

			client.notify("solution/open", {
				["solution"] = target_uri,
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
