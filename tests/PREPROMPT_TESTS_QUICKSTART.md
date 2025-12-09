# Pre-Prompt Tests Quick Start Guide

**Total Test Code:** 1,610 lines across 4 files
**Total Tests:** 72 functional tests
**Framework:** MiniTest (existing project framework)
**Status:** All tests EXPECTED TO FAIL until implementation complete

---

## Quick Test Execution

### Run Individual Test Files

```bash
# Settings module tests (28 tests)
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_settings.lua')"

# Pre-Prompt tab UI tests (23 tests)
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_preprompt_tab.lua')"

# Enhanced Context tab tests (13 tests)
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_context_tab.lua')"

# Integration tests (8 tests)
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_preprompt_integration.lua')"
```

### Run All Tests (After Implementation)

```bash
make test
```

---

## Test Files Overview

| File | Tests | Lines | Purpose |
|------|-------|-------|---------|
| `test_settings.lua` | 28 | 396 | Settings persistence (file I/O, paths, scope) |
| `test_preprompt_tab.lua` | 23 | 498 | Pre-Prompt tab UI and auto-save |
| `test_context_tab.lua` | 13 | 322 | Enhanced Context tab display |
| `test_preprompt_integration.lua` | 8 | 394 | End-to-end API integration |
| **Total** | **72** | **1,610** | **Complete v1.2.0 feature validation** |

---

## TDD Implementation Order

### Phase 1: Settings Module (4.5 hours)

**File to Create:** `lua/n00bKeys/settings.lua`

**Test to Run:**
```bash
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_settings.lua')"
```

**Expected Initial Output:**
```
Error: module 'n00bkeys.settings' not found
```

**Implementation Checklist:**
- [ ] Create module skeleton with constants
- [ ] Implement `get_global_settings_path()` → 1 test passes
- [ ] Implement `get_project_settings_path()` → 2 tests pass
- [ ] Implement `find_project_root()` → 5 tests pass
- [ ] Implement `load_global()` → 7 tests pass
- [ ] Implement `load_project()` → 8 tests pass
- [ ] Implement `save_global()` → 12 tests pass
- [ ] Implement `save_project()` → 13 tests pass
- [ ] Implement `ensure_directory()` → 14 tests pass
- [ ] Implement `get_selected_scope()` → 16 tests pass
- [ ] Implement `set_selected_scope()` → 18 tests pass
- [ ] Implement `get_current_preprompt()` → 21 tests pass
- [ ] Implement `save_current_preprompt()` → 23 tests pass
- [ ] Add error handling for corrupt JSON → 25 tests pass
- [ ] Add multi-line and special character support → 27 tests pass
- [ ] Implement `clear_cache()` → **ALL 28 TESTS PASS** ✓

---

### Phase 2: Pre-Prompt Tab (4.5 hours)

**Files to Modify:**
- `lua/n00bKeys/ui.lua` (add tab, buffer layout, auto-save)
- `lua/n00bKeys/keymaps.lua` (add scope toggle keymap)

**Test to Run:**
```bash
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_preprompt_tab.lua')"
```

**Expected Initial Output:**
```
Error: Tab 'preprompt' not found
```

**Implementation Checklist:**
- [ ] Add preprompt to TABS constant → 3 tests pass
- [ ] Add preprompt to state.tabs → 3 tests pass
- [ ] Implement `get_preprompt_tab_content()` → 7 tests pass
- [ ] Make buffer modifiable → 9 tests pass
- [ ] Implement `extract_preprompt_text()` → 11 tests pass
- [ ] Implement `toggle_preprompt_scope()` → 14 tests pass
- [ ] Implement `refresh_preprompt_buffer()` → 16 tests pass
- [ ] Setup auto-save autocmd → 18 tests pass
- [ ] Add debouncing logic → 20 tests pass
- [ ] Update keymaps for 1-5 tabs → 21 tests pass
- [ ] Add `<C-g>` keymap for scope toggle → 22 tests pass
- [ ] Handle multi-line preprompt display → **ALL 23 TESTS PASS** ✓

---

### Phase 3: Enhanced Context Tab (1.5 hours)

**File to Modify:** `lua/n00bKeys/ui.lua`

**Test to Run:**
```bash
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_context_tab.lua')"
```

**Implementation Checklist:**
- [ ] Implement `get_context_tab_content()` → 7 tests pass
- [ ] Add pre-prompt section to content → 11 tests pass
- [ ] Add auto-refresh in `switch_tab()` → 12 tests pass
- [ ] Ensure buffer is read-only → **ALL 13 TESTS PASS** ✓

---

### Phase 4: Prompt Integration (35 minutes)

**File to Modify:** `lua/n00bKeys/prompt.lua`

**Test to Run:**
```bash
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_preprompt_integration.lua')"
```

**Implementation Checklist:**
- [ ] Add `{preprompt}` to DEFAULT_SYSTEM_PROMPT → 2 tests pass
- [ ] Modify `build_system_prompt()` to inject preprompt → 4 tests pass
- [ ] Verify ordering (preprompt before context) → 4 tests pass
- [ ] Test with HTTP mock capturing requests → **ALL 8 TESTS PASS** ✓

---

### Final Validation

```bash
# Run ALL tests (existing + new)
make test

# Expected output:
# 152 tests passed (80 existing + 72 new)
# 0 tests failed
```

---

## Test Debugging

### Common Failure Patterns

**"Module not found" errors:**
- Module hasn't been created yet (expected for TDD)
- Create the module file and re-run

**"Function does not exist" errors:**
- Function signature missing or misnamed
- Check function name matches exactly what tests call

**Buffer content doesn't match expected:**
- UI layout changed (expected during development)
- Tests verify observable content, not exact formatting
- If intentional change, tests may need adjustment

**Auto-save tests fail:**
- Debounce timer not long enough
- Tests wait 600ms - ensure timer is < 600ms
- Check autocmd is actually registered

**File I/O tests fail:**
- Permissions issue in temp directory
- JSON encoding/decoding error
- Check error messages in test output

### Debugging Individual Tests

```bash
# Run single test with verbose output
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_settings.lua', { 'save_global() creates file and load_global() reads it back' })"
```

---

## Test Philosophy Reminder

These tests follow the project's **workflow-first, anti-gaming** approach:

### ✅ DO (What These Tests Do)
- Test complete user workflows
- Verify actual buffer content via `nvim_buf_get_lines()`
- Check real file I/O (settings written to disk)
- Capture actual HTTP request bodies
- Wait for real timers (auto-save debounce)
- Verify state persists across restarts

### ❌ DON'T (What These Tests Avoid)
- Test internal implementation details
- Mock business logic (only HTTP is mocked)
- Verify function return values without side effects
- Test without observable outcomes
- Allow passing with stub implementations

### Why This Matters

If you can satisfy these tests without implementing real functionality:
- **The tests are broken, not the implementation**
- Tests must be rewritten to be more strict
- See `TESTING_STRATEGY.md` for anti-gaming principles

---

## Success Criteria

### Phase 1 Complete When:
- All 28 settings tests pass
- `lua/n00bKeys/settings.lua` exists (~250 lines)
- Files are actually written to disk
- Settings persist across cache clears

### Phase 2 Complete When:
- All 23 preprompt tab tests pass
- Tab 4 shows Pre-Prompt UI
- Radio buttons toggle visually
- Text auto-saves after 500ms
- Scope changes load different content

### Phase 3 Complete When:
- All 13 context tab tests pass
- Context tab shows full system prompt
- Pre-prompt section displays current value
- Tab auto-refreshes on switch

### Phase 4 Complete When:
- All 8 integration tests pass
- Preprompts appear in actual API requests
- Global/project scopes work correctly
- Context tab matches API prompt

### v1.2.0 Complete When:
- **ALL 152 TESTS PASS** (80 existing + 72 new)
- No test failures
- No skipped tests
- Manual smoke testing confirms UI works

---

## Quick Reference: Key Functions to Implement

### Settings Module (`lua/n00bKeys/settings.lua`)
```lua
M.get_global_settings_path()
M.get_project_settings_path()
M.find_project_root()
M.load_global()
M.load_project()
M.save_global(settings)
M.save_project(settings)
M.get_current_preprompt()
M.get_selected_scope()
M.set_selected_scope(scope)
M.save_current_preprompt(text)
M.ensure_directory(path)
M.clear_cache()
```

### UI Module (`lua/n00bKeys/ui.lua`)
```lua
-- Add to TABS constant:
{ id = "preprompt", label = "Pre-Prompt", icon = "P", order = 4 }

M.get_preprompt_tab_content()
M.get_context_tab_content()
M.extract_preprompt_text(buf_id)
M.toggle_preprompt_scope()
M.refresh_preprompt_buffer(preprompt_text)
M.setup_preprompt_autosave(buf_id)
```

### Prompt Module (`lua/n00bKeys/prompt.lua`)
```lua
-- Update DEFAULT_SYSTEM_PROMPT to include {preprompt}
-- Modify build_system_prompt() to inject preprompt
```

### Keymaps Module (`lua/n00bKeys/keymaps.lua`)
```lua
-- Update tab jump range: for i = 1, 5 do
-- Add scope toggle for preprompt buffer:
vim.keymap.set("n", "<C-g>", toggle_preprompt_scope, { buffer = buf_id })
```

---

**Ready to implement!** Start with Phase 1 and watch the tests guide you to a working implementation.
