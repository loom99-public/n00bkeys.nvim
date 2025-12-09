# Settings Panel Test Fixes - TDD Ready

**Date:** 2025-11-26
**Status:** Tests Updated, Ready for Implementation
**Test Status:** Expected to FAIL (intentionally - this is TDD!)

---

## Summary

Fixed 3 test files to be **un-gameable** and ready for Test-Driven Development of the Settings Panel feature. Tests now call functions that **don't exist yet** - this is correct TDD practice. The implementer will make them pass by creating the required functionality.

---

## Files Modified

### 1. `tests/test_api_key_precedence.lua` (+80 lines)

**Previous Issue:** Gaming-vulnerable - directly called `save_current_api_key()` to set state

**Fixed:** All API key setting now goes through UI actions

**New Helper Function:**
```lua
local function set_api_key_via_ui(api_key)
    -- This test cannot be gamed because:
    -- 1. Opens real Settings tab
    -- 2. Mocks ONLY vim.ui.input (user input simulation)
    -- 3. Calls real edit_api_key() function that must exist
    -- 4. Verifies file was actually written to disk
    -- 5. Verifies persistence after cache clear
```

**Anti-Gaming Measures:**
- ✅ Mocks user typing (vim.ui.input) - minimal, unavoidable mock
- ✅ Calls `edit_api_key()` function that DOESN'T EXIST YET
- ✅ Verifies actual file I/O (reads settings file from disk)
- ✅ Confirms persistence across cache clears
- ✅ Tests complete user workflow

**Tests:** 17 tests covering API key precedence

---

### 2. `tests/test_settings_panel.lua` (+392 lines)

**Previous Issues:**
- Gaming-vulnerable - directly set state via `save_current_api_key()` and `save_current_debug_mode()`
- Missing keymap tests
- Missing error handling tests

**Fixed:**

#### A. All State Changes Via UI Actions

**Before (gaming-vulnerable):**
```lua
child.lua([[require("n00bkeys.settings").save_current_api_key("test-key")]])
```

**After (un-gameable):**
```lua
child.lua([[
    vim.ui.input = function(opts, callback)
        callback("test-key")
    end
    require("n00bkeys.ui").open()
    require("n00bkeys.ui").switch_tab("settings")
    require("n00bkeys.ui").edit_api_key()  -- Function doesn't exist yet
]])
-- Then verify file was written to disk
```

#### B. New Test Categories Added

**API Key Editing Tests (3 tests):**
- `edit_api_key prompts for user input` - Verifies vim.ui.input called, file written, UI updated
- `edit_api_key handles special characters in key` - Tests JSON escaping
- `edit_api_key persists across close and reopen` - Confirms disk persistence

**Keymap Tests (3 tests):**
- `<C-g> keymap triggers edit_api_key` - Sends REAL keypress, verifies action called
- `<C-k> keymap triggers toggle_settings_scope` - Sends REAL keypress, verifies scope changed
- `<C-d> keymap triggers toggle_debug_mode` - Sends REAL keypress, verifies debug toggled

**Error Handling Tests (2 tests):**
- `corrupt JSON recovers gracefully` - Writes corrupt JSON, verifies defaults loaded
- `missing settings file creates new one on save` - Tests file creation workflow

**Anti-Gaming Measures:**
- ✅ Sends actual keypresses via `child.type_keys("<C-g>")`
- ✅ Calls functions that DON'T EXIST YET: `edit_api_key()`, `toggle_settings_scope()`
- ✅ Verifies file I/O at every step
- ✅ Confirms persistence by clearing cache and re-reading from disk
- ✅ Tests complete user workflows

**Tests:** 28 tests covering Settings Panel UI

---

### 3. `tests/test_settings_integration.lua` (+255 lines)

**Previous Issue:** Gaming-vulnerable - directly called `save_current_api_key()` instead of UI actions

**Fixed:**

#### A. All Settings Changes Via UI

**Before (gaming-vulnerable):**
```lua
child.lua([[require("n00bkeys.settings").save_current_api_key("settings-key")]])
-- Then test query
```

**After (un-gameable):**
```lua
child.lua([[
    vim.ui.input = function(opts, callback)
        callback("settings-key")
    end
    require("n00bkeys.ui").open()
    require("n00bkeys.ui").switch_tab("settings")
    require("n00bkeys.ui").edit_api_key()  -- Function doesn't exist yet
]])
-- Then test query AND verify HTTP request contains the key
```

#### B. New Keymap Integration Tests (3 tests)

- `user can edit API key with <C-g> keypress` - Complete workflow: keypress → input → save → query
- `user can toggle scope with <C-k> keypress and API keys are isolated` - Tests scope isolation via keypress
- `user can toggle debug mode with <C-d> keypress` - Tests debug toggle + persistence via keypress

**Anti-Gaming Measures:**
- ✅ Complete end-to-end workflows
- ✅ Sends actual keypresses
- ✅ Verifies HTTP requests contain correct API keys (can't be faked)
- ✅ Confirms file persistence
- ✅ Tests real OpenAI integration (mocked HTTP only)

**Tests:** 11 tests covering Settings Panel integration with plugin

---

## Why These Tests Will Fail (And That's Good!)

### Missing Functions (Will Cause Test Failures)

These functions are called by tests but **don't exist yet**:

1. **`require("n00bkeys.ui").edit_api_key()`**
   - Called by: 20+ tests
   - Should: Prompt user with vim.ui.input, save to settings, refresh UI
   - Implementation location: `lua/n00bKeys/ui.lua`

2. **`require("n00bkeys.ui").toggle_settings_scope()`**
   - Called by: 8+ tests
   - Should: Switch between global/project, refresh buffer
   - Implementation location: `lua/n00bKeys/ui.lua`

3. **`require("n00bkeys.ui").refresh_settings_buffer()`**
   - Called by: 10+ tests
   - Should: Re-render Settings tab with current values
   - Implementation location: `lua/n00bKeys/ui.lua`

4. **Keymaps for Settings Tab:**
   - `<C-g>` → `edit_api_key()`
   - `<C-k>` → `toggle_settings_scope()`
   - `<C-d>` → `toggle_debug_mode()` (already exists)
   - Implementation location: `lua/n00bKeys/keymaps.lua`

### Expected Test Output

```
tests/test_api_key_precedence.lua | env var has highest priority: x
  Error: attempt to call field 'edit_api_key' (a nil value)

tests/test_settings_panel.lua | <C-g> keymap triggers edit_api_key: x
  Error: attempt to call field 'edit_api_key' (a nil value)

tests/test_settings_integration.lua | user can edit API key with <C-g> keypress: x
  Error: attempt to call field 'edit_api_key' (a nil value)
```

**This is CORRECT! Tests define the contract for the implementation.**

---

## What Makes These Tests Un-Gameable?

### 1. Real User Actions

❌ **Before:**
```lua
require("n00bkeys.settings").save_current_api_key("key")
```
→ Can be gamed: Just make `save_current_api_key()` do nothing, tests still pass

✅ **After:**
```lua
vim.ui.input = function(opts, callback) callback("key") end
require("n00bkeys.ui").edit_api_key()
-- Then verify file written to disk
```
→ Cannot be gamed: Must implement real UI action that writes to disk

### 2. Actual Keypresses

❌ **Before:**
```lua
require("n00bkeys.ui").toggle_debug_mode()
```
→ Can be gamed: Call function directly, skip keymap registration

✅ **After:**
```lua
child.type_keys("<C-d>")
-- Then verify debug mode changed and persisted
```
→ Cannot be gamed: Keymap must be registered, action must execute

### 3. File System Verification

❌ **Before:**
```lua
-- Just check in-memory state
local key = require("n00bkeys.settings").get_current_api_key()
assert(key == "test")
```
→ Can be gamed: Just return hardcoded value

✅ **After:**
```lua
-- Verify file was written
local path = require("n00bkeys.settings").get_global_settings_path()
local file_content = io.open(path, "r"):read("*a")
assert(file_content:match("test"))
-- Then clear cache and re-read from disk
```
→ Cannot be gamed: File must actually exist on disk

### 4. HTTP Request Verification

❌ **Before:**
```lua
-- Just check that query was submitted
require("n00bkeys.ui").submit_query()
```
→ Can be gamed: Just set state without real HTTP call

✅ **After:**
```lua
-- Mock HTTP at transport layer
setup_mock_success(child)
require("n00bkeys.ui").submit_query()
-- Then verify HTTP request contains API key
local http_calls = child.lua_get([[_G.mock_http_calls]])
assert(http_calls[1].headers.Authorization == "Bearer test-key")
```
→ Cannot be gamed: Must build real HTTP request with correct headers

---

## Test Statistics

| File | Tests | New Tests | Lines Added | Gaming Vulnerabilities Fixed |
|------|-------|-----------|-------------|------------------------------|
| `test_api_key_precedence.lua` | 17 | 0 | +80 | 17 (all tests) |
| `test_settings_panel.lua` | 28 | 8 | +392 | 20 (most tests) |
| `test_settings_integration.lua` | 11 | 3 | +255 | 8 (most tests) |
| **TOTAL** | **56** | **11** | **+727** | **45** |

---

## Implementation Checklist

The implementer needs to create these functions to make tests pass:

### UI Functions (`lua/n00bKeys/ui.lua`)

- [ ] `edit_api_key()` - Prompt user, save API key, refresh buffer
- [ ] `toggle_settings_scope()` - Switch scope, refresh buffer
- [ ] `refresh_settings_buffer()` - Re-render Settings tab
- [ ] `render_settings_buffer()` - Initial render of Settings tab (may already exist)
- [ ] Settings tab buffer creation in `create_buffers()`
- [ ] Settings tab rendering in `switch_tab()`

### Keymap Registration (`lua/n00bKeys/keymaps.lua`)

- [ ] `<C-g>` → `edit_api_key()`
- [ ] `<C-k>` → `toggle_settings_scope()`
- [ ] `<C-d>` → `toggle_debug_mode()` (may already exist)
- [ ] Register keymaps only when Settings tab is active

### Settings Integration

- [ ] API key input dialog with vim.ui.input
- [ ] API key masking in UI (show `*****` instead of actual key)
- [ ] Scope radio buttons rendering
- [ ] Debug mode checkbox rendering
- [ ] Security warning text

---

## Running The Tests

```bash
# All tests (will show failures - expected!)
make test

# Specific test file
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_settings_panel.lua')"

# Watch for "attempt to call field 'edit_api_key' (a nil value)"
# This proves tests are ready for TDD implementation
```

---

## Success Criteria

Tests will pass when:

1. ✅ User can press `5` to open Settings tab
2. ✅ User can press `<C-g>` to edit API key
3. ✅ User can press `<C-k>` to toggle scope
4. ✅ User can press `<C-d>` to toggle debug mode
5. ✅ All settings persist to disk (verified by file I/O)
6. ✅ API keys work in real queries (verified by HTTP requests)
7. ✅ Scope isolation works (global vs project settings are separate)
8. ✅ Error handling works (corrupt JSON, missing files)

---

**END OF SUMMARY**
