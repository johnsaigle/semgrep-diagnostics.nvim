local M = {}

local namespace = nil
local config = require('semgrep-diagnostics.config')

local function is_valid_diagnostic(result)
	return result.extra and
	    result.extra.severity and
	    result.extra.message
end

-- Run semgrep and populate diagnostics with the results.
function M.semgrep()
	local null_ls_ok, null_ls = pcall(require, "null-ls")
	if not null_ls_ok then
		vim.notify("none-ls is required for semgrep-nvim", vim.log.levels.ERROR)
		return
	end

	local semgrep_generator = {
		method = null_ls.methods.DIAGNOSTICS,
		filetypes = config.filetypes,
		generator = {
			-- Configure when to run the diagnostics
			runtime_condition = function()
				return config.enabled
			end,
			fn = function(params)
				-- Get semgrep or opengrep executable path
				local cmd = ""
				local semgrep_path = vim.fn.exepath("semgrep")
				if semgrep_path == "" then
					local opengrep_path = vim.fn.exepath("opengrep")
					if opengrep_path == "" then
						vim.notify("semgrep executable not found in PATH", vim.log.levels.ERROR)
						return {}
					else
						cmd = "opengrep"
					end
				else
					cmd = "semgrep"
				end

				local filepath = vim.api.nvim_buf_get_name(params.bufnr)

				-- Build command arguments.
				local args = {
					"--json",
					"--quiet",
				}

				-- Add all config paths.
				local configs = config.normalize_config(config.semgrep_config)
				for _, ruleset in ipairs(configs) do
					-- Include rulesets from the registry
					if vim.startswith(ruleset, "p/")
					    -- also allow the special "auto" option
					    or ruleset == "auto" then
						table.insert(args, "--config=" .. ruleset)
					else
						-- If using custom rulesets, first check if they exist.
						-- Allow for single files or directories.
						local path = vim.fn.expand(ruleset)
						if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
							table.insert(args, "--config=" .. ruleset)
						else
							vim.notify(
								string.format("Semgrep config not found, skipping: %s",
									config),
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

				-- Create async system command
				local full_cmd = vim.list_extend({ cmd }, args)

				-- TODO check nil when creating the file handle
				local f = io.open("/tmp/nvim_debug.log", "a")
				f:write(vim.inspect(vim.fn.join(full_cmd, " ")) .. "\n")
				f:close()

				vim.system(
					full_cmd,
					{
						text = true,
						cwd = vim.fn.getcwd(),
						env = vim.env,
					},
					-- TODO: Way too much indentation here. Should be refactored to use functions and/or continue statements.
					function(obj)
						local diags = {}
						-- Parse JSON output
						local ok, parsed = pcall(vim.json.decode, obj.stdout)
						if ok and parsed then
							local f = io.open("/tmp/nvim_debug.log", "a")
							f:write(vim.inspect(parsed) .. "\n")
							f:close()

							-- Convert results to diagnostics
							for _, result in ipairs(parsed.results) do
								if is_valid_diagnostic(result) then
									local severity = result.extra.severity and
									    config.severity_map[result.extra.severity] or
									    config.default_severity

									-- Ensure this result is relevant based on the user's settings.
									-- Range is: Critical=1 Hint=4.
									-- So if minimum severity is Warning (2), then
									-- skip results that are greater.
									if severity <= config.minimum_severity then
										-- Build the diagnostic message with rule information
										local message = result.extra.message
										if result.check_id then
											message = string.format(
												"%s [%s]",
												message,
												result.check_id
											)
										end

										local diag = {
											lnum = result.start.line - 1,
											col = result.start.col - 1,
											end_lnum = result["end"].line - 1,
											end_col = result["end"].col - 1,
											source = "semgrep",
											message = message,
											severity = severity,
											-- Store additional metadata in user_data
											user_data = {
												rule_id = result
												.check_id,
												-- this will show which config file contained the rule
												rule_source = result
												.path,
												rule_details = {
													category = result
													    .extra
													    .metadata and
													    result.extra
													    .metadata
													    .category,
													technology =
													    result.extra
													    .metadata and
													    result.extra
													    .metadata
													    .technology,
													confidence =
													    result.extra
													    .metadata and
													    result.extra
													    .metadata
													    .confidence,
													references =
													    result.extra
													    .metadata and
													    result.extra
													    .metadata
													    .references
												}
											}
										}
										table.insert(diags, diag)
									end
								end
							end

							-- Schedule the diagnostic updates
							vim.schedule(function()
								local namespace = vim.api.nvim_create_namespace(
									"semgrep-nvim")
								vim.diagnostic.set(namespace, params.bufnr, diags)
							end)
						end
					end
				)

				return {}
			end
		}
	}

	null_ls.register(semgrep_generator)
end

function M.show_rule_details()
	-- Get the diagnostics under the cursor
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local line = cursor_pos[1] - 1
	local col = cursor_pos[2]
	local diagnostics = vim.diagnostic.get(0, {
		namespace = vim.api.nvim_create_namespace("semgrep-nvim"),
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
			focus = true, -- Allow focusing the window
			width = 80,
			height = #details,
			close_events = { "BufHidden", "BufLeave" },
			focusable = true, -- Make the window focusable
			focus_id = "semgrep_details", -- Unique identifier for the window
		}
	)
end

return M
