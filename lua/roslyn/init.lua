local util = require("lspconfig.util")

local server_config = {
	capabilities = nil,
}
local selected_targets = {}
local client_by_target = {} ---@type table<string, table|nil>
local targets_by_bufnr = {} ---@type table<number, string[]>

---Finds the possible Targets
---@param fname string @The name of the file to find possible targets for
---@return string[], (string|nil) @The possible targets.
local function find_possible_targets(fname)
	local targets = {}

	local sln_dir = util.root_pattern("*sln")(fname)
	if sln_dir then
		vim.list_extend(targets, vim.fn.glob(util.path.join(sln_dir, "*.sln"), true, true))
	end

	return targets, targets[1]
end

local M = {}

local function attach_or_spawn(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local target = selected_targets[bufnr]
	if target == nil then
		return
	elseif not util.path.is_file(target) then
		selected_targets[target] = nil
		return
	end

	local client = client_by_target[target]
	if client == nil then
		client = require("roslyn.client").spawn(target, function()
			client_by_target[target] = nil
		end, server_config.capabilities)
		if client == nil then
			vim.notify("Failed to start Roslyn client for " .. vim.fn.fnamemodify(target, ":~:."), vim.log.levels.ERROR)
			return
		end
		client_by_target[target] = client
	end

	client:attach(bufnr)
end

local function select_target(bufnr)
	vim.ui.select(targets_by_bufnr[bufnr], {
		prompt = "Select target",
	}, function(selected)
		selected_targets[bufnr] = selected
		attach_or_spawn(bufnr)
	end)
end

local function init_buf_targets(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(bufnr)

	if vim.bo["buftype"] == "nofile" or targets_by_bufnr[bufnr] ~= nil or not util.bufname_valid(bufname) then
		return
	end

	local bufpath = util.path.sanitize(bufname)
	local targets, prefered_target = find_possible_targets(bufpath)
	if prefered_target then
		selected_targets[bufnr] = prefered_target
	elseif #targets > 1 then
		vim.api.nvim_create_user_command("CSTarget", function()
			select_target(bufnr)
		end, { desc = "Selects the target for the current buffer" })

		local active_possible_targets = {}
		for _, target in ipairs(targets) do
			if client_by_target[target] then
				table.insert(active_possible_targets, target)
			end
		end
		if #active_possible_targets == 1 then
			selected_targets[bufnr] = active_possible_targets[1]
		end
	end
	targets_by_bufnr[bufnr] = targets

	if selected_targets[bufnr] == nil and #targets > 0 then
		select_target(bufnr)
	end
end

function M.setup(config)
	server_config = vim.tbl_deep_extend("force", server_config, config or {})

	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "cs" },
		callback = function(opt)
			init_buf_targets(opt.buf)
			attach_or_spawn(opt.buf)
		end,
		group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
		desc = "",
	})
end

return M
