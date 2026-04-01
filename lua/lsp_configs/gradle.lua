local lspconfig = require("lspconfig")
local mason_install = require("lsp_configs.helpers.mason_install")

return function()
	mason_install({
		"groovy-language-server",
		"gradle-language-server",
	})

	vim.lsp.config("groovyls", {})

	vim.lsp.config("gradle_ls", {
		cmd = { "gradle-language-server" },
		filetypes = { "groovy", "gradle", "kotlin.kts" },
		single_file_support = true,
		root_markers = {
			"settings.gradle.kts",
			"settings.gradle",
			"build.gradle.kts",
			"build.gradle",
			".git",
			"gradlew",
			"mvnw",
			"pom.xml",
		},
	})

	vim.lsp.enable("groovyls")
	vim.lsp.enable("gradle_ls")
end
