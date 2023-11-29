local M = {}

function M.bufname_valid(bufname)
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

function M.sanitize(path)
    if is_windows then
        path = path:sub(1, 1):upper() .. path:sub(2)
        path = path:gsub('\\', '/')
    end
    return path
end

return M
