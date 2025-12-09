# Command Name Issue: E939 Error

**Date:** 2025-11-23
**Issue:** `:N00bkeys` command produces E939 error
**Root Cause:** Vim command-line parser interprets name as `:Next` with invalid count

---

## Problem

When users try to invoke `:N00bkeys`, Vim displays:
```
E939: Positive count required: N00bkeys
```

The plugin code NEVER RUNS because the error occurs during command-line parsing, before Neovim checks user-defined commands.

---

## Root Cause

Vim's command-line parser uses greedy matching for built-in commands:

1. User types: `:N00bkeys`
2. Parser sees: `:N` (matches built-in `:Next` command)
3. Parser sees: `00` (interprets as count = 0)
4. Parser sees: `bkeys` (remaining text, ignored)
5. Parser executes: `:Next` with count=0
6. `:Next` requires count ≥ 1, throws E939

**Our user-defined command is never consulted because the parser matches a built-in command first.**

---

## Why Tests Didn't Catch It

Our tests called the Lua API directly:
```lua
child.lua([[require("n00bkeys").enable()]])  -- Works fine
```

But users invoke via Ex command:
```vim
:N00bkeys  -- Triggers parser error
```

---

## Why Logging Didn't Catch It

Debug logging starts when Lua code runs:
```lua
function n00bkeys.setup(opts)
    log.debug("init.setup", "Registering command")  -- This runs
    vim.api.nvim_create_user_command("N00bkeys", handler, {})  -- Command registers fine
end
```

But the error occurs BEFORE the handler runs:
```lua
function()
    log.debug("command", "Handler invoked")  -- NEVER EXECUTES
    require("n00bkeys.ui").open()
end
```

**The command handler is never invoked, so nothing gets logged.**

---

## Verification

Built-in `:Next` behavior:
```vim
:help :Next
```
> Go to [count] previous file in argument list

Requires positive count for navigation.

Test the parsing issue:
```bash
nvim --headless --noplugin \
  -c "try | N00bkeys | catch | echo v:exception | endtry" \
  -c "qa"
# Output: Vim(Next):E939: Positive count required: N00bkeys
```

Even with command registered:
```bash
nvim --headless -u scripts/minimal_init.lua \
  -c "lua require('n00bkeys').setup()" \
  -c "try | N00bkeys | catch | echo v:exception | endtry" \
  -c "qa"
# Output: STILL E939!
```

---

## Solution Options

### Option 1: Rename to `Noobkeys` (Recommended)
Remove the zeros to avoid the `N00` parsing pattern:

```lua
vim.api.nvim_create_user_command("Noobkeys", handler, opts)
```

Pros:
- Clean, simple name
- No parsing conflicts
- Easy to type

Cons:
- Loses the "1337 speak" aesthetic
- Breaking change for existing users (if any)

### Option 2: Use Different Prefix
Change the starting pattern entirely:

```lua
vim.api.nvim_create_user_command("Keyshelp", handler, opts)
vim.api.nvim_create_user_command("AiKeys", handler, opts)
```

Pros:
- Completely avoids N-prefix conflicts
- More descriptive names possible

Cons:
- Loses brand identity (n00b theme)
- Less memorable

### Option 3: Use Keymap Instead of Command
Don't define an Ex command at all:

```lua
vim.keymap.set('n', '<leader>nk', function()
    require('n00bkeys.ui').open()
end, { desc = "Open n00bkeys" })
```

Pros:
- No command-line parsing issues
- More ergonomic (single keypress vs :Command<CR>)

Cons:
- Less discoverable
- Requires users to configure keymap
- Can't be called from command-line scripts

### Option 4: Accept the Limitation, Document Workaround
Keep `N00bkeys` but require full typing (no abbreviation):

```vim
:N00bkeys  " Doesn't work - E939
:call luaeval('require("n00bkeys").enable()')  " Works
```

Pros:
- Keeps original name
- API still works

Cons:
- Terrible user experience
- Defeats purpose of convenient command

---

## Recommended Solution

**Rename to `:Noobkeys`** and update all documentation.

Changes required:
1. `lua/n00bkeys/init.lua` - Command name
2. `README.md` - Usage examples
3. `doc/n00bkeys.txt` - Help documentation
4. `CLAUDE.md` - Development docs
5. `tests/test_API.lua` - Test assertions

---

## Test Coverage Fix

Add test that invokes Ex command (not just Lua API):

```lua
T["Ex command"]["command name doesn't conflict with built-ins"] = function()
    child.lua([[require('n00bkeys').setup()]])

    -- Clear error message
    child.lua([[vim.v.errmsg = ""]])

    -- Try to invoke via Ex command
    local success, err = pcall(function()
        child.cmd("Noobkeys")  -- or whatever we rename it to
    end)

    -- Check for Vim errors
    local errmsg = child.lua_get([[vim.v.errmsg]])

    -- Should not have E939 or any parsing errors
    if errmsg:match("E939") or errmsg:match("Positive count required") then
        error(string.format("Command name conflicts with built-in: %s", errmsg))
    end

    if not success then
        error(string.format("Command execution failed: %s", err))
    end
end
```

---

## Logging Enhancement

Add error capture in command handler:

```lua
vim.api.nvim_create_user_command("Noobkeys", function()
    log.debug("command", "Handler invoked")

    -- Capture any pre-existing errors
    local errmsg_before = vim.v.errmsg
    if errmsg_before ~= "" then
        log.error("command", "Pre-existing error: %s", errmsg_before)
        vim.v.errmsg = ""  -- Clear it
    end

    require("n00bkeys.ui").open()

    -- Check for new errors
    local errmsg_after = vim.v.errmsg
    if errmsg_after ~= "" then
        log.error("command", "Error after open: %s", errmsg_after)
    end
end, opts)
```

**NOTE:** This still won't catch the E939 because the handler never runs! But it will catch errors that occur DURING execution.

---

## Lessons Learned

1. **Test user-facing interfaces, not just APIs**
   - Users type `:Command`, not `lua require('module').function()`
   - Tests must exercise both paths

2. **Vim command parsing has precedence rules**
   - Built-in commands are checked before user commands
   - Short forms (`:N` for `:Next`) can shadow user commands
   - Numbers after command prefix are parsed as counts

3. **Command names must avoid built-in patterns**
   - Check `:help command-list` for conflicts
   - Test with actual `:Command` invocation
   - Don't assume user-defined commands "win"

4. **Logging can't capture parse-time errors**
   - Errors before Lua execution are invisible to plugin logging
   - Must test with actual Ex command invocation
   - Check `vim.v.errmsg` in tests

---

## References

- `:help :Next` - Built-in command for previous file in arglist
- `:help user-commands` - User-defined command documentation
- `:help command-line` - Command-line parsing rules
- `:help E939` - Positive count required error
