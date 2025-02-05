local M = {}

local semgrep = require('semgrep-diagnostics.semgrep')
local config = require('semgrep-diagnostics.config')

-- Setup function to initialize the plugin
function M.setup(opts)
	if opts then
		for k, v in pairs(opts) do
			M.config[k] = v
		end
	end

	config.setup()
	config.setup_keymaps()
	-- config.print_config()

	if config.config.enabled then
		semgrep.semgrep()
	end
end

-- Re-export the config for other modules to use
-- TODO
M.config = config

return M
