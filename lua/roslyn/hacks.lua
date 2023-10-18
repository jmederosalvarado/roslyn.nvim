local M = {}

-- see https://github.com/dotnet/roslyn/issues/70392
-- fixed https://github.com/dotnet/roslyn/pull/70407
function M.wrap_rpc_client(client)
	local result = {}

	---@private
	function result.is_closing()
		return client.is_closing()
	end

	---@private
	function result.terminate()
		client.terminate()
	end

	--- Sends a request to the LSP server and runs {callback} upon response.
	---
	---@param method (string) The invoked LSP method
	---@param params (table|nil) Parameters for the invoked LSP method
	---@param callback fun(err: lsp.ResponseError | nil, result: any) Callback to invoke
	---@param notify_reply_callback (function|nil) Callback to invoke as soon as a request is no longer pending
	---@return boolean success, integer|nil request_id true, message_id if request could be sent, `false` if not
	function result.request(method, params, callback, notify_reply_callback)
		return client.request(method, params, callback, notify_reply_callback)
	end

	--- Sends a notification to the LSP server.
	---@param method (string) The invoked LSP method
	---@param params (table|nil): Parameters for the invoked LSP method
	---@return boolean `true` if notification could be sent, `false` if not
	function result.notify(method, params)
		if method == vim.lsp.protocol.Methods.textDocument_didChange then
			---@cast params -nil Assert that params is not nil
			local changes = params.contentChanges
			for _, change in ipairs(changes) do
				local notified = client.notify(method, {
					textDocument = params.textDocument,
					contentChanges = { change },
				})
				if not notified then
					return notified
				end
			end
			return true
		end
		return client.notify(method, params)
	end

	return result
end

function M.wrap_server_cmd(cmd_fn)
	return function(...)
		return M.wrap_rpc_client(cmd_fn(...))
	end
end

function M.fix_diagnostics_tags(diagnostics)
	for _, diagnostic in ipairs(diagnostics) do
		if diagnostic.tags ~= nil then
			diagnostic.tags = vim.tbl_filter(function(tag)
				return tag == vim.lsp.protocol.DiagnosticTag.Unnecessary
					and tag == vim.lsp.protocol.DiagnosticTag.Deprecated
			end, diagnostic.tags)
		end
	end
end

function M.with_fixed_diagnostics_tags(handler)
	return function(err, res, ctx, config)
		local diagnostics = res and res.items or {}
		for _, diagnostic in ipairs(diagnostics) do
			if diagnostic.tags ~= nil then
				diagnostic.tags = vim.tbl_filter(function(tag)
					return tag == vim.lsp.protocol.DiagnosticTag.Unnecessary
						and tag == vim.lsp.protocol.DiagnosticTag.Deprecated
				end, diagnostic.tags)
			end
		end
		return handler(err, res, ctx, config)
	end
end

function M.with_filtered_watchers(handler)
	return function(err, res, ctx, config)
		for _, reg in ipairs(res.registrations) do
			if reg.method == vim.lsp.protocol.Methods.workspace_didChangeWatchedFiles then
				reg.registerOptions.watchers = vim.tbl_filter(function(watcher)
					if type(watcher.globPattern) == "table" then
						local base_uri = nil ---@type string?
						if type(watcher.globPattern.baseUri) == "string" then
							base_uri = watcher.globPattern.baseUri
							-- remove trailing slash if present
							if base_uri:sub(-1) == "/" then
								watcher.globPattern.baseUri = base_uri:sub(1, -2)
							end
						elseif type(watcher.globPattern.baseUri) == "table" then
							base_uri = watcher.globPattern.baseUri.uri
							-- remove trailing slash if present
							if base_uri:sub(-1) == "/" then
								watcher.globPattern.baseUri.uri = base_uri:sub(1, -2)
							end
						end

						if base_uri ~= nil then
							local base_dir = vim.uri_to_fname(base_uri)
							-- use luv to check if baseDir is a directory
							local stat = vim.loop.fs_stat(base_dir)
							return stat ~= nil and stat.type == "directory"
						end
					end

					return true
				end, reg.registerOptions.watchers)
			end
		end
		return handler(err, res, ctx, config)
	end
end

return M
