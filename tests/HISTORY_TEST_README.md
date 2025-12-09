# History Tab Test Documentation

## Overview

`tests/test_history.lua` contains comprehensive functional tests for the History Tab feature. These tests follow a strict **Test-Driven Development (TDD)** approach and are designed to be **un-gameable** - they validate real user workflows and cannot be satisfied with stubs or mocks.

**Current Status:** All 25 tests FAIL (expected - implementation not yet complete)

**Test Framework:** mini.test with child Neovim processes

## Test Categories

### 1. Query Capture (6 tests)
Tests that queries are automatically captured to persistent storage after successful API responses.

**Key Tests:**
- `successful query is automatically saved to history` - Validates end-to-end capture workflow
- `multiple queries create multiple history entries` - Tests accumulation and ordering
- `error responses are NOT saved to history` - Ensures only successful queries captured
- `history respects max_entries limit` - Tests automatic pruning of old entries
- `history disabled config prevents capture` - Validates config control

**Anti-Gaming Measures:**
- Verifies actual JSON file written to disk
- Validates file structure and content
- Checks file persists after UI closes
- Tests real file system operations (not mocks)

### 2. History Display (6 tests)
Tests that the History Tab UI correctly renders captured queries.

**Key Tests:**
- `History tab shows empty state when no queries` - Zero-state handling
- `History tab shows captured queries after submission` - Basic display
- `History tab displays multiple entries in reverse chronological order` - Ordering logic
- `History tab shows timestamps` - Timestamp rendering
- `History tab truncates long prompts` - Text truncation
- `History tab refreshes when switching to it` - Dynamic updates

**Anti-Gaming Measures:**
- Validates actual buffer content users see
- Verifies complete workflow (submit → capture → display)
- Tests real-time refresh behavior
- No hardcoded display data

### 3. Load History (3 tests)
Tests that users can load previous queries back into the Query tab.

**Key Tests:**
- `Enter key loads selected query into Query tab` - Basic load workflow
- `loading entry preserves full prompt text even if truncated in display` - Full text restoration
- `Enter key focuses prompt for editing after load` - UX completeness

**Anti-Gaming Measures:**
- Validates tab switching behavior
- Verifies prompt actually written to buffer
- Tests cursor position and mode
- Checks full text preservation

### 4. Delete History (3 tests)
Tests that users can delete individual history entries.

**Key Tests:**
- `d key deletes selected history item` - Delete workflow
- `deleting item refreshes buffer display` - UI update after delete
- `deleting last item shows empty state` - Transition to empty state

**Anti-Gaming Measures:**
- Verifies actual file modification
- Validates correct entry removed
- Tests UI refresh behavior
- Checks file state matches display

### 5. Clear History (2 tests)
Tests that users can clear all history with confirmation.

**Key Tests:**
- `c key with confirmation clears all history` - Clear workflow
- `c key with cancel does NOT clear history` - Confirmation validation

**Anti-Gaming Measures:**
- Tests confirmation prompt behavior
- Verifies file actually cleared
- Validates cancel prevents clearing
- Checks UI updates correctly

### 6. Persistence (2 tests)
Tests that history survives window close/reopen and plugin reload.

**Key Tests:**
- `history persists after closing and reopening window` - Window persistence
- `history survives plugin reload` - Module reload handling

**Anti-Gaming Measures:**
- Tests file-based persistence (not memory cache)
- Validates data survives plugin unload
- Verifies complete reload workflow

### 7. Error Handling (5 tests)
Tests edge cases and error recovery.

**Key Tests:**
- `corrupt history file recovers gracefully` - Corrupt JSON handling
- `missing history file starts with empty state` - Initialization
- `adding entry creates history file if missing` - File creation
- `special characters in prompt handled correctly` - Unicode/escaping

**Anti-Gaming Measures:**
- Tests real error conditions
- Validates graceful degradation
- Verifies JSON encoding/decoding
- Checks file creation logic

## Running Tests

### Run all history tests:
```bash
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_history.lua')"
```

### Run via Make:
```bash
make test  # Runs all tests including history tests
```

### Expected Output (Before Implementation):
```
Total number of cases: 25
Total number of groups: 1

tests/test_history.lua: xxxxxxxxxxxxxxxxxxxxxxxxx

FAIL in tests/test_history.lua | Query Capture | successful query is automatically saved to history
...
(All tests should fail with "attempt to call field 'X' (a nil value)")
```

## Test Design Philosophy

### 1. Useful Tests
Every test validates **real user value**:
- "Can I see my query history?" → Display tests
- "Can I reload a previous query?" → Load tests
- "Can I delete unwanted history?" → Delete tests

**No tautological tests** - Each test proves functionality works, not just that code exists.

### 2. Complete Coverage
Tests cover:
- ✅ Happy path (normal usage)
- ✅ Error cases (corrupt files, missing data)
- ✅ Edge cases (special chars, max limits)
- ✅ UX completeness (focus, mode, cursor position)

### 3. Flexible Tests
Tests validate **behavior**, not **implementation**:
- ✅ "Query appears in history" - NOT "add_entry() was called"
- ✅ "File contains entry" - NOT "specific JSON structure used"
- ✅ "Buffer shows timestamp" - NOT "format_timestamp() exists"

**Allows refactoring** - Implementation can change as long as behavior stays correct.

### 4. Fully Automated
- No manual setup required
- Uses temp directories (isolated from real config)
- Mocks only HTTP (follows existing pattern)
- Clean state per test (child.restart)

## Anti-Gaming Architecture

### Why These Tests Cannot Be Faked

**1. Real File System Operations:**
```lua
-- Test reads ACTUAL file from disk
local history_data = read_history_file()
eq(#history_data.entries, 1)
```
Cannot be satisfied with:
- ❌ Mock file system
- ❌ Fake return values
- ❌ Stub implementations

**2. Observable Outcomes:**
```lua
-- Test verifies what USER sees in buffer
local lines = get_history_buffer_lines()
expect.match(content, "How do I save a file")
```
Cannot be satisfied with:
- ❌ Internal state changes only
- ❌ Function call tracking
- ❌ Hidden side effects

**3. Complete Workflows:**
```lua
-- Submit → Capture → Display → Load
ui.submit_query()  -- Real submission
-- (file written)
ui.switch_tab("history")  -- Real tab switch
ui.load_history_item_at_cursor()  -- Real load
```
Cannot be satisfied with:
- ❌ Testing each function in isolation
- ❌ Mocking intermediate steps
- ❌ Skipping file operations

**4. State Verification:**
```lua
-- Verify file matches display
local file_data = read_history_file()
local buffer_content = get_history_buffer_lines()
-- Both must show same entry count
```
Cannot be satisfied with:
- ❌ Display without storage
- ❌ Storage without display
- ❌ Inconsistent state

## Traceability Matrix

### STATUS Gaps → Tests

| STATUS Gap | Test Coverage |
|------------|---------------|
| History storage NOT IMPLEMENTED | Query Capture tests (6) validate JSON persistence |
| History display STUB ONLY | History Display tests (6) validate dynamic rendering |
| History load NOT IMPLEMENTED | Load History tests (3) validate query restoration |
| History delete NOT IMPLEMENTED | Delete History tests (3) validate removal |
| History clear NOT IMPLEMENTED | Clear History tests (2) validate clearing |
| No persistence | Persistence tests (2) validate file-based storage |
| No error handling | Error Handling tests (5) validate graceful recovery |

### PLAN Items → Tests

| PLAN Phase | Test Coverage |
|------------|---------------|
| Phase 1: Storage & Persistence | Query Capture (6 tests) + Persistence (2 tests) |
| Phase 2: Query Capture Hook | Query Capture (6 tests) - automatic capture |
| Phase 3: UI Display | History Display (6 tests) - rendering |
| Phase 4: User Interactions | Load (3) + Delete (3) + Clear (2) = 8 tests |
| Phase 5: Testing (this phase!) | All 25 tests |
| Edge Cases | Error Handling (5 tests) |

## Test Execution Flow

### Typical Test Anatomy

```lua
T["Test Category"]["specific test case"] = function()
    -- 1. SETUP: Prepare test environment
    setup_mock_success("Test response")
    child.lua([[require("n00bkeys.ui").open()]])

    -- 2. EXECUTE: Perform user action
    child.lua([[
        local ui = require("n00bkeys.ui")
        vim.api.nvim_buf_set_lines(ui.state.tabs.query.buf_id, 0, 1, false, {"test"})
        ui.submit_query()
    ]])
    wait_for_completion()

    -- 3. VERIFY: Check observable outcomes
    local history_data = read_history_file()  -- Check file
    eq(#history_data.entries, 1)              -- Verify count

    local lines = get_history_buffer_lines()  // Check UI
    expect.match(content, "test")             // Verify display

    -- 4. CLEANUP: Automatic via pre_case hook
end
```

### Isolation Strategy

**Each test runs in isolated environment:**
- Fresh Neovim child process
- Temp XDG_DATA_HOME (isolated history.json)
- Clean module state (no shared cache)
- Independent file system (no cross-test pollution)

## Expected Failures (Before Implementation)

### Missing Functions (Will Cause Failures):

**In `lua/n00bkeys/history.lua` (module doesn't exist yet):**
- `history.add_entry(prompt, response)`
- `history.get_entries()`
- `history.remove_entry(index)`
- `history.clear_all()`

**In `lua/n00bkeys/ui.lua` (functions don't exist yet):**
- `ui.load_history_item_at_cursor()`
- `ui.delete_history_item_at_cursor()`
- `ui.clear_all_history()`
- `ui.render_history_buffer()` (currently stub)

**In `lua/n00bkeys/config.lua` (options don't exist yet):**
- `history_enabled`
- `history_max_items`

### Error Messages You'll See:

```
attempt to call field 'load_history_item_at_cursor' (a nil value)
attempt to call field 'delete_history_item_at_cursor' (a nil value)
attempt to call field 'clear_all_history' (a nil value)
```

**This is EXPECTED and CORRECT** - tests fail until implementation complete.

## Success Criteria

### Tests Pass When:

1. **All functions exist** - No "nil value" errors
2. **File operations work** - JSON files created/read/written
3. **UI displays correctly** - Buffer shows history entries
4. **Interactions functional** - Load/delete/clear work
5. **Edge cases handled** - Corrupt files, missing data, etc.

### What "Passing" Means:

```
Total number of cases: 25
Total number of groups: 1

tests/test_history.lua: .........................

All 25 tests passed!
```

### Integration Success:

```bash
make test
# All 260+ tests pass (235 existing + 25 new)
```

## Maintenance Guide

### Adding New Tests

**When to add tests:**
- New history features (search, filter, export)
- New edge cases discovered
- Bug fixes (add regression test)
- UX improvements (test new behavior)

**Where to add:**
- Create new test group: `T["New Feature"] = MiniTest.new_set()`
- Or add to existing group if related

**Pattern to follow:**
```lua
T["Category"]["descriptive test name"] = function()
    -- ANTI-GAMING: Why this test can't be faked
    -- 1. Uses real X
    -- 2. Verifies actual Y
    -- 3. Checks observable Z

    -- Test implementation
end
```

### Modifying Existing Tests

**When to modify:**
- Implementation changes behavior (update expectations)
- Better anti-gaming measures discovered
- Test becomes flaky (fix isolation)

**When NOT to modify:**
- Test fails due to incomplete implementation (implement first!)
- Test is "too strict" (tests should be strict!)
- Don't want to deal with failure (fix the code!)

## Common Issues

### Test Fails: "unexpected symbol near 'return'"
**Cause:** History module doesn't exist yet
**Fix:** Implement `lua/n00bkeys/history.lua`

### Test Fails: "attempt to call field 'X' (a nil value)"
**Cause:** Function not implemented in ui.lua
**Fix:** Implement the missing function

### Test Passes but History Doesn't Work in Real Use
**Cause:** Test is gameable (BAD!)
**Fix:** Add more anti-gaming measures:
- Verify file on disk
- Check actual buffer content
- Test complete workflow

### All Tests Pass but One Feature Broken
**Cause:** Test coverage gap
**Fix:** Add test for that feature (regression test)

## Future Enhancements

### Potential New Test Areas:

1. **Search/Filter:**
   - Search by text
   - Filter by date range
   - Filter by context

2. **Performance:**
   - Large history files (1000+ entries)
   - Rendering speed
   - File I/O performance

3. **Privacy:**
   - Sensitive data detection
   - History encryption
   - Secure deletion

4. **Integration:**
   - History → Preprompt integration
   - History → Settings integration
   - History export/import

## References

- **Test Pattern:** Based on `tests/test_settings_panel.lua`
- **Workflow Pattern:** Based on `tests/test_user_workflows.lua`
- **STATUS Source:** `.agent_planning/STATUS-2025-11-30-235159.md`
- **PLAN Source:** `.agent_planning/PLAN-2025-11-30-235532.md`

## Summary

**Purpose:** Prove History Tab works before writing implementation

**Approach:** TDD - tests written first, implementation follows

**Philosophy:** Un-gameable tests that validate real user value

**Coverage:** 25 tests × 7 workflows = comprehensive validation

**Next Step:** → Run tests (they fail) → Implement features → Tests pass
