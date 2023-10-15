local M = {}

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

return M
