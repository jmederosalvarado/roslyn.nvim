---@param file_paths string[]
---@param search_string string
local function find_string_in_files(file_paths, search_string)
    for _, file_path in ipairs(file_paths) do
        local file = io.open(file_path, "r")

        if not file then
            return nil
        end

        local content = file:read("*a")
        file:close()

        if content:find(search_string, 1, true) then
            return file_path
        end
    end

    return nil
end

local M = {}

---@param buffer integer
function M.get_solution_directory(buffer)
    return vim.fs.root(buffer, function(name)
        return name:match("%.sln$") ~= nil
    end)
end

---@param buffer integer
function M.get_all_solution_files(buffer)
    local sln_dir = M.get_solution_directory(buffer)
    if not sln_dir then
        return
    end

    return vim.fn.glob(vim.fs.joinpath(sln_dir, "*.sln"), true, true)
end

---@param buffer integer
function M.get_current_solution_file(buffer)
    local sln_files = M.get_all_solution_files(buffer)

    if not sln_files then
        return
    end

    local csproj_dir = vim.fs.root(buffer, function(name)
        return name:match("%.csproj$") ~= nil
    end)

    if not csproj_dir then
        return
    end

    local csproj_files = vim.fn.glob(vim.fs.joinpath(csproj_dir, "*.csproj"), true, true)

    if #csproj_files > 1 then
        return nil -- enum?
    end

    local csproj_filename = vim.fn.fnamemodify(csproj_files[1], ":t")

    return find_string_in_files(sln_files, csproj_filename)
end

return M
