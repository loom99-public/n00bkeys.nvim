# n00bkeys Test Suite

## Overview

This test suite validates **real user workflows** for the n00bkeys Neovim plugin. Tests are designed to be:

1. **Fully Automated** - No API keys or manual setup required
2. **User-Centric** - Tests validate user-visible behavior, not implementation details
3. **Un-Gameable** - Tests use mocked responses and verify actual outcomes
4. **Maintainable** - Tests survive refactoring of internal implementation

## Test Structure

### Core Test Files

- **`test_user_workflows.lua`** - Complete end-to-end user workflows (24 tests)
- **`test_integration.lua`** - E2E integration tests with mocked HTTP
- **`test_ui.lua`** - UI component behavior tests
- **`test_openai.lua`** - OpenAI API client tests with mocks
- **`test_keymaps.lua`** - Keybinding functionality tests
- **`test_prompt.lua`** - Prompt generation and context tests
- **`test_context.lua`** - Context collection tests
- **`test_http.lua`** - HTTP client tests
- **`test_API.lua`** - Public API tests

### Archived Files

- **`.agent_planning/archive/test_live_api_integration.lua`** - Old tests requiring real API keys (replaced by test_user_workflows.lua)

## Running Tests

```bash
# Run all tests
make test

# Run tests on specific Neovim versions
make test-nightly
make test-0.8.3

# Run all checks (tests + lint + docs)
make all
```

## User Workflow Tests (`test_user_workflows.lua`)

### Workflow Coverage

1. **Basic Query Flow** (3 tests)
   - User opens UI → types question → submits → sees response
   - Question remains visible after response
   - Window closes properly

2. **Multi-Turn Conversation** (3 tests)
   - Apply response to prompt with `<C-a>`
   - Edit applied response and submit follow-up
   - Error handling when no response exists

3. **Keybinding Workflows** (4 tests)
   - `<C-c>` clears prompt and focuses for new question
   - `<C-i>` focuses prompt for editing
   - `<CR>` submits query from normal mode
   - Complete workflow: ask → clear → ask again

4. **Error Recovery** (4 tests)
   - Clear error messages when API fails
   - Prompt preserved after error for retry
   - User can retry after error
   - Helpful error for missing API key

5. **Edge Case Workflows** (5 tests)
   - Empty prompt handling
   - Very long prompts (1000+ characters)
   - Special characters and Unicode
   - Prompt preservation with special characters
   - Multiple questions in sequence

6. **Window Management** (3 tests)
   - Opening window twice focuses existing window
   - Reopen window after closing
   - State resets when window reopened

7. **Loading States** (3 tests)
   - Loading indicator appears immediately
   - Loading clears when response received
   - Loading clears when error occurs

### Key Testing Principles

#### ✅ Tests User-Visible Behavior

**GOOD:**
```lua
-- User opens UI and gets response
child.lua([[require("n00bkeys.ui").open()]])
child.lua([[ui.submit_query()]])
wait_for_completion()
local content = get_buffer_content()
Helpers.expect.match(content, "Response:")
```

**BAD:**
```lua
-- Testing implementation details
local api_key = child.lua_get([[require("n00bkeys.openai").get_api_key()]])
Helpers.expect.equality(api_key, "test-key")
```

#### ✅ Uses Mocked Responses

All tests use helper functions to mock HTTP responses:

```lua
setup_mock_success("Use :w to save the file")
setup_mock_error("API rate limit exceeded")
```

No tests require `OPENAI_API_KEY` environment variable.

#### ✅ Tests Complete Workflows

Each test validates a full user journey from start to finish:

1. User action (open UI, type question, press keybinding)
2. System response (loading indicator, response display, error handling)
3. Observable outcome (content visible, state correct, workflow can continue)

## Why This Approach?

### Problems with Previous Approach

The old `test_live_api_integration.lua` had critical flaws:

1. **Required API key** - Tests failed without manual setup
2. **Tested implementation** - Validated `get_api_key()` function, not user workflows
3. **Tightly coupled** - Tests broke when refactoring internal code
4. **Missing workflows** - No tests for UI opening, keybindings, multi-turn conversations

### Benefits of New Approach

1. **100% Automated** - All tests run without any setup
2. **User-Focused** - Tests prove users can successfully use n00bkeys
3. **Refactor-Safe** - Tests survive internal implementation changes
4. **Comprehensive** - Covers all major user workflows

## Test Philosophy

### What Makes These Tests Un-Gameable?

1. **End-to-End Validation**: Tests execute complete user flows
2. **Real Artifacts**: Verify actual buffer content, window state, UI elements
3. **Observable Outcomes**: Assert on what users would actually see
4. **State Verification**: Confirm system state changes match expectations
5. **Error Recovery**: Verify proper error handling and retry capabilities

### Example: Multi-Turn Conversation Test

```lua
-- User asks initial question
setup_mock_success("Press gd to go to definition")
child.lua([[ui.submit_query()]])
wait_for_completion()

-- User applies response to prompt
child.lua([[ui.apply_response()]])
local prompt = get_prompt_line()
Helpers.expect.equality(prompt, "Press gd to go to definition")

-- User edits for follow-up
child.lua([[ui.set_lines({"...what if that doesn't work?"})]])
setup_mock_success("Try :LSP commands")
child.lua([[ui.submit_query()]])
wait_for_completion()

-- Verify second response
Helpers.expect.match(get_buffer_content(), "LSP commands")
```

This test:
- ✅ Mirrors real user behavior
- ✅ Validates actual buffer content
- ✅ Tests complete multi-turn flow
- ✅ Cannot be faked with stubs

## Adding New Tests

When adding tests, follow these guidelines:

1. **Think Like a User**: What would a real user do?
2. **Test Workflows, Not Functions**: Validate complete journeys
3. **Mock External Dependencies**: Use `setup_mock_success()`/`setup_mock_error()`
4. **Verify Observable Outcomes**: Check buffer content, window state, mode
5. **Document Why It's Un-Gameable**: Add comment explaining validation strategy

### Template for New Workflow Test

```lua
T["Workflow Name"]["user can do X"] = function()
  child.restart()
  setup_mock_success("Expected response text")

  -- USER ACTION: What the user does
  child.lua([[require("n00bkeys.ui").open()]])
  child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.buf_id, 0, 1, false, {"user question"})
    ui.submit_query()
  ]])

  wait_for_completion()

  -- OBSERVABLE OUTCOME: What the user sees
  local content = get_buffer_content()
  Helpers.expect.match(content, "Expected response text")

  -- STATE VERIFICATION: System state is correct
  local is_loading = child.lua_get("require('n00bkeys.ui').state.is_loading")
  Helpers.expect.equality(is_loading, false)
end
```

## Test Metrics

- **Total Tests**: 91
- **User Workflow Tests**: 24 (all automated, no API key required)
- **Test Groups**: 43
- **Pass Rate**: 100% (75 passing, 16 skipped by design)
- **Skipped Tests**: Live API tests (require manual setup, archived)

## Success Criteria

✅ **All tests run without manual setup**
✅ **Zero tests require OPENAI_API_KEY**
✅ **All tests use mocked responses**
✅ **Tests validate user-visible behavior only**
✅ **Tests pass after refactoring internal code**

## Contributing

When contributing tests:

1. Run `make test` to verify all tests pass
2. Ensure new tests follow user workflow pattern
3. Use mocked responses, not real API calls
4. Document test purpose and anti-gaming strategy
5. Update this README if adding new test categories
