-- lua/semgrep/init.lua
local M = {}

-- Default configuration
M.default_config = {
	-- Enable the plugin by default
	enabled = true,
	-- Default semgrep configuration
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

-- Store user config
M.config = {}

-- Setup function to initialize the plugin
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})

	if not M.config.enabled then
		return
	end

	-- Load and setup null-ls integration
	local null_ls_ok, null_ls = pcall(require, "null-ls")
	if not null_ls_ok then
		vim.notify("null-ls is required for semgrep-nvim", vim.log.levels.ERROR)
		return
	end

	local semgrep_generator = {
		method = null_ls.methods.DIAGNOSTICS,
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
						-- if obj.code ~= 0 then
						-- 	vim.schedule(function()
						-- 		vim.notify(
						-- 		"semgrep error: " .. (obj.stderr or "unknown error"),
						-- 			vim.log.levels.WARN)
						-- 	end)
						-- 	return
						-- end

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

return M
