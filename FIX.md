## Systemic Bugs in Neovim Plugins Using External Static Analysis Tools

### Problem #1: Running on Incomplete Code
**Symptom**: Tool executes on syntactically invalid code while typing, producing bogus errors that flood the editor.

**Root Cause**: 
- Plugin triggers on every buffer change via null-ls `DIAGNOSTICS` method
- External tool (semgrep/shellcheck/etc.) receives incomplete/invalid syntax
- No delay mechanism between keystrokes and execution

**Solution**: 
Use `DIAGNOSTICS_ON_SAVE` method instead of `DIAGNOSTICS` for null-ls generators:
```lua
-- BEFORE (bad)
method = null_ls.methods.DIAGNOSTICS

-- AFTER (good - default)
method = null_ls.methods.DIAGNOSTICS_ON_SAVE
```

**Alternative** (if user wants while-typing feedback):
Add debouncing with `vim.defer_fn()`:
```lua
if debounce_timers[params.bufnr] then
    debounce_timers[params.bufnr]:stop()
    debounce_timers[params.bufnr]:close()
end
debounce_timers[params.bufnr] = vim.defer_fn(function()
    -- run tool here
end, 1000) -- wait 1s after last keystroke
```

### Problem #2: Diagnostics Not Cleared Between Runs
**Symptom**: Errors accumulate on same lines; fixing issues doesn't remove old diagnostics.

**Root Cause**:
- `vim.diagnostic.set()` updates/adds diagnostics but doesn't guarantee removal of old ones
- No explicit cleanup before setting new results
- Namespace created repeatedly instead of reused

**Solution**:
Always call `vim.diagnostic.reset()` before `vim.diagnostic.set()`:
```lua
-- BEFORE (bad)
vim.schedule(function()
    local namespace = vim.api.nvim_create_namespace("tool-name")
    vim.diagnostic.set(namespace, bufnr, diags)
end)

-- AFTER (good)
vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    vim.diagnostic.reset(config.namespace, bufnr)  -- explicit clear
    vim.diagnostic.set(config.namespace, bufnr, diags)
end)
```

**Additional Fix**: Create namespace once at module load, not per-execution:
```lua
-- config.lua
M.namespace = vim.api.nvim_create_namespace("tool-name")  -- once, globally

-- use everywhere as config.namespace
```

### Configuration Pattern
Add runtime mode selection:
```lua
-- config.lua
M.run_mode = "save"  -- or "change" for debounced while-typing
M.debounce_ms = 1000

-- semgrep.lua (or tool-specific file)
method = config.run_mode == "save" 
    and null_ls.methods.DIAGNOSTICS_ON_SAVE 
    or null_ls.methods.DIAGNOSTICS
```

### Key Principle
**LSP servers** (rust-analyzer, gopls) can handle incomplete code because they're incremental parsers with state. **External CLI tools** (semgrep, shellcheck, eslint) cannot, so they should run on stable states (after save) or with significant debouncing (1000ms+).
