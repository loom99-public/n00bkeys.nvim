# Testing Strategy: User Workflow Validation

## Mission Statement

Write functional tests that **prove users can successfully use n00bkeys** to ask questions and get helpful answers in Neovim.

## Core Principles

### 1. Mirror Real Usage
Tests execute exactly as users would:
- Same commands (`require("n00bkeys.ui").open()`)
- Same interactions (type question, press `<CR>`)
- Same data flows (submit → loading → response)
- Same UI interactions (keybindings, buffer content)

### 2. Validate True Behavior
Tests verify actual functionality, not implementation:
- ✅ User sees response in buffer
- ✅ Prompt preserved after error
- ✅ Window opens and closes correctly
- ❌ Internal function returns expected value
- ❌ Config variable has correct type
- ❌ API key source priority

### 3. Resist Gaming
Structured to prevent shortcuts:
- Use mocked responses (not stubs that pass without functionality)
- Verify buffer content (not just function calls)
- Check observable state (not internal variables)
- Test complete workflows (not isolated functions)

### 4. Few but Critical
Small number of high-value tests covering essential journeys:
- 24 user workflow tests cover 7 major user scenarios
- Each test validates complete flow from user action to observable outcome
- Tests grouped by user intent, not by code module

### 5. Fail Honestly
When functionality is broken, tests fail clearly:
- Cannot be satisfied by stubs
- Cannot be worked around
- Require actual implementation to pass

## Test Categories

### User Workflow Tests (`test_user_workflows.lua`)

**Purpose**: Prove users can successfully use n00bkeys in real scenarios

**Coverage**:
1. Basic Query Flow - Ask question, get answer
2. Multi-Turn Conversation - Apply response, ask follow-up
3. Keybinding Workflows - All 5 keybindings in realistic scenarios
4. Error Recovery - Errors shown clearly, retry works
5. Edge Cases - Empty, long, special characters
6. Window Management - Open, close, reopen
7. Loading States - User sees appropriate feedback

**Why Un-Gameable**:
- Tests complete user journeys, not isolated functions
- Verifies actual buffer content users would see
- Uses mocked HTTP responses (not mocked business logic)
- Checks multiple observable outcomes per test
- Cannot pass with stub implementations

### Integration Tests (`test_integration.lua`)

**Purpose**: Validate all modules work together correctly

**Coverage**:
- Full flow with successful response
- Error response handling
- Empty prompt rejection
- Request contains system + user messages

**Why Un-Gameable**:
- Tests actual HTTP request body structure
- Verifies system prompt includes context
- Checks buffer content after async completion

### Component Tests

**UI Tests** (`test_ui.lua`):
- Window creation and cleanup
- Buffer properties
- State management
- Error/response display

**OpenAI Tests** (`test_openai.lua`):
- Successful response parsing
- Error handling
- Request format
- Header construction

**Keymaps Tests** (`test_keymaps.lua`):
- Clear functionality
- Focus prompt
- Apply response
- State tracking

## Mocking Strategy

### What We Mock

**External HTTP Calls**:
```lua
local http = require("n00bkeys.http")
http.post = function(url, headers, body, callback)
  vim.schedule(function()
    callback(nil, {
      choices = {
        { message = { content = "Use :w to save" } }
      }
    })
  end)
end
```

**Why**: External API calls are not deterministic and require API keys

### What We DON'T Mock

- UI buffer creation/manipulation
- Window management
- State tracking
- Keybinding behavior
- Prompt construction
- Response display logic

**Why**: These are the actual functionality we're testing

## Testing Anti-Patterns (Avoided)

### ❌ Testing Implementation Details

```lua
-- BAD: Tests internal function
local api_key = get_api_key()
assert(api_key == "test-key")

-- GOOD: Tests user-visible behavior
submit_query()
wait_for_completion()
assert(get_buffer_content():match("Error:.*API key"))
```

### ❌ Mocking What You're Testing

```lua
-- BAD: Mocks the submit_query function
ui.submit_query = function() return "success" end
assert(ui.submit_query() == "success")

-- GOOD: Mocks external HTTP, tests real submit_query
setup_mock_success("Use :w")
ui.submit_query()
wait_for_completion()
assert(get_buffer_content():match(":w"))
```

### ❌ Tests That Pass with Stubs

```lua
-- BAD: Would pass even if submit_query does nothing
setup_mock_success("test")
ui.submit_query()
assert(true) -- Meaningless assertion

-- GOOD: Fails if submit_query doesn't actually call HTTP
setup_mock_success("test")
ui.submit_query()
wait_for_completion()
assert(get_buffer_content():match("Response:")) -- Must show response
```

### ❌ Testing Without Observable Outcomes

```lua
-- BAD: Tests internal state only
ui.set_response("test")
assert(ui.state.last_response == "test")

-- GOOD: Tests what user sees
ui.set_response("test")
assert(get_buffer_content():match("Response:.*test"))
assert(ui.state.last_response == "test") -- Also check state
```

## Example: Un-Gameable Test Breakdown

```lua
T["Multi-Turn Conversation"]["user can edit applied response and submit follow-up"] = function()
  -- SETUP: Mock external HTTP only
  setup_mock_success("Press gd to go to definition")

  -- USER ACTION 1: Ask initial question
  child.lua([[require("n00bkeys.ui").open()]])
  child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.buf_id, 0, 1, false, {"go to definition"})
    ui.submit_query()
  ]])
  wait_for_completion()

  -- VERIFY 1: Response received
  -- Cannot be faked - must actually query and display response
  local content = get_buffer_content()
  Helpers.expect.match(content, "Press gd")

  -- USER ACTION 2: Apply response to prompt
  child.lua([[require("n00bkeys.ui").apply_response()]])

  -- VERIFY 2: Prompt contains previous response
  -- Cannot be faked - must actually copy response to prompt line
  local prompt = get_prompt_line()
  Helpers.expect.equality(prompt, "Press gd to go to definition")

  -- USER ACTION 3: Edit and submit follow-up
  child.lua([[
    vim.api.nvim_buf_set_lines(ui.state.buf_id, 0, 1, false,
      {"Press gd to go to definition - what if that doesn't work?"})
  ]])
  setup_mock_success("Try using :LSP commands")
  child.lua([[ui.submit_query()]])
  wait_for_completion()

  -- VERIFY 3: Second response displayed
  -- Cannot be faked - must handle second query correctly
  content = get_buffer_content()
  Helpers.expect.match(content, "LSP commands")
end
```

**Why This Test is Un-Gameable**:

1. **Real Buffer Operations**: Uses actual `nvim_buf_set_lines()` and `nvim_buf_get_lines()`
2. **Complete Workflow**: Tests entire multi-turn conversation flow
3. **Multiple Verifications**: Checks response display, prompt update, follow-up handling
4. **Observable Outcomes**: Verifies what user actually sees in buffer
5. **Side Effect Validation**: Confirms state changes (last_response tracking)
6. **Idempotency**: Can run multiple queries in sequence

An AI cannot cheat this test by:
- ❌ Hardcoding response text (uses dynamic mocks)
- ❌ Skipping HTTP call (verification would fail)
- ❌ Faking buffer content (uses real Neovim API)
- ❌ Short-circuiting apply_response (prompt check would fail)

## Success Metrics

### Quantitative
- ✅ 75 total tests
- ✅ 24 user workflow tests
- ✅ 100% pass rate (without API key)
- ✅ 0 tests require manual setup
- ✅ 0 tests skipped in CI

### Qualitative
- ✅ Tests read like user stories
- ✅ Tests survive refactoring
- ✅ New contributors can understand tests
- ✅ Failures clearly indicate what's broken
- ✅ Tests document expected behavior

## Running Tests

```bash
# All tests (no setup required)
make test

# With coverage (if available)
make test-coverage

# Specific test file
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_user_workflows.lua')"
```

## Adding New User Workflow Tests

### Checklist

- [ ] Test describes user action, not function call
- [ ] Test uses mocked HTTP responses only
- [ ] Test verifies observable buffer/window state
- [ ] Test covers complete workflow from start to finish
- [ ] Test would fail if functionality was stubbed
- [ ] Test name explains user intent
- [ ] Test includes comments explaining why un-gameable

### Template

```lua
T["Workflow Category"]["user can <action>"] = function()
  child.restart()
  setup_mock_success("Expected response from AI")

  -- USER ACTION: Describe what user does
  child.lua([[require("n00bkeys.ui").open()]])
  -- ... user interactions

  wait_for_completion()

  -- OBSERVABLE OUTCOME: What user sees
  local content = get_buffer_content()
  Helpers.expect.match(content, "Expected content")

  -- STATE VERIFICATION: System is in correct state
  local state = child.lua_get("require('n00bkeys.ui').state")
  Helpers.expect.equality(state.is_loading, false)
end
```

## Related Documentation

- [`README.md`](./README.md) - Test suite overview and running instructions
- [`test_user_workflows.lua`](./test_user_workflows.lua) - Complete user workflow tests
- [`helpers.lua`](./helpers.lua) - Shared test utilities
- [`../CLAUDE.md`](../CLAUDE.md) - Project overview and architecture

## Philosophy: Boring Implementation, Creative Tests

**Tests Should Be Creative**: Think of edge cases users will encounter. Test happy paths AND unhappy paths. Imagine what could go wrong.

**Implementation Should Be Boring**: An expert should read the code and think "obviously this is how it's done."

**Tests Prove It Works**: If tests pass, users can successfully use the feature. If tests fail, something users care about is broken.
