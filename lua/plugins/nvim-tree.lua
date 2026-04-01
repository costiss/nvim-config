return {
	{
		"nvim-tree/nvim-tree.lua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local api = require("nvim-tree.api")

			vim.keymap.set("n", "<leader>t", function()
				api.tree.toggle()
			end)

			require("nvim-tree").setup({
				filters = {
					git_ignored = false,
					dotfiles = false,
					custom = { "^.git$" },
				},
				disable_netrw = true,
				hijack_netrw = true,
				hijack_cursor = true,
				hijack_unnamed_buffer_when_opening = false,
				sync_root_with_cwd = true,
				update_focused_file = {
					enable = true,
					update_root = false,
				},
				view = {
					adaptive_size = false,
					side = "left",
					width = 40,
					preserve_window_proportions = true,
				},
				git = {
					enable = true,
					ignore = true,
				},
				filesystem_watchers = {
					enable = true,
				},
				actions = {
					open_file = {
						resize_window = true,
					},
				},
				renderer = {
					group_empty = true,
					root_folder_label = false,
					highlight_git = true,
					highlight_opened_files = "none",

					indent_markers = {
						enable = true,
					},

					icons = {
						show = {
							file = true,
							folder = true,
							folder_arrow = true,
							git = true,
						},

						glyphs = {
							default = "󰈚",
							symlink = "",
							folder = {
								default = "",
								empty = "",
								empty_open = "",
								open = "",
								symlink = "",
								symlink_open = "",
								arrow_open = "",
								arrow_closed = "",
							},
							git = {
								unstaged = "✗",
								staged = "✓",
								unmerged = "",
								renamed = "➜",
								untracked = "★",
								deleted = "",
								ignored = "◌",
							},
						},
					},
				},
			})
		end,
	},
	{
		"antosha417/nvim-lsp-file-operations",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-tree.lua",
		},
		config = function()
			require("lsp-file-operations").setup()
		end,
	},
}
