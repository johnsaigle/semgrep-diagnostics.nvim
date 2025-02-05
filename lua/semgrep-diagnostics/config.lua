local M = {}

-- Default configuration
local defaults = {
	-- Enable the plugin by default
	enabled = true,
	-- Default semgrep configuration(s)
	-- Can be a string for single config or table for multiple configs
	semgrep_config = "auto",
	-- Severity mapping
	severity_map = {
		ERROR = vim.diagnostic.severity.ERROR,
		WARNING = vim.diagnostic.severity.WARN,
		INFO = vim.diagnostic.severity.INFO,
		HINT = vim.diagnostic.severity.HINT,
	},
	-- Default severity if not specified
	default_severity = vim.diagnostic.severity.WARN,
	-- Additional semgrep CLI arguments
	extra_args = {},
	-- Filetypes to run semgrep on, empty means all filetypes
	filetypes = {},
	keymaps = {
		-- Set to empty string or false to disable
		set_severity = "<leader>ss",
	},
}


function M.print_config()
	local config_lines = { "Current Semgrep Configuration:" }
	for k, v in pairs(M.config) do
		if type(v) == "table" then
			table.insert(config_lines, string.format("%s: %s", k, vim.inspect(v)))
		else
			table.insert(config_lines, string.format("%s: %s", k, tostring(v)))
		end
	end
	vim.notify(table.concat(config_lines, "\n"), vim.log.levels.INFO)
end

-- Function to toggle the plugin. Clears current diagnostics.
function M.toggle()
	if not namespace then
		namespace = vim.api.nvim_create_namespace("semgrep-nvim")
	end

	-- Toggle the enabled state
	M.config.enabled = not M.config.enabled
	if not M.config.enabled then
		-- Clear all diagnostics when disabling
		-- Get all buffers
		local bufs = vim.api.nvim_list_bufs()
		for _, buf in ipairs(bufs) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.diagnostic.reset(namespace, buf)
			end
		end
		vim.notify("Semgrep diagnostics disabled", vim.log.levels.INFO)
	else
		vim.notify("Semgrep diagnostics enabled", vim.log.levels.INFO)
		M.semgrep()
	end
end

-- Helper function to convert semgrep_config to a table if it's a string
function M.normalize_config(config)
	if type(config) == "string" then
		return { config }
	end
	return config
end

function M.setup_keymaps()
	if M.config.keymaps.set_severity then
		vim.keymap.set('n', M.config.keymaps.set_severity, function()
			vim.ui.select(
				{ "ERROR", "WARN", "INFO", "HINT" },
				{
					prompt = "Select minimum severity level:",
					format_item = function(item)
						return string.format("%s (%d)", item, vim.diagnostic.severity[item])
					end,
				},
				function(choice)
					if choice then
						local severity = vim.diagnostic.severity[choice]
						M.set_minimum_severity(severity)
					end
				end
			)
		end, { desc = "Set [s]emgrep minimum [s]everity" })
	end
end

function M.set_minimum_severity(level)
	if not vim.tbl_contains(vim.tbl_values(vim.diagnostic.severity), level) then
		vim.notify("Invalid severity level", vim.log.levels.ERROR)
		return
	end
	M.config.default_severity = level
	vim.notify(string.format("Minimum severity set to: %s", level), vim.log.levels.INFO)
end


-- Function to update configuration
function M.setup(opts)
    M.current = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

M.config = vim.deepcopy(defaults)
return M
