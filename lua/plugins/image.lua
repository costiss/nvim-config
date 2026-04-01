return {
	{
		"3rd/image.nvim",
		ft = { "markdown", "vimwiki", "asciidoc", "norg", "typst", "rst" },
		event = {
			"BufReadPre *.png",
			"BufReadPre *.jpg",
			"BufReadPre *.jpeg",
		},
		build = false,
		opts = {
			backend = "kitty",
			processor = "magick_cli",
			integrations = {
				markdown = {
					enabled = true,
					clear_in_insert_mode = false,
					download_remote_images = true,
					only_render_image_at_cursor = true,
					only_render_image_at_cursor_mode = "popup",
				},
			},
			max_height_window_percentage = 50,
			window_overlap_clear_enabled = true,
			hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg" },
		},
	},
}
