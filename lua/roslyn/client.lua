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
function M.spawn(cmd, target, on_exit, on_attach, capabilities)
	local data_path = vim.fn.stdpath("data") --[[@as string]]
	local server_path = vim.fs.joinpath(data_path, "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")
	if not vim.uv.fs_stat(server_path) then
		vim.notify_once("Roslyn LSP server not installed. Run CSInstallRoslyn to install.", vim.log.levels.ERROR, { title = "Roslyn" })
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
		-- settings = {
		-- 	["csharp|background_analysis"] = {
		-- 		["dotnet_analyzer_diagnostics_scope"] = nil,
		-- 		["dotnet_compiler_diagnostics_scope"] = nil,
		-- 	},
		-- 	["csharp|code_lens"] = {
		-- 		["dotnet_enable_references_code_lens"] = nil,
		-- 		["dotnet_enable_tests_code_lens"] = nil,
		-- 	},
		-- 	["csharp|code_style"] = {
		-- 		["formatting"] = {
		-- 			["indentation_and_spacing"] = {
		-- 				["indent_size"] = nil,
		-- 				["indent_style"] = nil,
		-- 				["tab_width"] = nil,
		-- 			},
		-- 			["new_line"] = {
		-- 				["end_of_line"] = nil,
		-- 			},
		-- 		},
		-- 	},
		-- 	["csharp|completion"] = {
		-- 		["dotnet_provide_regex_completions"] = nil,
		-- 		["dotnet_show_completion_items_from_unimported_namespaces"] = true,
		-- 		["dotnet_show_name_completion_suggestions"] = true,
		-- 	},
		-- 	["csharp|highlighting"] = {
		-- 		["dotnet_highlight_related_json_components"] = nil,
		-- 		["dotnet_highlight_related_regex_components"] = nil,
		-- 	},
		-- 	["csharp|implement_type"] = {
		-- 		["dotnet_insertion_behavior"] = nil,
		-- 		["dotnet_property_generation_behavior"] = nil,
		-- 	},
		-- 	["csharp|inlay_hints"] = {
		-- 		["csharp_enable_inlay_hints_for_implicit_object_creation"] = nil,
		-- 		["csharp_enable_inlay_hints_for_implicit_variable_types"] = nil,
		-- 		["csharp_enable_inlay_hints_for_lambda_parameter_types"] = nil,
		-- 		["csharp_enable_inlay_hints_for_types"] = nil,
		-- 		["dotnet_enable_inlay_hints_for_indexer_parameters"] = nil,
		-- 		["dotnet_enable_inlay_hints_for_literal_parameters"] = nil,
		-- 		["dotnet_enable_inlay_hints_for_object_creation_parameters"] = nil,
		-- 		["dotnet_enable_inlay_hints_for_other_parameters"] = nil,
		-- 		["dotnet_enable_inlay_hints_for_parameters"] = nil,
		-- 		["dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix"] = nil,
		-- 		["dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name"] = nil,
		-- 		["dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent"] = nil,
		-- 	},
		-- 	["csharp|quick_info"] = {
		-- 		["dotnet_show_remarks_in_quick_info"] = true,
		-- 	},
		-- 	["csharp|symbol_search"] = {
		-- 		["dotnet_search_reference_assemblies"] = nil,
		-- 	},
		-- 	["navigation"] = {
		-- 		["dotnet_navigate_to_decompiled_sources"] = nil,
		-- 	},
		-- 	["projects"] = {
		-- 		["dotnet_binary_log_path"] = nil,
		-- 		["dotnet_load_in_process"] = nil,
		-- 	},
		-- 	["code_style"] = {
		-- 		["formatting"] = {
		-- 			["new_line"] = {
		-- 				["insert_final_newline"] = nil,
		-- 			},
		-- 		},
		-- 	},
		-- },
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
		},
		on_exit = on_exit,
	})

	if spawned.id == nil then
		return nil
	end

	return spawned
end

return M
