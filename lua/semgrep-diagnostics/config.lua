local M = {}
-- Create namespace once and export it for reuse
M.namespace = vim.api.nvim_create_namespace("semgrep-nvim")

M.enabled = true
-- Corresponds to the `--config` parameter when invoking semgrep. Represents a ruleset or yaml file.
M.semgrep_config = "auto"
M.severity_map = {
	CRITICAL = vim.diagnostic.severity.ERROR,
	ERROR = vim.diagnostic.severity.WARN,
	WARNING = vim.diagnostic.severity.INFO,
	INFO = vim.diagnostic.severity.HINT,
}
-- Used when the severity can't be parsed from the semgrep result.
---@type integer
M.default_severity = vim.diagnostic.severity.INFO
-- Show all results by default.
---@type integer
M.minimum_severity = vim.diagnostic.severity.HINT
M.extra_args = {}
M.filetypes = {}
-- Run mode: "save" = only on file save, "change" = debounced while typing
M.run_mode = "save"
-- Debounce delay in milliseconds (only used if run_mode = "change")
M.debounce_ms = 1000

function M.print_config()
	local config_lines = { "Current Semgrep Configuration:" }
	for k, v in pairs(M) do
		if type(v) == "table" and type(k) == "string" then
			table.insert(config_lines, string.format("%s: %s", k, vim.inspect(v)))
		elseif type(k) == "string" then
			table.insert(config_lines, string.format("%s: %s", k, tostring(v)))
		end
	end
	vim.notify(table.concat(config_lines, "\n"), vim.log.levels.INFO)
end

function M.toggle()
	-- Toggle the enabled state
	M.enabled = not M.enabled
	if not M.enabled then
		-- Clear all diagnostics when disabling
		local bufs = vim.api.nvim_list_bufs()
		for _, buf in ipairs(bufs) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.diagnostic.reset(M.namespace, buf)
			end
		end
		vim.notify("Semgrep diagnostics disabled", vim.log.levels.INFO)
	else
		vim.notify("Semgrep diagnostics enabled", vim.log.levels.INFO)
		require('semgrep-diagnostics.semgrep').semgrep()
	end
end

-- Helper function to convert semgrep_config to a table if it's a string
function M.normalize_config(config)
	if type(config) == "string" then
		return { config }
	end
	return config
end

function M.on_attach(bufnr)
	local opts = { buffer = bufnr }

	vim.keymap.set("n", "<leader>tt", function() M.toggle() end,
		vim.tbl_extend("force", opts, { desc = "[T]oggle Semgrep diagnostics" }))

	vim.keymap.set("n", "<leader>tc", function() M.print_config() end,
		vim.tbl_extend("force", opts, { desc = "Print Semgrep diagnostics [C]onfig" }))

	local semgrep = require('semgrep-diagnostics.semgrep')
	vim.keymap.set('n', '<leader>td', function() semgrep.show_rule_details() end,
		vim.tbl_extend("force", opts, { desc = 'Show Semgrep rule [D]etails' }))

	vim.keymap.set('n', '<leader>ts', function() semgrep.semgrep() end,
		vim.tbl_extend("force", opts, { desc = 'Run [S]emgrep' }))

	vim.keymap.set('n', '<leader>tv', function()
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
	end, vim.tbl_extend("force", opts, { desc = "Set [s]emgrep minimum se[v]erity" }))
end

function M.set_minimum_severity(level)
	if not vim.tbl_contains(vim.tbl_values(vim.diagnostic.severity), level) then
		vim.notify("Invalid severity level", vim.log.levels.ERROR)
		return
	end
	M.minimum_severity = level
	vim.notify(string.format("Minimum severity set to: %s", level), vim.log.levels.INFO)
end

function M.setup(opts)
    if opts then
        local updated = vim.tbl_deep_extend("force", M, opts)
        for k, v in pairs(updated) do
            M[k] = v
        end
    end
end

return M
