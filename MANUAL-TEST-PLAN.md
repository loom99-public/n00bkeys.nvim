# n00bkeys Manual Test Plan

This document describes manual testing procedures that complement the automated test suite. These tests focus on aspects that cannot be easily automated: visual UI quality, user experience, and interactive workflows.

## Prerequisites

- Neovim 0.9.5+ installed
- OpenAI API key set (`export OPENAI_API_KEY=your-key`)
- Plugin installed and loaded
- Internet connection for API tests

## Test Environment Setup

```bash
# Set API key
export OPENAI_API_KEY=your-actual-api-key

# Start Neovim
nvim

# Load plugin (if not auto-loaded)
:lua require('n00bkeys').setup()
```

---

## P0: Critical Manual Tests

### P0-2: UI Visual Quality Inspection

**Test ID:** MT-P0-2
**Objective:** Verify the floating window appears correctly and is visually appealing

**Steps:**
1. Open Neovim
2. Run `:n00bkeys`
3. Observe the floating window

**Expected Results:**
- [ ] Window appears centered on screen
- [ ] Window has rounded borders (not straight lines)
- [ ] Title "n00bkeys" is visible at top
- [ ] Window size is appropriate (60% width, 40% height)
- [ ] Background color distinguishes from main editor
- [ ] Prompt text is visible and editable
- [ ] Cursor appears in the prompt area
- [ ] No visual artifacts or rendering glitches

**Pass Criteria:** All visual elements render correctly and look professional

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P0-3: Interactive Keybinding Validation

**Test ID:** MT-P0-3
**Objective:** Verify all keybindings work correctly through actual keystrokes

**Steps:**
1. Open n00bkeys: `:n00bkeys`
2. Type a test query: "how do I save?"
3. Press `<CR>` (Enter) to submit
4. Wait for response
5. Press `<C-i>` to re-enter insert mode
6. Add text to the prompt
7. Press `<C-c>` to clear prompt and response
8. Type new query: "how do I quit?"
9. Press `<CR>` to submit
10. After response appears, press `<C-a>` to apply response to prompt
11. Verify response text copied to prompt
12. Press `<Esc>` to close window

**Expected Results:**
- [ ] `<CR>` submits query and shows "Loading..."
- [ ] Response appears after API call completes
- [ ] `<C-i>` allows editing prompt
- [ ] `<C-c>` clears both prompt and response areas
- [ ] `<C-a>` copies last response to prompt line
- [ ] `<Esc>` closes window and returns to editor
- [ ] No key conflicts with Neovim defaults
- [ ] Keybindings feel natural and responsive

**Pass Criteria:** All keybindings work as documented with no lag or errors

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P0-4: Live API Response Quality

**Test ID:** MT-P0-4
**Objective:** Verify OpenAI responses are relevant, accurate, and well-formatted

**Test Queries:**
1. "how do I save a file?"
2. "how do I quit vim?"
3. "how do I undo my last change?"
4. "how do I search for text?"
5. "how do I split windows?"

**For Each Query:**
1. Open `:n00bkeys`
2. Enter the query
3. Press `<CR>` and wait for response
4. Evaluate response quality

**Expected Results:**
- [ ] All responses are relevant to the question
- [ ] Responses mention correct Vim commands (:w, :q, u, /, :split)
- [ ] Responses are concise (not overly verbose)
- [ ] No JSON artifacts or formatting errors visible
- [ ] No technical jargon that would confuse n00bs
- [ ] Responses load within 1-5 seconds
- [ ] "Loading..." indicator appears during wait

**Pass Criteria:** 5/5 queries return accurate, helpful responses

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

## P1: High Priority Manual Tests

### P1-1: Multi-Turn Conversation UX

**Test ID:** MT-P1-1
**Objective:** Verify the multi-turn conversation workflow feels natural

**Scenario:** User asks a question, then asks follow-up questions

**Steps:**
1. Open `:n00bkeys`
2. Ask: "how do I delete a line?"
3. Wait for response (should mention "dd")
4. Press `<C-a>` to apply response to prompt
5. Edit prompt to: "Use dd in normal mode - what about deleting multiple lines?"
6. Submit and wait for response
7. Repeat 2-3 more follow-up questions

**Expected Results:**
- [ ] `<C-a>` makes it easy to build on previous answer
- [ ] Follow-up context feels natural
- [ ] No confusion about conversation history
- [ ] User can easily ask related questions
- [ ] Workflow feels efficient (not tedious)

**Pass Criteria:** Multi-turn conversation feels smooth and natural

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P1-2: Context Detection Accuracy

**Test ID:** MT-P1-2
**Objective:** Verify context affects response quality appropriately

**Setup:** Test in LazyVim if available, or vanilla Neovim

**Steps:**
1. Open `:n00bkeys`
2. Ask: "how do I open the file explorer?"
3. Note the response
4. Check context: `:lua print(vim.inspect(require('n00bkeys.context').collect()))`
5. Verify context includes:
   - Neovim version
   - Distribution (if LazyVim)
   - Plugin list (if any)
   - OS type

**Expected Results:**
- [ ] In LazyVim: Response mentions Neo-tree
- [ ] In vanilla Neovim: Response mentions netrw
- [ ] Context includes accurate Neovim version
- [ ] Context includes accurate OS type
- [ ] Plugin list is reasonable (top 10 if many installed)

**Pass Criteria:** Responses adapt based on detected environment

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P1-3: Error Message Quality Review

**Test ID:** MT-P1-3
**Objective:** Verify error messages are clear, helpful, and actionable

**Error Scenarios to Test:**

#### 1. Missing API Key
**Steps:**
1. Unset API key: `:lua vim.env.OPENAI_API_KEY = nil`
2. Open `:n00bkeys`
3. Submit query

**Expected:**
- [ ] Error message is visible (red text)
- [ ] Message explains API key is missing
- [ ] Message provides setup instructions
- [ ] No technical jargon or stack traces

#### 2. Invalid API Key
**Steps:**
1. Set invalid key: `:lua vim.env.OPENAI_API_KEY = "sk-invalid"`
2. Open `:n00bkeys`
3. Submit query

**Expected:**
- [ ] Error distinguishes auth error from network error
- [ ] Message mentions checking API key validity
- [ ] Prompt is preserved (not cleared)

#### 3. Network Timeout
**Steps:**
1. Set very short timeout: `:lua require('n00bkeys').setup({timeout_ms = 100})`
2. Submit query

**Expected:**
- [ ] Error mentions timeout
- [ ] Suggests checking internet connection
- [ ] Doesn't blame user

#### 4. Empty Prompt
**Steps:**
1. Open `:n00bkeys`
2. Press `<CR>` without typing anything

**Expected:**
- [ ] Error explains prompt is empty
- [ ] Asks user to enter a question
- [ ] Tone is friendly, not scolding

**Pass Criteria:** All error messages are clear, helpful, and friendly

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P1-4: Custom Configuration Testing

**Test ID:** MT-P1-4
**Objective:** Verify custom configuration options work correctly

**Test Cases:**

#### 1. Custom Keymaps
```lua
require('n00bkeys').setup({
  keymaps = {
    submit = '<C-s>',
    clear = '<C-x>',
    insert_mode = '<C-e>',
    apply_response = '<C-y>',
    close = '<C-q>',
  }
})
```
**Verify:** All new keymaps work, old keymaps don't

#### 2. Custom Model
```lua
require('n00bkeys').setup({ model = 'gpt-4o-mini' })
```
**Verify:** Responses still work (model is used)

#### 3. Custom Temperature
```lua
require('n00bkeys').setup({ temperature = 0.0 })
```
**Verify:** Responses feel more deterministic

#### 4. Debug Mode
```lua
require('n00bkeys').setup({ debug = true })
```
**Verify:** `:messages` shows debug output

**Expected Results:**
- [ ] All configuration options take effect
- [ ] No errors when changing config
- [ ] Changes persist across window open/close
- [ ] Invalid config shows helpful error

**Pass Criteria:** Custom configuration works reliably

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

## P2: Medium Priority Manual Tests

### P2-2: Neovim Version Compatibility

**Test ID:** MT-P2-2
**Objective:** Verify plugin works across supported Neovim versions

**Versions to Test:**
- Neovim 0.9.5 (minimum)
- Neovim 0.10.x (stable)
- Neovim 0.11.x (nightly)

**Setup:**
```bash
# Use bob version manager
bob install 0.9.5
bob use 0.9.5
nvim

# Repeat for each version
```

**For Each Version:**
1. Open Neovim
2. Verify plugin loads: `:n00bkeys`
3. Submit a test query
4. Verify response received
5. Check for deprecation warnings: `:messages`

**Expected Results:**
- [ ] Plugin loads on all versions
- [ ] UI renders correctly on all versions
- [ ] API calls work on all versions
- [ ] No deprecation warnings
- [ ] No version-specific errors

**Pass Criteria:** Plugin works on all supported versions

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P2-3: Edge Case Input Testing

**Test ID:** MT-P2-3
**Objective:** Verify plugin handles unusual inputs gracefully

**Test Cases:**

#### 1. Rapid Submission
**Steps:**
1. Open `:n00bkeys`
2. Type "test"
3. Press `<CR>` 10 times rapidly

**Expected:**
- [ ] No crash or hang
- [ ] Handles gracefully (ignores or queues)

#### 2. Close During Loading
**Steps:**
1. Submit query
2. Immediately press `<Esc>` during "Loading..."

**Expected:**
- [ ] Window closes cleanly
- [ ] No zombie processes
- [ ] API call is cancelled or cleaned up

#### 3. Terminal Resize
**Steps:**
1. Open `:n00bkeys`
2. Resize terminal window (make very small, then very large)

**Expected:**
- [ ] Window repositions/resizes appropriately
- [ ] No visual artifacts
- [ ] Content remains readable

#### 4. Unicode and Emoji
**Steps:**
1. Ask: "how do I use 你好 emoji 💾 in vim?"

**Expected:**
- [ ] Characters render correctly
- [ ] API handles unicode properly
- [ ] Response doesn't corrupt characters

**Pass Criteria:** All edge cases handled without crashes

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P2-4: Performance and Resource Usage

**Test ID:** MT-P2-4
**Objective:** Verify plugin is performant and doesn't leak resources

**Test Procedure:**

#### 1. Window Open Performance
**Steps:**
1. Time window open: `:n00bkeys`
2. Measure subjective responsiveness

**Expected:**
- [ ] Window opens instantly (<100ms)
- [ ] No perceptible lag

#### 2. Context Collection Performance
**Steps:**
1. First call: `:lua require('n00bkeys.context').collect()`
2. Second call: `:lua require('n00bkeys.context').collect()`
3. Compare timing (use `:profile`)

**Expected:**
- [ ] First call <50ms
- [ ] Second call <5ms (cached)

#### 3. Memory Leak Testing
**Steps:**
1. Open and close `:n00bkeys` 50 times
2. Monitor memory usage (Activity Monitor/htop)
3. Check buffer list: `:ls!`

**Expected:**
- [ ] Memory usage stable (no continuous growth)
- [ ] No zombie buffers accumulating
- [ ] Autocmds cleaned up: `:autocmd n00bkeys`

#### 4. API Response Latency
**Steps:**
1. Submit 5 queries
2. Measure time from submit to response

**Expected:**
- [ ] Average 1-5 seconds (network dependent)
- [ ] No unusually long delays
- [ ] Loading indicator visible during wait

**Pass Criteria:** Plugin is responsive and efficient

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

## P3: Low Priority Manual Tests

### P3-1: Help Documentation Accuracy

**Test ID:** MT-P3-1
**Objective:** Verify help documentation matches actual behavior

**Steps:**
1. Open help: `:help n00bkeys`
2. Read through all sections
3. Test each documented feature
4. Verify examples work

**Sections to Verify:**
- [ ] Installation instructions accurate
- [ ] Configuration examples work
- [ ] Keybinding documentation matches actual bindings
- [ ] API documentation matches actual API
- [ ] Troubleshooting section helpful
- [ ] Links work (`:help n00bkeys.setup`)

**Expected Results:**
- [ ] All documented features exist
- [ ] No undocumented breaking changes
- [ ] Examples are copy-pasteable and work
- [ ] Help formatting is clean

**Pass Criteria:** Documentation is 100% accurate

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P3-2: README Examples Validation

**Test ID:** MT-P3-2
**Objective:** Verify README examples work exactly as shown

**Steps:**
1. Follow Quick Start guide step-by-step
2. Try all configuration examples
3. Test all usage examples

**Examples to Test:**
- [ ] Installation (lazy.nvim)
- [ ] Basic setup
- [ ] Custom keymaps example
- [ ] GPT-4 example
- [ ] Custom prompt template example
- [ ] API key setup methods (env, .env, config)
- [ ] All example queries return expected type of answer

**Expected Results:**
- [ ] All examples work as documented
- [ ] No outdated information
- [ ] All code is syntactically correct

**Pass Criteria:** README is fully accurate and helpful

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

### P3-3: Loading Indicator UX

**Test ID:** MT-P3-3
**Objective:** Evaluate loading indicator user experience

**Steps:**
1. Submit several queries
2. Observe "Loading..." indicator
3. Note user experience

**Evaluation Criteria:**
- [ ] Indicator appears immediately on submit
- [ ] Text is visible and clear
- [ ] User understands processing is happening
- [ ] Doesn't look broken or frozen
- [ ] Async nature is clear (can still use Neovim)

**Known Limitation:**
- Static text (not animated spinner)
- Acceptable for v1.0.0
- Animated spinner planned for v1.1.0

**Pass Criteria:** Loading UX is "good enough" for v1.0.0

**Tested By:** __________ **Date:** __________ **Status:** [ ] Pass [ ] Fail

**Notes:**
```


```

---

## Test Summary Report

**Test Date:** __________
**Tested By:** __________
**Neovim Version:** __________
**Plugin Version:** v1.0.0

### Results Summary

| Priority | Total Tests | Passed | Failed | Notes |
|----------|-------------|--------|--------|-------|
| P0 (Critical) | 4 | | | |
| P1 (High) | 4 | | | |
| P2 (Medium) | 3 | | | |
| P3 (Low) | 3 | | | |
| **Total** | **14** | | | |

### Critical Issues Found

```
(List any critical issues that must be fixed before release)


```

### Non-Critical Issues

```
(List minor issues that can be deferred)


```

### Overall Assessment

**Ready for Production:** [ ] Yes [ ] No

**Recommendation:**
```
(Provide final recommendation and any follow-up actions)


```

---

## Automated Test Execution

The automated test suite complements these manual tests:

```bash
# Run all automated tests (50 tests)
make test

# Run live API integration tests (requires API key)
OPENAI_API_KEY=your-key make test

# Run tests on specific Neovim versions
make test-0.9.5
make test-nightly
```

**Automated Test Coverage:**
- ✅ Core functionality (11 tests)
- ✅ API integration with mocking (8 tests)
- ✅ UI state management (12 tests)
- ✅ Context collection (7 tests)
- ✅ Error handling (6 tests)
- ✅ Configuration validation (6 tests)
- ✅ **New:** Live API integration (16 tests - requires API key)

**Manual Test Coverage:** (this document)
- ⚠️ Visual UI quality
- ⚠️ Interactive keybinding workflows
- ⚠️ UX and error message quality
- ⚠️ Cross-version compatibility
- ⚠️ Documentation accuracy
- ⚠️ Real-world usage scenarios

Together, these provide comprehensive test coverage for production readiness.
