--- Review mode: browse every diff against a target branch (or the working tree)
--- one file at a time, in a dedicated tab.
---
---   :Review [rev]     review against <rev> (default: origin/master)
---   :ReviewChanges    review uncommitted changes (vs HEAD)
---   :ReviewQuit       leave review mode
---
--- While review mode is active:
---   N            next file
---   n            previous file
---   <leader>gt   toggle side-by-side / inline diff
---   <leader>gf   pick a file from the review list
---   <leader>gq   quit review mode
---   ]c / [c      next/previous hunk (built-in diff motions)

local M = {}

local DEFAULT_BASES = { "origin/master", "origin/main", "master", "main" }

local state = {
	active = false,
	tab = nil,
	root = nil,
	files = {},
	idx = 1,
	base = nil, -- resolved rev the diff is taken from (merge-base sha, or HEAD)
	label = nil, -- human readable base, e.g. "origin/master"
	mode = "side", -- "side" | "inline"
	maps_on = false,
	saved_maps = {},
	saved_diffopt = nil,
}

--------------------------------------------------------------------------- git

local function git(args)
	local cmd = { "git", "-C", state.root or vim.fn.getcwd() }
	vim.list_extend(cmd, args)
	local out = vim.fn.systemlist(cmd)
	return out, vim.v.shell_error
end

local function repo_root()
	local out = vim.fn.systemlist({ "git", "-C", vim.fn.getcwd(), "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return out[1]
end

local function rev_exists(rev)
	local _, code = git({ "rev-parse", "--verify", "--quiet", rev .. "^{commit}" })
	return code == 0
end

local function default_base()
	for _, candidate in ipairs(DEFAULT_BASES) do
		if rev_exists(candidate) then
			return candidate
		end
	end
	return nil
end

--- Resolve the commit the diff is taken from. For a branch we use the
--- merge-base so only the changes belonging to this branch show up.
local function resolve_base(label)
	if label == "HEAD" then
		return "HEAD"
	end
	local out, code = git({ "merge-base", "HEAD", label })
	if code ~= 0 or not out[1] then
		return label
	end
	return out[1]
end

--- @return table[] list of { status = "M", path = "a/b.lua", old = "a/c.lua"|nil }
local function collect_files(base)
	local files = {}

	local out, code = git({ "diff", "--name-status", "--find-renames", base })
	if code ~= 0 then
		return files
	end
	for _, line in ipairs(out) do
		local parts = vim.split(line, "\t", { plain = true })
		local status = parts[1]
		if status and parts[2] then
			local entry = { status = status:sub(1, 1), path = parts[2] }
			if entry.status == "R" or entry.status == "C" then
				entry.old = parts[2]
				entry.path = parts[3] or parts[2]
			end
			table.insert(files, entry)
		end
	end

	-- untracked files count as new work worth reviewing
	local untracked = git({ "ls-files", "--others", "--exclude-standard" })
	for _, path in ipairs(untracked) do
		if path ~= "" then
			table.insert(files, { status = "?", path = path })
		end
	end

	table.sort(files, function(a, b)
		return a.path < b.path
	end)
	return files
end

local function base_content(entry)
	if entry.status == "A" or entry.status == "?" then
		return {}
	end
	local out, code = git({ "show", state.base .. ":" .. (entry.old or entry.path) })
	if code ~= 0 then
		return {}
	end
	return out
end

local function unified_diff(entry)
	if entry.status == "?" then
		local out = git({ "diff", "--no-index", "--", "/dev/null", entry.path })
		return out
	end
	local out = git({ "diff", state.base, "--", entry.old or entry.path, entry.path })
	return out
end

------------------------------------------------------------------------ buffers

local seq = 0

local function scratch(name, lines, filetype)
	seq = seq + 1
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	if filetype then
		vim.bo[buf].filetype = filetype
	end
	pcall(vim.api.nvim_buf_set_name, buf, string.format("review://%d/%s", seq, name))
	return buf
end

local STATUS_LABEL = {
	M = "modified",
	A = "added",
	D = "deleted",
	R = "renamed",
	C = "copied",
	["?"] = "untracked",
}

local function winbar(entry, side)
	return string.format(
		" [%d/%d] %s  %s · %s",
		state.idx,
		#state.files,
		entry.path,
		STATUS_LABEL[entry.status] or entry.status,
		side
	)
end

------------------------------------------------------------------------ render

local function open_current_version(entry)
	local abs = state.root .. "/" .. entry.path
	if entry.status ~= "D" and vim.uv.fs_stat(abs) then
		vim.cmd("edit " .. vim.fn.fnameescape(abs))
	else
		local buf = scratch(entry.path .. " (deleted)", {}, vim.filetype.match({ filename = entry.path }))
		vim.api.nvim_win_set_buf(0, buf)
	end
end

local function render()
	local entry = state.files[state.idx]
	if not entry then
		return
	end

	vim.cmd("silent! diffoff!")
	vim.cmd("silent! only")

	if state.mode == "inline" then
		local lines = unified_diff(entry)
		if #lines == 0 then
			lines = { "-- no textual diff (binary or mode change only) --" }
		end
		local buf = scratch(entry.path .. " (diff)", lines, "diff")
		vim.api.nvim_win_set_buf(0, buf)
		vim.wo.winbar = winbar(entry, state.label .. " → working tree, inline")
		vim.wo.wrap = false
		return
	end

	-- side by side: base on the left, working tree on the right
	open_current_version(entry)
	local right = vim.api.nvim_get_current_win()
	vim.cmd("diffthis")
	vim.wo[right].winbar = winbar(entry, "working tree")

	local ft = vim.bo.filetype
	if ft == "" then
		ft = vim.filetype.match({ filename = entry.path })
	end
	local buf = scratch(entry.path .. "@" .. state.label, base_content(entry), ft)

	vim.cmd("leftabove vsplit")
	local left = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(left, buf)
	vim.cmd("diffthis")
	vim.wo[left].winbar = winbar(entry, state.label)

	vim.api.nvim_set_current_win(right)
	vim.cmd("normal! gg")
	if vim.fn.line(".") == 1 then
		vim.cmd("silent! normal! ]c")
	end
	vim.cmd("normal! zz")
end

------------------------------------------------------------------------ keymaps

local function keys()
	return {
		{ "n", "N", M.next, "Review: next file" },
		{ "n", "n", M.prev, "Review: previous file" },
		{ "n", "<leader>gt", M.toggle_mode, "Review: toggle side/inline diff" },
		{ "n", "<leader>gf", M.pick, "Review: pick file" },
		{ "n", "<leader>gq", M.quit, "Review: quit review mode" },
	}
end

local function activate_maps()
	if state.maps_on then
		return
	end
	state.saved_maps = {}
	for _, k in ipairs(keys()) do
		local mode, lhs, rhs, desc = k[1], k[2], k[3], k[4]
		local previous = vim.fn.maparg(lhs, mode, false, true)
		table.insert(state.saved_maps, {
			mode = mode,
			lhs = lhs,
			map = (type(previous) == "table" and next(previous)) and previous or nil,
		})
		vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
	end
	state.maps_on = true
end

local function deactivate_maps()
	if not state.maps_on then
		return
	end
	for _, saved in ipairs(state.saved_maps) do
		pcall(vim.keymap.del, saved.mode, saved.lhs)
		if saved.map then
			pcall(vim.fn.mapset, saved.map)
		end
	end
	state.saved_maps = {}
	state.maps_on = false
end

local group = vim.api.nvim_create_augroup("CostisReview", { clear = true })

local function watch_tab()
	vim.api.nvim_create_autocmd({ "TabEnter", "TabClosed" }, {
		group = group,
		callback = function()
			if not state.active then
				return true
			end
			if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
				if vim.api.nvim_get_current_tabpage() == state.tab then
					activate_maps()
				else
					deactivate_maps()
				end
			else
				M.quit()
				return true
			end
		end,
	})
	vim.api.nvim_create_autocmd("TabLeave", {
		group = group,
		callback = function()
			if not state.active then
				return true
			end
			deactivate_maps()
		end,
	})
end

-------------------------------------------------------------------------- api

function M.goto_file(idx)
	if not state.active or #state.files == 0 then
		return
	end
	if idx < 1 then
		idx = #state.files
	elseif idx > #state.files then
		idx = 1
	end
	state.idx = idx
	render()
end

function M.next()
	M.goto_file(state.idx + 1)
end

function M.prev()
	M.goto_file(state.idx - 1)
end

function M.toggle_mode()
	if not state.active then
		return
	end
	state.mode = state.mode == "side" and "inline" or "side"
	render()
end

function M.pick()
	if not state.active then
		return
	end
	vim.ui.select(state.files, {
		prompt = "Review files (" .. state.label .. ")",
		format_item = function(entry)
			return string.format("%s  %s", entry.status, entry.path)
		end,
	}, function(_, idx)
		if idx then
			M.goto_file(idx)
		end
	end)
end

function M.quit()
	if not state.active then
		return
	end
	state.active = false
	deactivate_maps()
	vim.api.nvim_clear_autocmds({ group = group })

	if state.saved_diffopt then
		vim.opt.diffopt = state.saved_diffopt
		state.saved_diffopt = nil
	end

	local tab = state.tab
	state.tab = nil
	if tab and vim.api.nvim_tabpage_is_valid(tab) and #vim.api.nvim_list_tabpages() > 1 then
		local current = vim.api.nvim_get_current_tabpage()
		vim.api.nvim_set_current_tabpage(tab)
		vim.cmd("silent! diffoff!")
		vim.cmd("tabclose")
		if current ~= tab and vim.api.nvim_tabpage_is_valid(current) then
			vim.api.nvim_set_current_tabpage(current)
		end
	else
		vim.cmd("silent! diffoff!")
	end
	vim.notify("Review mode ended", vim.log.levels.INFO)
end

--- @param label string|nil revision to review against; "HEAD" for uncommitted work
function M.start(label)
	if state.active then
		M.quit()
	end

	local root = repo_root()
	if not root then
		vim.notify("Not inside a git repository", vim.log.levels.ERROR)
		return
	end
	state.root = root

	label = label and label ~= "" and label or default_base()
	if not label then
		vim.notify(
			"No default base branch found (tried " .. table.concat(DEFAULT_BASES, ", ") .. ")",
			vim.log.levels.ERROR
		)
		return
	end
	if label ~= "HEAD" and not rev_exists(label) then
		vim.notify("Unknown revision: " .. label, vim.log.levels.ERROR)
		return
	end

	state.label = label
	state.base = resolve_base(label)
	state.files = collect_files(state.base)

	if #state.files == 0 then
		vim.notify("No changes against " .. label, vim.log.levels.WARN)
		return
	end

	state.saved_diffopt = vim.opt.diffopt:get()
	local diffopt = vim.tbl_filter(function(o)
		return not vim.startswith(o, "linematch:")
	end, vim.deepcopy(state.saved_diffopt))
	vim.list_extend(diffopt, { "linematch:60", "vertical" })
	vim.opt.diffopt = diffopt

	vim.cmd("tabnew")
	state.tab = vim.api.nvim_get_current_tabpage()
	state.active = true
	state.idx = 1
	state.mode = "side"

	watch_tab()
	activate_maps()
	render()

	vim.notify(
		string.format(
			"Review mode: %d file(s) vs %s\nN next · n prev · <leader>gt toggle side/inline · <leader>gf files · <leader>gq quit",
			#state.files,
			label
		),
		vim.log.levels.INFO
	)
end

function M.setup()
	vim.api.nvim_create_user_command("Review", function(opts)
		M.start(opts.args)
	end, {
		nargs = "?",
		complete = function(lead)
			local out = vim.fn.systemlist({ "git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes" })
			if vim.v.shell_error ~= 0 then
				return {}
			end
			return vim.tbl_filter(function(ref)
				return ref:find(lead, 1, true) == 1
			end, out)
		end,
		desc = "Enter review mode against a branch (default origin/master)",
	})

	vim.api.nvim_create_user_command("ReviewChanges", function()
		M.start("HEAD")
	end, { desc = "Review uncommitted changes" })

	vim.api.nvim_create_user_command("ReviewQuit", function()
		M.quit()
	end, { desc = "Leave review mode" })

	vim.keymap.set("n", "<leader>gr", function()
		M.start()
	end, { desc = "Review vs default base branch" })

	vim.keymap.set("n", "<leader>gR", function()
		vim.ui.input({ prompt = "Review against: ", default = default_base() or "" }, function(input)
			if input and input ~= "" then
				M.start(input)
			end
		end)
	end, { desc = "Review vs branch (prompt)" })

	vim.keymap.set("n", "<leader>gc", function()
		M.start("HEAD")
	end, { desc = "Review uncommitted changes" })
end

return M
