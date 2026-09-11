return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "master", -- Locks to the stable legacy branch
		build = ":TSUpdate",
		event = { "BufReadPost", "BufNewFile", "BufWritePre" },
		main = "nvim-treesitter.configs", -- The "s" works perfectly here
		opts = {
			auto_install = true,
			ensure_installed = { "markdown", "markdown_inline" },
			highlight = {
				enable = true,
				additional_vim_regex_highlighting = false,
			},
		},
	},
	{
		"windwp/nvim-ts-autotag",
		event = "InsertEnter",
		opts = {
			enable_close = true,
			enable_rename = true,
			enable_close_on_slash = false,
		},
	},
}
