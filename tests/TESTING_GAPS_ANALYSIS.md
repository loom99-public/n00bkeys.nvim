# Testing & Logging Gaps Analysis

**Date:** 2025-11-23
**Issue:** E939 error from command abbreviation went undetected by both tests and logging
**Status:** Fixed by removing problematic abbreviation (commit TBD)

---

## Executive Summary

A Vim command abbreviation (`cnoreabbrev`) introduced in `lua/n00bkeys/init.lua` caused an E939 error ("Positive count required") when users invoked the plugin. Despite having:

- 75 passing tests with 100% workflow coverage
- Comprehensive debug logging
- Manual test plan

**Neither testing nor logging detected this production-breaking bug.**

This document analyzes why our safety nets failed and provides concrete recommendations to prevent similar issues.

---

## What Happened

### The Bug
```lua
-- Added in init.lua:setup()
vim.cmd([[cnoreabbrev <expr> n00bkeys (getcmdtype() == ':' && getcmdline() == 'n00bkeys') ? 'N00bkeys' : 'n00bkeys']])
```

This abbreviation was intended to allow users to type `:n00bkeys` (lowercase) and have it automatically expand to `:N00bkeys` (uppercase, required by Neovim).

### The Failure Mode
When users typed `:n00bkeys`, Neovim's command parser encountered an error **before any Lua code executed**:
```
Error 23:49:15 msg_show.emsg  N00bkeys E939: Positive count required
```

### What the Debug Log Showed
The `/tmp/n00bkeys.log` file showed the plugin code WAS running:
```
2025-11-23 23:45:48 [n00bkeys.nvim@ui.open] Opening n00bkeys window
2025-11-23 23:45:48 [n00bkeys.nvim@ui.open] Creating new buffer
...
```

**Key Insight:** The plugin executed successfully, but only *after* the E939 error occurred at the Vim command parsing level. The error was non-fatal but disrupted the user experience.

---

## Why Tests Didn't Catch It

### Gap 1: Tests Don't Exercise Command Invocation Paths

**Current approach:**
```lua
-- tests/test_user_workflows.lua
child.lua([[require("n00bkeys.ui").open()]])  -- Direct Lua call
```

**What we didn't test:**
```lua
child.cmd("N00bkeys")        -- Ex command invocation
child.cmd("n00bkeys")        -- Lowercase abbreviation
```

### Gap 2: Headless Mode Suppresses Vim Errors

Tests run with `nvim --headless`, which:
- Suppresses UI error messages
- Doesn't populate `vim.v.errmsg` reliably for non-fatal errors
- Doesn't test command-line parsing behavior

### Gap 3: No Testing of Vim Command Layer

Our test philosophy correctly focuses on "workflow-first, anti-gaming" testing. However, we tested the **Lua API** (`require("n00bkeys").enable()`) but not the **user-facing command** (`:N00bkeys`).

The abbreviation lives in the **Vim command layer**, outside the scope of our Lua-focused tests.

---

## Why Logging Didn't Catch It

### Gap 4: Logging Starts Too Late

**Current logging architecture:**
```lua
-- lua/n00bkeys/util/log.lua
log.debug("ui.open", "Opening n00bkeys window")
```

Logging begins when Lua code executes. By that point:
1. Vim has already parsed the command
2. The abbreviation has already been evaluated
3. The E939 error has already been displayed

**The error occurred in a layer we don't instrument.**

### Gap 5: No Capture of Vim Error Messages

We don't capture or log:
- `vim.v.errmsg` (last error message)
- `vim.v.warningmsg` (last warning message)
- Output from `:messages`

These Vim-level diagnostics contain errors that happen before/outside Lua execution.

### Gap 6: Debug Logging Doesn't Include Setup Phase

The abbreviation is registered during `setup()`, but we don't log:
```lua
log.debug("init.setup", "Registering command: N00bkeys")
log.debug("init.setup", "Registering abbreviation: n00bkeys -> N00bkeys")
```

Setup failures are silent unless they throw exceptions.

---

## Root Cause Analysis

### Why This Specific Issue Occurred

The E939 error suggests the `<expr>` abbreviation evaluation failed, likely due to:
1. **Quoting issues**: Mixing Lua string escaping with Vimscript evaluation
2. **Context mismatch**: `getcmdline()` returning unexpected values during expansion
3. **Expression evaluation order**: The conditional expression may have been parsed incorrectly

The `vim.cmd([[...]])` approach executes Vimscript directly, bypassing Lua's error handling. If the Vimscript expression is malformed, errors surface at the Vim layer, not Lua.

### Why This Class of Issue Is Hard to Catch

Command abbreviations are inherently fragile:
- They operate on string matching during command-line parsing
- They use Vimscript expressions in a Lua plugin
- They have subtle edge cases (counts, ranges, modifiers)
- They're hard to test in headless mode

**This was the wrong solution to the problem.**

---

## Recommendations

### 1. Expand Test Coverage: Command Invocation

**Add to `tests/test_API.lua`:**
```lua
T["command invocation"] = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })
    child.lua([[require("n00bkeys").setup({})]])

    -- Test uppercase command
    child.cmd("N00bkeys")
    eq(child.lua_get([[vim.v.errmsg]]), "")  -- No errors

    -- Verify window opened
    local winid = child.lua_get([[require("n00bkeys.ui").state.win_id]])
    expect.truthy(winid)

    child.cmd("close")
end

T["command registration"] = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })
    child.lua([[require("n00bkeys").setup({})]])

    -- Verify command exists
    local commands = child.api.nvim_get_commands({})
    expect.truthy(commands["N00bkeys"])

    -- Verify command has no args/range
    eq(commands["N00bkeys"].nargs, "0")
end
```

**Add to `tests/test_user_workflows.lua`:**
```lua
T["User Types Command"] = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })
    setup_plugin_with_mock()

    -- Simulate typing the command (not calling Lua directly)
    child.cmd("N00bkeys")

    -- Check for any error messages
    local errmsg = child.lua_get([[vim.v.errmsg]])
    eq(errmsg, "", "Command invocation should not produce errors")

    -- Verify window opened via command
    local lines = get_buffer_lines()
    expect.truthy(lines[1]:match("Ask about Neovim"))
end
```

### 2. Enhance Logging: Capture Vim Errors

**Add to `lua/n00bkeys/util/log.lua`:**
```lua
--- Log and clear vim.v.errmsg if present
---@param module string Module name
---@param context string Context description
function M.check_vim_errors(module, context)
    local errmsg = vim.v.errmsg
    if errmsg and errmsg ~= "" then
        M.error(module, "%s: vim.v.errmsg = %s", context, errmsg)
        vim.v.errmsg = ""  -- Clear so we don't double-report
    end
end
```

**Use in setup and critical paths:**
```lua
function n00bkeys.setup(opts)
    log.debug("init.setup", "Starting setup")
    _G.n00bkeys.config = config.setup(opts)

    log.debug("init.setup", "Registering command: N00bkeys")
    vim.api.nvim_create_user_command("N00bkeys", function()
        require("n00bkeys.ui").open()
    end, {})

    log.check_vim_errors("init.setup", "After command registration")
    log.debug("init.setup", "Setup complete")
end
```

### 3. Add Manual Test Checklist: Command Invocation

**Add to `MANUAL-TEST-PLAN.md`:**
```markdown
## Command Invocation Tests

These tests verify the user-facing Ex command works correctly.

### TC-CMD-01: Basic Command Invocation
1. Start Neovim: `nvim`
2. Type: `:N00bkeys<CR>`
3. **VERIFY:** No error messages appear in `:messages`
4. **VERIFY:** n00bkeys window opens

### TC-CMD-02: Command Completion
1. Start Neovim: `nvim`
2. Type: `:N00b<Tab>`
3. **VERIFY:** Completes to `:N00bkeys`
4. Press `<CR>`
5. **VERIFY:** Window opens without errors

### TC-CMD-03: Case Sensitivity
1. Start Neovim: `nvim`
2. Type: `:n00bkeys<CR>` (lowercase)
3. **VERIFY:** Shows "Not an editor command" (expected)
4. Type: `:N00bkeys<CR>` (uppercase)
5. **VERIFY:** Opens correctly
```

### 4. Architecture Change: Avoid Vim Command Layer Complexity

**Current approach (problematic):**
```lua
-- Trying to make lowercase work via abbreviation
vim.cmd([[cnoreabbrev <expr> n00bkeys ... ? 'N00bkeys' : 'n00bkeys']])
```

**Better approach:**
```lua
-- Just use the uppercase command
vim.api.nvim_create_user_command("N00bkeys", handler, {})
```

**If lowercase is required, document user-side solutions:**
```markdown
## Optional: Lowercase Command Alias

If you prefer typing `:n00bkeys`, add to your `init.lua`:

```lua
-- Simple abbreviation (only in command mode)
vim.cmd([[cabbrev n00bkeys N00bkeys]])

-- Or use a keymap instead
vim.keymap.set('n', '<leader>nk', ':N00bkeys<CR>', { desc = "Open n00bkeys" })
```
```

**Reasoning:**
- Puts abbreviation maintenance burden on users who want it
- Keeps plugin code simple and testable
- Avoids edge cases in command parsing
- Users can choose their preferred approach (abbrev vs keymap)

### 5. Add Pre-Commit Validation: Vim Command Syntax

**Add to `.git/hooks/pre-commit`:**
```bash
#!/bin/bash
# Test that plugin setup doesn't produce Vim errors

echo "Testing plugin setup..."
nvim --headless --noplugin -u scripts/minimal_init.lua \
  -c "lua require('n00bkeys').setup({})" \
  -c "if vim.v.errmsg != '' then print('ERROR: ' .. vim.v.errmsg); cquit; endif" \
  -c "quit"

if [ $? -ne 0 ]; then
  echo "Plugin setup produced Vim errors!"
  exit 1
fi
```

---

## Updated Development Workflow

### Before: What We Did
1. Write feature code
2. Write unit/integration tests (Lua API level)
3. Run `make test` (all pass ✓)
4. Commit
5. Users encounter Vim-level errors ✗

### After: What We Should Do
1. Write feature code
2. Write unit/integration tests (Lua API + Vim command level)
3. Add manual test checklist items if touching user-facing commands
4. Run `make test` (includes command invocation tests)
5. Run manual smoke test: `nvim` → `:N00bkeys` → verify no errors
6. Check `:messages` for any warnings
7. Commit with confidence

---

## Lessons Learned

### 1. Test the User-Facing Interface
We tested `require("n00bkeys").enable()` extensively but never tested `:N00bkeys`. The latter is what users actually interact with.

**Principle:** *Test the interface users touch, not just the Lua API.*

### 2. Integration Tests Need Multiple Invocation Paths
Good coverage means testing:
- Lua API calls: `require("n00bkeys").enable()`
- Ex commands: `:N00bkeys`
- Keymaps: `<leader>nk`
- Autocommands: `VimEnter` → `n00bkeys.setup()`

**Principle:** *If there are multiple ways to trigger functionality, test all of them.*

### 3. Logging Must Cover All Layers
Our logging was excellent for the **Lua layer** but missed the **Vim command layer**. Multi-layer architectures need multi-layer instrumentation.

**Principle:** *Log at every boundary crossing between systems.*

### 4. Vim Command Abstractions Are Fragile
Command abbreviations, especially with `<expr>` evaluation, introduce:
- Vimscript parsing complexity
- Cross-language boundary issues (Lua ↔ Vimscript)
- Hard-to-test edge cases

**Principle:** *Avoid complex Vim command layer abstractions when possible.*

### 5. "100% Test Coverage" Doesn't Mean "100% Confidence"
We had 100% workflow coverage at the Lua level, but 0% command invocation coverage.

**Principle:** *Coverage metrics lie when you're not measuring the right thing.*

---

## Prompt Guidance for AI Assistants

When working on Neovim plugins in the future, AI assistants (including Claude) should:

### ✅ DO

1. **Test Ex commands explicitly:**
   ```lua
   child.cmd("MyCommand")  -- Not just child.lua([[require('myplugin').func()]])
   ```

2. **Check vim.v.errmsg after operations:**
   ```lua
   child.cmd("N00bkeys")
   eq(child.lua_get([[vim.v.errmsg]]), "")
   ```

3. **Ask about lowercase command requirements:**
   - "Do you need users to type `:command` or is `:Command` acceptable?"
   - "Would a keymap be better than a command abbreviation?"

4. **Add logging at setup time:**
   ```lua
   log.debug("module.setup", "Registering command X")
   log.check_vim_errors("module.setup", "After registration")
   ```

5. **Update manual test plan when adding commands:**
   - Document the exact command to type
   - Include expected vs actual behavior
   - Note any error messages to check

6. **Consider implementation complexity:**
   - Is this feature worth the testing burden?
   - Is there a simpler approach?
   - Are we adding fragility for convenience?

### ❌ DON'T

1. **Don't use `vim.cmd([[...]])` for complex expressions without testing:**
   - Vimscript + Lua string escaping is error-prone
   - Test in actual Neovim before committing

2. **Don't assume "tests pass" means "it works":**
   - Tests only verify what they test
   - Manual verification is still necessary for user-facing features

3. **Don't add command abbreviations without discussing alternatives:**
   - They're fragile and hard to test
   - Consider keymaps or user-side config instead

4. **Don't trust headless mode to catch all errors:**
   - Some errors are only visible in interactive mode
   - Run at least one manual test

5. **Don't skip the "why" when removing features:**
   - If you remove an abbreviation, explain why in the commit message
   - Document the alternative solution for users

---

## Conclusion

This incident revealed gaps at the **boundary between Lua code and Vim command parsing**. Our testing and logging were excellent *within their scope*, but that scope was too narrow.

### Immediate Fix
- Removed problematic command abbreviation
- Documented uppercase command (`:N00bkeys`)
- All 75 tests still pass

### Long-Term Improvements
1. Add command invocation tests to test suite
2. Enhance logging to capture Vim-level errors
3. Update manual test plan with command-specific tests
4. Avoid complex Vim command layer abstractions

### Key Takeaway
**Production-breaking bugs hide at integration boundaries.** Testing must span every boundary users cross: Lua → Vim → command-line → user.

---

**Document Ownership:** @brandon-fryslie
**Review Cadence:** Revisit when adding new user-facing commands or when tests fail to catch a production bug
**Related Files:**
- `tests/TESTING_STRATEGY.md` - Overall testing philosophy
- `MANUAL-TEST-PLAN.md` - Manual validation checklist
- `CLAUDE.md` - Guidance for AI assistants
