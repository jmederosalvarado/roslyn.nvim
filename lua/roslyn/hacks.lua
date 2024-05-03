local M = {}

-- TODO: Looks like this isn't needed?
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

-- TODO: This is probably needed for now...
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
