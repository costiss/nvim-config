--- Markdown preview through `leaf`, a terminal previewer.
---
--- Opening a markdown file swaps the window over to the rendered document, so
--- that is what you land on. The render is plain buffer text with no process
--- behind it: leaf's own keybindings never apply and every neovim mapping
--- works as usual. <leader>mp (or q) hands the window back to the source
--- buffer, which then stays editable until you ask for the preview again.
---
---   :Leaf [file]      preview <file> in place (default: the current buffer)
---   :LeafSplit [f]    preview side by side, without taking focus
---   :LeafFloat [f]    preview in a floating window
---   :LeafEdit         go back to the source buffer
---   :LeafPicker       browse files in leaf's own picker (interactive TUI)
---   :LeafFuzzy [kw]   fuzzy-find a file in leaf's own picker
---   :LeafAuto         toggle the open-markdown-in-leaf behaviour
---
--- In markdown buffers:
---   <leader>mp   toggle the preview in place
---   <leader>mv   preview side by side
---
--- In a preview: q or <leader>mp returns to the source. Everything else is
--- ordinary neovim -- j/k, /, gg, G, <C-e>, marks, folds, your own maps.

local M = {}

local BIN = "leaf"
local MIN_WIDTH = 20

M.config = {
	theme = "ocean",
	auto = true,
	position = "right",
	width = 0.5,
}

--- Live previews, keyed by the window showing them.
local previews = {}

local augroup = vim.api.nvim_create_augroup("costis_leaf", { clear = true })

local function available()
	if vim.fn.executable(BIN) == 1 then
		return true
	end
	vim.notify(
		BIN .. " not found on $PATH — install it with:\n  curl -fsSL https://leaf.rivolink.mg/install.sh | sh",
		vim.log.levels.ERROR
	)
	return false
end

--- Resolve a buffer to a path leaf can read.
--- Scratch and unnamed buffers are dumped to a tempfile.
local function buffer_file(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	if name ~= "" and vim.bo[buf].buftype == "" then
		if vim.bo[buf].modified and vim.bo[buf].modifiable then
			vim.api.nvim_buf_call(buf, function()
				vim.cmd("silent write")
			end)
		end
		return name
	end

	local tmp = vim.fn.tempname() .. ".md"
	vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmp)
	return tmp
end

local function target(file)
	if file == nil or file == "" then
		local buf = vim.api.nvim_get_current_buf()
		return buffer_file(buf), buf
	end

	local path = vim.fn.fnamemodify(file, ":p")
	if vim.fn.filereadable(path) == 0 then
		vim.notify("leaf: no such file: " .. path, vim.log.levels.ERROR)
		return nil
	end
	return path, nil
end

------------------------------------------------------------------- rendering

--- Render to ANSI and hand the bytes back. `--inline` writes to stdout and
--- exits, so nothing is left running to swallow keystrokes.
local function render(path, width, cb)
	vim.system({
		BIN,
		"--theme",
		M.config.theme,
		"--inline=ansi:" .. math.max(MIN_WIDTH, width),
		path,
	}, { text = false }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				vim.notify("leaf: " .. vim.trim(res.stderr or "render failed"), vim.log.levels.ERROR)
				return
			end
			cb(res.stdout or "")
		end)
	end)
end

local PREVIEW_WO = { number = false, relativenumber = false, signcolumn = "no", wrap = false, list = false }

local function save_wo(win)
	local saved = {}
	for opt, _ in pairs(PREVIEW_WO) do
		saved[opt] = vim.wo[win][opt]
	end
	return saved
end

local function apply_wo(win, opts)
	for opt, value in pairs(opts) do
		pcall(function()
			vim.wo[win][opt] = value
		end)
	end
end

local function wipe(buf)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

--- Paint `path` into `win`, replacing whatever preview is already there.
local function show(win, src, path, keep_cursor)
	render(path, vim.api.nvim_win_get_width(win), function(data)
		if not vim.api.nvim_win_is_valid(win) then
			return
		end

		local entry = previews[win]
		local old = entry and entry.buf
		local line = keep_cursor and entry and vim.api.nvim_win_get_cursor(win)[1] or 1

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(win, buf)

		local chan = vim.api.nvim_open_term(buf, {})
		vim.api.nvim_chan_send(chan, (data:gsub("\r?\n", "\r\n")))

		previews[win] = {
			buf = buf,
			src = src,
			path = path,
			saved_wo = (entry and entry.saved_wo) or save_wo(win),
		}
		wipe(old)

		apply_wo(win, PREVIEW_WO)
		vim.bo[buf].filetype = "leaf"

		vim.keymap.set("n", "q", function()
			M.edit(win)
		end, { buffer = buf, desc = "Leaf: back to the source buffer" })

		vim.keymap.set("n", "<leader>mp", function()
			M.edit(win)
		end, { buffer = buf, desc = "Leaf: back to the source buffer" })

		vim.schedule(function()
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
				local last = vim.api.nvim_buf_line_count(buf)
				pcall(vim.api.nvim_win_set_cursor, win, { math.min(math.max(line, 1), last), 0 })
			end
		end)
	end)
end

--- Give `win` back to the buffer it was previewing.
function M.edit(win)
	win = win or vim.api.nvim_get_current_win()
	local entry = previews[win]
	if not entry then
		vim.notify("leaf: no preview in this window", vim.log.levels.WARN)
		return
	end

	previews[win] = nil

	if vim.api.nvim_win_is_valid(win) then
		apply_wo(win, entry.saved_wo)
		if entry.src and vim.api.nvim_buf_is_valid(entry.src) then
			vim.b[entry.src].leaf_edit = true
			vim.api.nvim_win_set_buf(win, entry.src)
			vim.api.nvim_set_current_win(win)
		end
	end

	wipe(entry.buf)
end

--------------------------------------------------------------------- entries

function M.preview(file)
	if not available() then
		return
	end

	local win = vim.api.nvim_get_current_win()
	if previews[win] then
		return M.edit(win)
	end

	local path, src = target(file)
	if path then
		show(win, src or vim.api.nvim_get_current_buf(), path)
	end
end

function M.split(file)
	if not available() then
		return
	end

	local path, src = target(file)
	if not path then
		return
	end

	local source = vim.api.nvim_get_current_win()
	local width = math.floor(vim.o.columns * M.config.width)
	vim.cmd(("silent noswapfile vertical %s new"):format(M.config.position == "left" and "topleft" or "botright"))
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_width(win, width)

	show(win, src or vim.api.nvim_win_get_buf(source), path)
	vim.api.nvim_set_current_win(source)
end

function M.float(file)
	if not available() then
		return
	end

	local path, src = target(file)
	if not path then
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * 0.9)
	local height = math.floor(vim.o.lines * 0.9)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		border = "rounded",
		title = " leaf ",
		title_pos = "center",
	})

	show(win, src, path)
end

------------------------------------------------------------------- leaf's TUI

--- The pickers are interactive by nature, so they do run leaf itself.
local function tui(args, float)
	if not available() then
		return
	end

	local cmd = { BIN, "--theme", M.config.theme }
	vim.list_extend(cmd, args)

	require("snacks").terminal.open(cmd, {
		cwd = vim.fn.getcwd(),
		win = float and {
			position = "float",
			border = "rounded",
			width = 0.92,
			height = 0.92,
			title = " leaf ",
			title_pos = "center",
		} or {
			position = M.config.position,
			width = M.config.width,
			height = 0,
			stack = false,
			wo = { winbar = "" },
		},
	})
end

function M.picker(float)
	tui({ "--picker" }, float)
end

function M.fuzzy(keyword, float)
	local args = { "--fuzzy" }
	if keyword and keyword ~= "" then
		table.insert(args, keyword)
	end
	tui(args, float)
end

------------------------------------------------------------------------- auto

--- Every reason not to hijack a window. Reviews, diffs, floats, special
--- windows and buffers the user chose to edit are all left alone.
local function should_open(buf, win)
	if not M.config.auto or vim.g.leaf_auto == false then
		return false
	end
	if vim.b[buf].leaf_edit or vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype ~= "markdown" then
		return false
	end
	if vim.bo[buf].modified or not vim.bo[buf].modifiable then
		return false
	end
	if vim.fn.filereadable(vim.api.nvim_buf_get_name(buf)) == 0 then
		return false
	end
	if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
		return false
	end
	if vim.api.nvim_win_get_config(win).relative ~= "" or vim.fn.win_gettype(win) ~= "" then
		return false
	end
	if vim.wo[win].diff or previews[win] then
		return false
	end

	local ok, review = pcall(require, "costis.review")
	if ok and review.is_active and review.is_active() then
		return false
	end

	return vim.fn.executable(BIN) == 1
end

function M.toggle_auto()
	M.config.auto = not M.config.auto
	vim.notify("leaf: auto preview " .. (M.config.auto and "enabled" or "disabled"))
end

------------------------------------------------------------------------ setup

function M.setup()
	local function cmd(name, fn, opts)
		vim.api.nvim_create_user_command(name, fn, opts)
	end

	cmd("Leaf", function(o)
		M.preview(o.args)
	end, { nargs = "?", complete = "file", desc = "Preview markdown with leaf, in place" })

	cmd("LeafSplit", function(o)
		M.split(o.args)
	end, { nargs = "?", complete = "file", desc = "Preview markdown with leaf, side by side" })

	cmd("LeafFloat", function(o)
		M.float(o.args)
	end, { nargs = "?", complete = "file", desc = "Preview markdown with leaf, floating" })

	cmd("LeafEdit", function()
		M.edit()
	end, { desc = "Leave a leaf preview" })

	cmd("LeafPicker", function(o)
		M.picker(o.bang)
	end, { bang = true, desc = "Browse files in leaf" })

	cmd("LeafFuzzy", function(o)
		M.fuzzy(o.args, o.bang)
	end, { nargs = "?", bang = true, desc = "Fuzzy-find a file to preview in leaf" })

	cmd("LeafAuto", function()
		M.toggle_auto()
	end, { desc = "Toggle opening markdown files in leaf" })

	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = { "markdown", "codecompanion" },
		callback = function(args)
			vim.keymap.set("n", "<leader>mp", function()
				M.preview()
			end, { buffer = args.buf, desc = "Leaf: toggle preview in place" })

			vim.keymap.set("n", "<leader>mv", function()
				M.split()
			end, { buffer = args.buf, desc = "Leaf: preview side by side" })
		end,
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = augroup,
		pattern = { "*.md", "*.markdown" },
		callback = function(args)
			local win = vim.api.nvim_get_current_win()
			vim.schedule(function()
				if should_open(args.buf, win) then
					show(win, args.buf, vim.api.nvim_buf_get_name(args.buf))
				end
			end)
		end,
	})

	--- Keep visible previews in step with the file and the window size.
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		pattern = { "*.md", "*.markdown" },
		callback = function(args)
			local path = vim.api.nvim_buf_get_name(args.buf)
			for win, entry in pairs(previews) do
				if entry.path == path and vim.api.nvim_win_is_valid(win) then
					show(win, entry.src, path, true)
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = augroup,
		callback = function()
			for win, entry in pairs(previews) do
				if vim.api.nvim_win_is_valid(win) then
					show(win, entry.src, entry.path, true)
				else
					previews[win] = nil
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			local win = tonumber(args.match)
			local entry = win and previews[win]
			if entry then
				previews[win] = nil
				wipe(entry.buf)
			end
		end,
	})
end

return M
