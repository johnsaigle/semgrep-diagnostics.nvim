local M = {}

local sast = require('sast-nvim')

-- Create the semgrep adapter using sast-nvim
local adapter = sast.create_adapter({
	name = "semgrep",
	executable = { "semgrep", "opengrep" },
	
	-- Build command arguments for semgrep
	build_args = function(config, filepath)
		local args = {
			"--json",
			"--quiet",
		}
		
		-- Add all config paths
		local configs = config.semgrep_config
		if type(configs) == "string" then
			configs = { configs }
		end
		
		for _, ruleset in ipairs(configs) do
			-- Include rulesets from the registry
			if vim.startswith(ruleset, "p/") or ruleset == "auto" then
				table.insert(args, "--config=" .. ruleset)
			else
				-- If using custom rulesets, first check if they exist
				local path = vim.fn.expand(ruleset)
				if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
					table.insert(args, "--config=" .. ruleset)
				else
					vim.notify(
						string.format("Semgrep config not found, skipping: %s", ruleset),
						vim.log.levels.WARN
					)
				end
			end
		end
		
		-- Add filepath
		table.insert(args, filepath)
		
		-- Add any extra arguments
		for _, arg in ipairs(config.extra_args) do
			table.insert(args, arg)
		end
		
		return args
	end,
	
	-- Validate a single result from semgrep JSON
	validate_result = function(result)
		return result.extra and
			result.extra.severity and
			result.extra.message
	end,
	
	-- Transform semgrep result to nvim diagnostic
	transform_result = function(result, config)
		local severity = result.extra.severity and
			config.severity_map[result.extra.severity] or
			config.default_severity
		
		-- Build the diagnostic message with rule information
		local message = result.extra.message
		if result.check_id then
			message = string.format("%s [%s]", message, result.check_id)
		end
		
		return {
			lnum = result.start.line - 1,
			col = result.start.col - 1,
			end_lnum = result["end"].line - 1,
			end_col = result["end"].col - 1,
			source = "semgrep",
			message = message,
			severity = severity,
			-- Store additional metadata in user_data
			user_data = {
				rule_id = result.check_id,
				rule_source = result.path,
				rule_details = {
					category = result.extra.metadata and result.extra.metadata.category,
					technology = result.extra.metadata and result.extra.metadata.technology,
					confidence = result.extra.metadata and result.extra.metadata.confidence,
					references = result.extra.metadata and result.extra.metadata.references
				}
			}
		}
	end,
})

-- Add custom semgrep-specific method for showing rule details
function adapter.show_rule_details()
	-- Get the diagnostics under the cursor
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local line = cursor_pos[1] - 1
	local col = cursor_pos[2]
	local diagnostics = vim.diagnostic.get(0, {
		namespace = adapter.namespace,
		lnum = line
	})
	
	-- Find the diagnostic at or closest to cursor position
	local current_diagnostic = nil
	for _, diagnostic in ipairs(diagnostics) do
		if diagnostic.col <= col and col <= diagnostic.end_col then
			current_diagnostic = diagnostic
			break
		end
	end
	
	if not current_diagnostic or not current_diagnostic.user_data then
		vim.notify("No semgrep diagnostic found under cursor", vim.log.levels.WARN)
		return
	end
	
	-- Build detailed message
	local details = {
		string.format("Rule ID: %s", current_diagnostic.user_data.rule_id or "N/A"),
		string.format("Source: %s", current_diagnostic.user_data.rule_source or "N/A"),
	}
	
	-- Add metadata if available
	local rule_details = current_diagnostic.user_data.rule_details
	if rule_details then
		if rule_details.category then
			table.insert(details, string.format("Category: %s", rule_details.category))
		end
		if rule_details.technology then
			table.insert(details, string.format("Technology: %s", rule_details.technology))
		end
		if rule_details.confidence then
			table.insert(details, string.format("Confidence: %s", rule_details.confidence))
		end
		if rule_details.references and #rule_details.references > 0 then
			table.insert(details, "References:")
			for _, ref in ipairs(rule_details.references) do
				table.insert(details, string.format("  - %s", ref))
			end
		end
	end
	
	-- Show in hover window
	vim.lsp.util.open_floating_preview(
		details,
		'markdown',
		{
			border = "rounded",
			focus = true,
			width = 80,
			height = #details,
			close_events = { "BufHidden", "BufLeave" },
			focusable = true,
			focus_id = "semgrep_details",
		}
	)
end

-- Setup function with semgrep-specific defaults
function M.setup(opts)
	-- Set semgrep-specific defaults
	local defaults = {
		-- Semgrep-specific configuration
		semgrep_config = "auto",
		severity_map = {
			CRITICAL = vim.diagnostic.severity.ERROR,
			ERROR = vim.diagnostic.severity.WARN,
			WARNING = vim.diagnostic.severity.INFO,
			INFO = vim.diagnostic.severity.HINT,
		},
		default_severity = vim.diagnostic.severity.INFO,
		
		-- Custom on_attach to set up keybindings
		on_attach = function(bufnr, adapter_instance)
			local opts_buf = { buffer = bufnr }
			
			vim.keymap.set("n", "<leader>tt", function() adapter_instance.toggle() end,
				vim.tbl_extend("force", opts_buf, { desc = "[T]oggle Semgrep diagnostics" }))
			
			vim.keymap.set("n", "<leader>tc", function() adapter_instance.print_config() end,
				vim.tbl_extend("force", opts_buf, { desc = "Print Semgrep diagnostics [C]onfig" }))
			
			vim.keymap.set('n', '<leader>td', function() adapter_instance.show_rule_details() end,
				vim.tbl_extend("force", opts_buf, { desc = 'Show Semgrep rule [D]etails' }))
			
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
							adapter_instance.set_minimum_severity(severity)
						end
					end
				)
			end, vim.tbl_extend("force", opts_buf, { desc = "Set [s]emgrep minimum se[v]erity" }))
		end,
	}
	
	-- Merge user options with defaults
	local config = vim.tbl_deep_extend("force", defaults, opts or {})
	
	-- Setup the adapter
	adapter.setup(config)
end

-- Re-export adapter methods for backwards compatibility
M.toggle = function() adapter.toggle() end
M.print_config = function() adapter.print_config() end
M.show_rule_details = function() adapter.show_rule_details() end
M.set_minimum_severity = function(level) adapter.set_minimum_severity(level) end

return M
