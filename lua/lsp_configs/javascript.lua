local mason_install = require("lsp_configs.helpers.mason_install")

return function()
	mason_install({
		"vtsls",
		"prisma-language-server",
		"eslint-lsp",
		"prettierd",
		"eslint_d",
		"biome",
		"tailwindcss-language-server",
		"deno",
		--"vue-language-server",
	})

	vim.lsp.config("denols", {
		root_markers = { "deno.json", "deno.jsonc" },
	})

	vim.lsp.config("vtsls", {
		-- root_dir = require("lspconfig.util").root_pattern("package.json", "tsconfig.json", "jsconfig.json"),
		--single_file_support = false,
		--cmd = { "bun", "x", "--bun", "vtsls", "--stdio" },
		settings = {
			vtsls = {
				autoUseWorkspaceTsdk = true, -- Automatically use the workspace TypeScript version
				typescript = {
					preferences = {
						organizeImports = true,
					},
				},
			},
		},
	})

	vim.lsp.config("prismals", {})

	vim.lsp.config("eslint", {
		--cmd = { "bunx", "--bun", "vscode-eslint-language-server", "--stdio" },
		settings = {
			eslint = {
				enable = true,
				executable = vim.env.HOME .. "/.bun/bin/eslint_d",
				format = { enable = false },
				packageManager = "bun",
				autoFixOnSave = true,
				codeActionsOnSave = {
					enable = false,
					mode = "all",
					rules = { "!debugger", "!no-only-tests/*" },
				},
				lintTask = {
					enable = true,
				},
			},
		},
	})

	vim.lsp.config("biome", {
		-- root_dir = require("lspconfig.util").root_pattern("biome.json"),
		settings = {
			biome = {
				format = {
					enable = true,
				},
				lint = {
					enable = true,
				},
			},
		},
	})

	vim.lsp.config("tailwindcss", {})

	vim.lsp.config("astro", {})

	-- :MasonInstall vue-language-server@1.8.27

	vim.lsp.config("volar", {
		cmd = { "vue-language-server", "--stdio" },
		filetypes = { "vue" },
		init_options = {
			vue = {
				hybridMode = true, -- explicit hybrid mode
			},
		},
		root_markers = { "vue.config.js", "vite.config.ts", "package.json", ".git" },
	})

	vim.lsp.enable("denols")
	vim.lsp.enable("vtsls")
	vim.lsp.enable("prismals")
	vim.lsp.enable("eslint")
	vim.lsp.enable("biome")
	-- vim.lsp.enable("tailwindcss")
	vim.lsp.enable("astro")
	vim.lsp.enable("volar")
end
