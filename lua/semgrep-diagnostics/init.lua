local M = {}

local namespace = nil

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
}

M.config = vim.deepcopy(defaults)

-- Debug function to print current config.
function M.print_config()
    local config_lines = {"Current Semgrep Configuration:"}
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
local function normalize_config(config)
	if type(config) == "string" then
		return { config }
	end
	return config
end

-- Run semgrep and populate diagnostics with the results.
function M.semgrep()
	-- Load and setup null-ls integration
	local null_ls_ok, null_ls = pcall(require, "null-ls")
	if not null_ls_ok then
		vim.notify("null-ls is required for semgrep-nvim", vim.log.levels.ERROR)
		return
	end

	local semgrep_generator = {
		method = null_ls.methods.DIAGNOSTICS,
		-- NOTE: unused
		filetypes = M.config.filetypes,
		generator = {
			-- Configure when to run the diagnostics
			runtime_condition = function()
				return M.config.enabled
			end,
			-- Run on file open and after saves
			on_attach = function(client, bufnr)
				vim.api.nvim_buf_attach(bufnr, false, {
					on_load = function()
						if M.config.enabled then
							null_ls.generator()(
								{ bufnr = bufnr }
							)
						end
					end
				})
			end,
			fn = function(params)
				-- Get semgrep executable path
				local semgrep_cmd = vim.fn.exepath("semgrep")
				if semgrep_cmd == "" then
					vim.notify("semgrep executable not found in PATH", vim.log.levels.ERROR)
					return {}
				end

				local filepath = vim.api.nvim_buf_get_name(params.bufnr)

				-- Build command arguments
				local args = {
					"--json",
					"--quiet",
				}

				-- Add all config paths
				local configs = normalize_config(M.config.semgrep_config)
				for _, config in ipairs(configs) do
					table.insert(args, "--config=" .. config)
				end

				-- Add filepath
				table.insert(args, filepath)

				-- Add any extra arguments
				for _, arg in ipairs(M.config.extra_args) do
					table.insert(args, arg)
				end

				-- Create async system command
				vim.system(
					vim.list_extend({ "semgrep" }, args),
					{
						text = true,
						cwd = vim.fn.getcwd(),
						env = vim.env,
					},
					function(obj)
						local diags = {}
						-- Parse JSON output
						local ok, parsed = pcall(vim.json.decode, obj.stdout)
						if ok and parsed and parsed.results then
							-- Convert results to diagnostics
							for _, result in ipairs(parsed.results) do
								local severity = M.config.default_severity
								if result.extra.severity then
									severity = M.config.severity_map
									    [result.extra.severity] or
									    M.config.default_severity
								end

								-- Build the diagnostic message with rule information
								local message = result.extra.message
								if result.check_id then
									message = string.format("%s [%s]",
										message,
										result.check_id
									)
								end

								local diag = {
									lnum = result.start.line - 1,
									col = result.start.col,
									end_lnum = result["end"].line - 1,
									end_col = result["end"].col,
									source = "semgrep",
									message = message,
									severity = severity,
									-- Store additional metadata in user_data
									user_data = {
										rule_id = result.check_id,
										rule_source = result.path, -- this will show which config file contained the rule
										rule_details = {
											category = result.extra.metadata and
											result.extra.metadata.category,
											technology = result.extra
											.metadata and
											result.extra.metadata.technology,
											confidence = result.extra
											.metadata and
											result.extra.metadata.confidence,
											references = result.extra
											.metadata and
											result.extra.metadata.references
										}
									}
								}
								table.insert(diags, diag)
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

-- Setup function to initialize the plugin
function M.setup(opts)
	if opts then
		for k, v in pairs(opts) do
			M.config[k] = v
		end
	end

	if M.config.enabled then
		M.semgrep()
	end
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
            focus = true,  -- Allow focusing the window
            width = 80,
            height = #details,
            close_events = {"BufHidden", "BufLeave"},
            focusable = true,  -- Make the window focusable
            focus_id = "semgrep_details",  -- Unique identifier for the window
        }
    )
end
return M

