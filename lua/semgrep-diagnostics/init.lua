local M = {}

local semgrep = require('semgrep-diagnostics.semgrep')
local config = require('semgrep-diagnostics.config')

-- TODO
function M.setup(opts)
	config.setup(opts)

	-- Set up autocommands to attach to appropriate filetypes
	local group = vim.api.nvim_create_augroup("SemgrepDiagnostics", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = config.filetypes,
		callback = function(args)
			config.on_attach(args.buf)
		end,
	})

	config.print_config()
	if config.enabled then
		semgrep.semgrep()
	end
end

-- Re-export the config for other modules to use
M.config = config

return M
