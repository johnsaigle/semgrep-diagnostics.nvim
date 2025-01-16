# semgrep-diagnostics.nvim

A Neovim plugin that integrates [semgrep](https://semgrep.dev/) with the built-in diagnostic system using null-ls.

## Prerequisites

- Neovim 0.8 or higher
- [null-ls.nvim](https://github.com/jose-elias-alvarez/null-ls.nvim)
- [semgrep](https://semgrep.dev/docs/getting-started/) installed and available in PATH

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "yourusername/semgrep.nvim",
  dependencies = { "jose-elias-alvarez/null-ls.nvim" },
  opts = {
    -- your configuration
  }
}
```

## Configuration

Here's an example configuration with all available options and their defaults:

```lua
require('semgrep').setup({
  -- Enable/disable the plugin
  enabled = true,
  
  -- Semgrep configuration to use
  -- Can be:
  -- - "auto" (default, use .semgrep.yml in project root)
  -- - "p/ci" (use semgrep's CI rules)
  -- - "p/security-audit" (use security audit rules)
  -- - or any other valid semgrep rule set
  semgrep_config = "auto",
  
  -- Map semgrep severities to nvim diagnostic severities
  severity_map = {
    ERROR = vim.diagnostic.severity.ERROR,
    WARNING = vim.diagnostic.severity.WARN,
    INFO = vim.diagnostic.severity.INFO,
    HINT = vim.diagnostic.severity.HINT,
  },
  
  -- Default severity if not specified in the semgrep rule
  default_severity = vim.diagnostic.severity.WARN,
  
  -- Additional arguments to pass to semgrep
  extra_args = {},
  
  -- Filetypes to run semgrep on (empty means all filetypes)
  filetypes = {},
})
```

## Usage

Once configured, the plugin will automatically run semgrep on your files and display the results as diagnostics in Neovim. The diagnostics will update whenever you save a file.

You can use any of Neovim's built-in diagnostic features to navigate and view the semgrep results:

- `:lua vim.diagnostic.open_float()` - Show diagnostic in a floating window
- `:lua vim.diagnostic.goto_next()` - Go to next diagnostic
- `:lua vim.diagnostic.goto_prev()` - Go to previous diagnostic
- `:lua vim.diagnostic.setqflist()` - Put diagnostics in quickfix list

## Examples

### Using with specific rule sets

```lua
-- Use security audit rules
require('semgrep').setup({
  semgrep_config = "p/security-audit"
})

-- Use multiple rule sets
require('semgrep').setup({
  semgrep_config = "p/security-audit,p/ci",
  extra_args = {"--max-target-bytes", "1000000"}
})

-- Only run on specific filetypes
require('semgrep').setup({
  filetypes = {"python", "javascript", "typescript"}
})
```

## License

MIT
