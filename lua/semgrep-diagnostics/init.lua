local M = {}

local namespace = nil

-- Default configuration
local defaults = {
	-- Enable the plugin by default
	enabled = true,
	-- Default semgrep configuration
	-- semgrep_config = "~/coding/semgrep-rules-ar",
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
	print("Current Semgrep Configuration:")
	for k, v in pairs(M.config) do
		if type(v) == "table" then
			print(string.format("%s: %s", k, vim.inspect(v)))
		else
			print(string.format("%s: %s", k, tostring(v)))
		end
	end
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
					"--config=" .. M.config.semgrep_config,
					filepath
				}
				-- vim.notify("Running with config: " .. M.config.semgrep_config, vim.log.levels.ERROR)
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

								local diag = {
									lnum = result.start.line - 1,
									col = result.start.col,
									end_lnum = result["end"].line - 1,
									end_col = result["end"].col,
									source = "semgrep",
									message = result.extra.message,
									severity = severity
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

return M
