local util = require("lspconfig.util")

local function set_selected_target(bufnr, target)
	vim.g["RoslynSelectedTarget" .. bufnr] = target
end

local function get_selected_target(bufnr)
	return vim.g["RoslynSelectedTarget" .. bufnr]
end

---Finds the possible Targets
---@param fname string @The name of the file to find possible targets for
---@return string[], (string|nil) @The possible targets.
local function find_possible_targets(fname)
	local prefered_target = nil
	local targets = {}

	local sln_dir = util.root_pattern("*sln")(fname)
	if sln_dir then
		vim.list_extend(targets, vim.fn.glob(util.path.join(sln_dir, "*.sln"), true, true))
	end

	if #targets == 1 then
		prefered_target = targets[1]
	end

	-- local csproj_dir = util.root_pattern("*csproj")(fname)
	-- if csproj_dir then
	-- 	table.insert(targets, csproj_dir)
	-- end
	--
	-- local git_dir = util.root_pattern(".git")(fname)
	-- if git_dir and not vim.tbl_contains(targets, git_dir) then
	-- 	table.insert(targets, git_dir)
	-- end
	--
	-- local cwd = vim.fn.getcwd()
	-- if util.path.is_descendant(cwd, fname) and not vim.tbl_contains(targets, cwd) then
	-- 	table.insert(targets, cwd)
	-- end
	--
	-- if #targets == 1 then
	-- 	prefered_target = targets[1]
	-- end

	return targets, prefered_target
end

local M = {}

M.server_config = {
	dotnet_cmd = "dotnet",
	roslyn_version = "4.8.0-3.23475.7",
	capabilities = nil,
	on_attach = nil,
	settings = nil,
}
M.client_by_target = {} ---@type table<string, table|nil>
M.targets_by_bufnr = {} ---@type table<number, string[]>

function M.init_buf_targets(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.api.nvim_buf_get_option(bufnr, "buftype") == "nofile" then
		return
	end

	if M.targets_by_bufnr[bufnr] ~= nil then
		return
	end

	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if not util.bufname_valid(bufname) then
		return
	end

	local bufpath = util.path.sanitize(bufname)
	local targets, prefered_target = find_possible_targets(bufpath)
	if prefered_target then
		set_selected_target(bufnr, prefered_target)
	elseif #targets > 1 then
		vim.api.nvim_create_user_command("CSTarget", function()
			M.select_target(vim.api.nvim_get_current_buf())
		end, { desc = "Selects the target for the current buffer" })

		local active_possible_targets = {}
		for _, target in ipairs(targets) do
			if M.client_by_target[target] then
				table.insert(active_possible_targets, target)
			end
		end
		if #active_possible_targets == 1 then
			set_selected_target(bufnr, active_possible_targets[1])
		end
	end
	M.targets_by_bufnr[bufnr] = targets

	if get_selected_target(bufnr) == nil and #targets > 0 then
		M.select_target(vim.api.nvim_get_current_buf())
	end
end

function M.attach_or_spawn(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local target = get_selected_target(bufnr)
	if target == nil then
		return
	elseif not util.path.is_file(target) then
		set_selected_target(bufnr, nil)
		return
	end

	local client = M.client_by_target[target]
	if client == nil then
		client = require("roslyn.client").spawn(M.server_config.dotnet_cmd, target, M.server_config.settings, function()
			M.client_by_target[target] = nil
		end, M.server_config.on_attach, M.server_config.capabilities)
		if client == nil then
			vim.notify("Failed to start Roslyn client for " .. vim.fn.fnamemodify(target, ":~:."), vim.log.levels.ERROR)
			return
		end
		M.client_by_target[target] = client
	end

	client:attach(bufnr)
end

function M.select_target(bufnr)
	vim.ui.select(M.targets_by_bufnr[bufnr], {
		prompt = "Select target",
	}, function(selected)
		set_selected_target(bufnr, selected)
		M.attach_or_spawn(bufnr)
	end)
end

function M.setup_autocmds()
	local lsp_group = vim.api.nvim_create_augroup("Roslyn", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "cs" },
		callback = function(opt)
			M.init_buf_targets(opt.buf)
			M.attach_or_spawn(opt.buf)
		end,
		group = lsp_group,
		desc = "",
	})
end

function M.setup_cmds()
	vim.api.nvim_create_user_command("CSInstallRoslyn", function()
		require("roslyn.install").install(M.server_config.dotnet_cmd, M.server_config.roslyn_version)
	end, { desc = "Installs the roslyn server" })
end

function M.setup(config)
	if config ~= nil then
		M.server_config = vim.tbl_deep_extend("force", M.server_config, config)
	end
	M.setup_cmds()
	M.setup_autocmds()
end

return M
