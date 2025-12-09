-- User Workflow Tests
-- These tests validate REAL USER WORKFLOWS from start to finish
-- NO API keys required - all responses are mocked
-- Tests validate user-visible behavior, not implementation details

local Helpers = dofile("tests/helpers.lua")
local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        post_once = child.stop,
    },
})

-- Helper function to setup mock HTTP responses
local function setup_mock_success(response_text)
    child.lua(string.format(
        [[
    vim.env.OPENAI_API_KEY = "test-key"

    -- Mock http.post for successful responses
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      vim.schedule(function()
        callback(nil, {
          choices = {
            { message = { content = %q } }
          }
        })
      end)
    end
  ]],
        response_text
    ))
end

local function setup_mock_error(error_msg)
    child.lua(string.format(
        [[
    vim.env.OPENAI_API_KEY = "test-key"

    -- Mock http.post for error responses
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      vim.schedule(function()
        callback({error = %q}, nil)
      end)
    end
  ]],
        error_msg
    ))
end

-- Helper to wait for async operations
-- P0-1 FIX: Check return value to fail fast on timeout
local function wait_for_completion()
    child.lua([[
        _G._wait_result = vim.wait(1000, function()
            return not require("n00bkeys.ui").state.tabs.query.is_loading
        end)
    ]])
    local success = child.lua_get("_G._wait_result")
    if not success then
        error("Timeout: query never completed (is_loading stayed true)")
    end
end

-- Helper to wait for history file to be written (for conversation restore tests)
local function wait_for_history_file()
    child.lua([[
        _G._history_file_result = vim.wait(1000, function()
            local path = vim.fn.stdpath('data') .. '/n00bkeys/history.json'
            return vim.fn.filereadable(path) == 1
        end)
    ]])
    local success = child.lua_get("_G._history_file_result")
    if not success then
        error("Timeout: history file was never written")
    end
end

local function get_buffer_content()
    -- Read from conversation buffer (shows [USER] and [AI] messages)
    local buf_id = child.lua_get("require('n00bkeys.ui').state.conversation_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")
    return table.concat(lines, "\n")
end

local function get_prompt_line()
    -- Read from input buffer (where user types)
    local buf_id = child.lua_get("require('n00bkeys.ui').state.input_buf_id")
    return child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, 1, false)[1]")
end

local function get_footer_content()
    -- Read from footer buffer (shows keybindings or loading status)
    local buf_id = child.lua_get("require('n00bkeys.ui').state.footer_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")
    return table.concat(lines, "\n")
end

-- ============================================================================
-- WORKFLOW 1: Basic Query Flow
-- User opens UI -> types question -> submits -> sees response
-- ============================================================================

T["Basic Query Workflow"] = MiniTest.new_set()

T["Basic Query Workflow"]["user can ask question and get response"] = function()
    child.restart()
    setup_mock_success("Use :w to save the file")

    -- User opens n00bkeys
    child.lua([[require("n00bkeys.ui").open()]])

    -- Verify windows opened (sidebar is 3 windows: conversation, input, footer)
    local win_count = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count, 4) -- Original + 3 sidebar windows

    -- User types question
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"How do I save a file?"})
  ]])

    -- User presses <CR> to submit
    child.lua([[require("n00bkeys.ui").submit_query()]])

    -- Wait for response
    wait_for_completion()

    -- User sees response
    local content = get_buffer_content()
    -- New chat UI uses [AI] label instead of "Response:"
    Helpers.expect.match(content, "%[AI%]")
    Helpers.expect.match(content, "Use :w to save the file")

    -- Loading should be complete
    local is_loading = child.lua_get("require('n00bkeys.ui').state.tabs.query.is_loading")
    Helpers.expect.equality(is_loading, false)
end

T["Basic Query Workflow"]["user question appears in conversation after getting response"] = function()
    child.restart()
    setup_mock_success("Press dd to delete a line")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"How do I delete a line?"})
    ui.submit_query()
  ]])

    wait_for_completion()

    -- In conversational UI, input is cleared after success (ready for next message)
    local prompt = get_prompt_line()
    Helpers.expect.equality(prompt, "")

    -- User's question appears in conversation display
    local content = get_buffer_content()
    Helpers.expect.match(content, "%[USER%]")
    Helpers.expect.match(content, "How do I delete a line")
end

T["Basic Query Workflow"]["user can close window with Escape"] = function()
    child.restart()
    setup_mock_success("Test response")

    child.lua([[require("n00bkeys.ui").open()]])
    local initial_win_count = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(initial_win_count, 4) -- Original + 3 sidebar windows

    -- User presses Escape
    child.lua([[require("n00bkeys.ui").close()]])

    local final_win_count = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(final_win_count, 1) -- Only original window remains
end

-- ============================================================================
-- WORKFLOW 2: Multi-Turn Conversation
-- User asks -> gets response -> applies response -> asks follow-up -> gets context-aware answer
-- ============================================================================

T["Multi-Turn Conversation"] = MiniTest.new_set()

T["Multi-Turn Conversation"]["user can apply response to prompt with C-a"] = function()
    child.restart()
    setup_mock_success("Use dd to delete a line in normal mode")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"how do I delete?"})
    ui.submit_query()
  ]])

    wait_for_completion()

    -- User presses <C-a> to apply response to prompt
    child.lua([[require("n00bkeys.ui").apply_response()]])

    -- Prompt should now contain the previous response
    local prompt = get_prompt_line()
    Helpers.expect.equality(prompt, "Use dd to delete a line in normal mode")

    -- User should be in insert mode ready to edit
    local mode = child.lua_get([[vim.api.nvim_get_mode().mode]])
    Helpers.expect.equality(mode, "i")
end

T["Multi-Turn Conversation"]["user can edit applied response and submit follow-up"] = function()
    child.restart()

    -- First response
    setup_mock_success("Press gd to go to definition")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"go to definition"})
    ui.submit_query()
  ]])

    wait_for_completion()

    -- Apply response
    child.lua([[require("n00bkeys.ui").apply_response()]])

    -- User edits the applied text for follow-up question
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false,
      {"Press gd to go to definition - what if that doesn't work?"})
  ]])

    -- Setup mock for second response
    setup_mock_success("Try using :LSP commands or check your LSP configuration")

    -- Submit follow-up
    child.lua([[require("n00bkeys.ui").submit_query()]])
    wait_for_completion()

    -- Verify second response received
    local content = get_buffer_content()
    Helpers.expect.match(content, "LSP commands")
end

T["Multi-Turn Conversation"]["apply_response shows error when no response exists"] = function()
    child.restart()
    setup_mock_success("test")

    child.lua([[require("n00bkeys.ui").open()]])

    -- User tries to apply before getting any response
    child.lua([[require("n00bkeys.ui").apply_response()]])

    -- Error is shown in footer (not conversation buffer)
    local footer_content = get_footer_content()
    Helpers.expect.match(footer_content, "Error:")
    Helpers.expect.match(footer_content, "No response")
end

-- ============================================================================
-- WORKFLOW 3: Keybindings in Realistic Scenarios
-- Test all 5 keybindings as users would use them
-- ============================================================================

T["Keybinding Workflows"] = MiniTest.new_set()

T["Keybinding Workflows"]["C-c clears conversation and input for new question"] = function()
    child.restart()
    setup_mock_success("Use :wq to write and quit")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"old question"})
    ui.submit_query()
  ]])

    wait_for_completion()

    -- User presses <C-c> to clear and start fresh
    child.lua([[require("n00bkeys.ui").clear()]])

    -- Input should be empty (no placeholder in new UI)
    local prompt = get_prompt_line()
    Helpers.expect.equality(prompt, "")

    -- Conversation should be cleared (no more messages)
    local content = get_buffer_content()
    -- Just verify the buffer isn't showing old conversation
    Helpers.expect.no_match(content, "%[AI%]")
    Helpers.expect.no_match(content, "%[USER%]")
end

T["Keybinding Workflows"]["C-i focuses prompt for editing question"] = function()
    child.restart()
    setup_mock_success("test")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"my question"})
  ]])

    -- User presses <C-i> to enter insert mode
    child.lua([[require("n00bkeys.ui").focus_prompt()]])

    -- Should be in insert mode on prompt line
    local mode = child.lua_get([[vim.api.nvim_get_mode().mode]])
    Helpers.expect.equality(mode, "i")

    local cursor =
        child.lua_get([[vim.api.nvim_win_get_cursor(require("n00bkeys.ui").state.win_id)]])
    Helpers.expect.equality(cursor[1], 1) -- On first line (1-indexed)
end

T["Keybinding Workflows"]["Enter submits query from normal mode"] = function()
    child.restart()
    setup_mock_success("Use / to search forward")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"how to search?"})
  ]])

    -- In normal mode, press Enter (calls submit_query)
    child.lua([[require("n00bkeys.ui").submit_query()]])
    wait_for_completion()

    local content = get_buffer_content()
    -- New chat UI uses [AI] label instead of "Response:"
    Helpers.expect.match(content, "%[AI%]")
    Helpers.expect.match(content, "search")
end

T["Keybinding Workflows"]["user workflow: ask -> clear -> ask again"] = function()
    child.restart()

    -- First question
    setup_mock_success("Use yy to yank a line")
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"how to copy?"})
    ui.submit_query()
  ]])
    wait_for_completion()

    local content = get_buffer_content()
    Helpers.expect.match(content, "yank")

    -- Clear for new question
    child.lua([[require("n00bkeys.ui").clear()]])

    -- Second question
    setup_mock_success("Use p to paste")
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"how to paste?"})
    ui.submit_query()
  ]])
    wait_for_completion()

    content = get_buffer_content()
    Helpers.expect.match(content, "paste")
    -- Should NOT contain previous answer
    Helpers.expect.no_equality(content:match("yank"), "yank")
end

-- ============================================================================
-- WORKFLOW 4: Error Recovery
-- User encounters error -> prompt preserved -> can retry
-- ============================================================================

T["Error Recovery Workflows"] = MiniTest.new_set()

T["Error Recovery Workflows"]["user sees clear error when API fails"] = function()
    child.restart()
    setup_mock_error("API rate limit exceeded")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"test question"})
    ui.submit_query()
  ]])

    wait_for_completion()

    local content = get_buffer_content()
    Helpers.expect.match(content, "Error:")
    Helpers.expect.match(content, "API rate limit exceeded")
end

T["Error Recovery Workflows"]["prompt preserved after error so user can retry"] = function()
    child.restart()
    setup_mock_error("Network timeout")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"my important question"})
    ui.submit_query()
  ]])

    wait_for_completion()

    -- User's question should still be in prompt
    local prompt = get_prompt_line()
    Helpers.expect.equality(prompt, "my important question")

    -- Error should be displayed
    local content = get_buffer_content()
    Helpers.expect.match(content, "Error:")
    Helpers.expect.match(content, "Network timeout")
end

T["Error Recovery Workflows"]["user can retry after error"] = function()
    child.restart()

    -- First attempt fails
    setup_mock_error("Connection failed")
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"test retry"})
    ui.submit_query()
  ]])
    wait_for_completion()

    local content = get_buffer_content()
    Helpers.expect.match(content, "Error:")

    -- Setup successful response for retry
    setup_mock_success("Use :help to get help")

    -- User retries (presses Enter again)
    child.lua([[require("n00bkeys.ui").submit_query()]])
    wait_for_completion()

    -- Should now show success response (new chat UI uses [AI])
    content = get_buffer_content()
    Helpers.expect.match(content, "%[AI%]")
    Helpers.expect.match(content, ":help")
end

T["Error Recovery Workflows"]["user sees helpful error for missing API key"] = function()
    child.restart()

    -- No API key set - use temp directories to avoid .env interference
    child.lua([[
    -- Temp HOME so ~/.env doesn't interfere
    local temp_home = vim.fn.tempname()
    vim.fn.mkdir(temp_home, "p")
    vim.env.HOME = temp_home

    -- Temp cwd so project .env doesn't interfere
    local temp_cwd = vim.fn.tempname()
    vim.fn.mkdir(temp_cwd, "p")
    vim.cmd("cd " .. temp_cwd)

    vim.env.OPENAI_API_KEY = nil
    require("n00bkeys").setup()
  ]])

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"test question"})
    ui.submit_query()
  ]])

    wait_for_completion()

    local content = get_buffer_content()
    Helpers.expect.match(content, "Error:")
    Helpers.expect.match(content, "OPENAI_API_KEY")
end

-- ============================================================================
-- WORKFLOW 5: Edge Cases from User Perspective
-- ============================================================================

T["Edge Case Workflows"] = MiniTest.new_set()

T["Edge Case Workflows"]["handles empty prompt gracefully"] = function()
    child.restart()
    setup_mock_success("test")

    child.lua([[require("n00bkeys.ui").open()]])

    -- User submits without typing anything
    child.lua([[require("n00bkeys.ui").submit_query()]])

    -- Error is shown in footer (not conversation buffer)
    local footer_content = get_footer_content()
    Helpers.expect.match(footer_content, "Error:")
    Helpers.expect.match(footer_content, "Please enter a question")
end

T["Edge Case Workflows"]["handles very long prompt"] = function()
    child.restart()
    setup_mock_success("Here's how to save: use :w command")

    -- Create a very long prompt (1000+ characters)
    local long_prompt = string.rep("how do I save a file in Neovim? ", 50)

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua(string.format(
        [[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {%q})
    ui.submit_query()
  ]],
        long_prompt
    ))

    wait_for_completion()

    -- Should handle without crashing (new chat UI uses [AI])
    local content = get_buffer_content()
    Helpers.expect.match(content, "%[AI%]")
    Helpers.expect.match(content, ":w")
end

T["Edge Case Workflows"]["handles special characters in prompt"] = function()
    child.restart()
    setup_mock_success("Ctrl+W is for window commands, Ctrl+V is visual block mode")

    -- Prompt with special characters, Unicode, etc.
    local special_prompt = "how do I use <C-w> and <C-v>? What about ñ or 中文 or 💾?"

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua(string.format(
        [[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {%q})
    ui.submit_query()
  ]],
        special_prompt
    ))

    wait_for_completion()

    -- Should handle without crashing (new chat UI uses [AI])
    local content = get_buffer_content()
    Helpers.expect.match(content, "%[AI%]")
    Helpers.expect.match(content, "window commands")
end

T["Edge Case Workflows"]["preserves prompt after error with special characters"] = function()
    child.restart()
    setup_mock_error("API error")

    local special_prompt = "symbols: <C-x><C-o> and unicode: 🚀 test"

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua(string.format(
        [[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {%q})
    ui.submit_query()
  ]],
        special_prompt
    ))

    wait_for_completion()

    -- Prompt should be preserved exactly
    local prompt = get_prompt_line()
    Helpers.expect.equality(prompt, special_prompt)
end

T["Edge Case Workflows"]["user can ask multiple questions in sequence"] = function()
    child.restart()

    child.lua([[require("n00bkeys.ui").open()]])

    -- Question 1
    setup_mock_success("Use :w to save")
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"save file?"})
    ui.submit_query()
  ]])
    wait_for_completion()
    local content = get_buffer_content()
    Helpers.expect.match(content, ":w")

    -- Question 2
    child.lua([[require("n00bkeys.ui").clear()]])
    setup_mock_success("Use :q to quit")
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"quit vim?"})
    ui.submit_query()
  ]])
    wait_for_completion()
    content = get_buffer_content()
    Helpers.expect.match(content, ":q")

    -- Question 3
    child.lua([[require("n00bkeys.ui").clear()]])
    setup_mock_success("Use / to search")
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"how to search?"})
    ui.submit_query()
  ]])
    wait_for_completion()
    content = get_buffer_content()
    Helpers.expect.match(content, "/")
end

-- ============================================================================
-- WORKFLOW 6: Window Management
-- User opens/closes window, handles state correctly
-- ============================================================================

T["Window Management Workflows"] = MiniTest.new_set()

T["Window Management Workflows"]["opening window twice focuses existing window"] = function()
    child.restart()
    setup_mock_success("test")

    -- Open first time
    child.lua([[require("n00bkeys.ui").open()]])
    local first_win_id = child.lua_get("require('n00bkeys.ui').state.win_id")
    local win_count_1 = child.lua_get("#vim.api.nvim_list_wins()")

    -- Open second time (should not create new window)
    child.lua([[require("n00bkeys.ui").open()]])
    local second_win_id = child.lua_get("require('n00bkeys.ui').state.win_id")
    local win_count_2 = child.lua_get("#vim.api.nvim_list_wins()")

    Helpers.expect.equality(first_win_id, second_win_id)
    Helpers.expect.equality(win_count_1, win_count_2)
end

T["Window Management Workflows"]["user can reopen window after closing"] = function()
    child.restart()
    setup_mock_success("test")

    -- Open -> Close -> Open
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").close()]])
    child.lua([[require("n00bkeys.ui").open()]])

    local win_id = child.lua_get("require('n00bkeys.ui').state.win_id")
    local buf_id = child.lua_get("require('n00bkeys.ui').state.tabs.query.buf_id")

    Helpers.expect.equality(type(win_id), "number")
    Helpers.expect.equality(type(buf_id), "number")

    local win_valid = child.lua_get("vim.api.nvim_win_is_valid(" .. win_id .. ")")
    Helpers.expect.equality(win_valid, true)
end

T["Window Management Workflows"]["restore=never creates fresh state on reopen"] = function()
    child.restart()
    setup_mock_success("First response")

    -- Configure with restore_conversation = "never"
    child.lua([[require("n00bkeys").setup({ restore_conversation = "never" })]])

    -- First session
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"first question"})
    ui.submit_query()
  ]])
    wait_for_completion()

    -- Close window
    child.lua([[require("n00bkeys.ui").close()]])

    -- Reopen - should have fresh state (empty input, no placeholder)
    child.lua([[require("n00bkeys.ui").open()]])

    local prompt = get_prompt_line()
    Helpers.expect.equality(prompt, "")

    -- Conversation should be empty (new session)
    local content = get_buffer_content()
    -- A new session should not have previous conversation (it gets a new ID)
    Helpers.expect.no_match(content, "first question")
end

T["Window Management Workflows"]["restore=session restores conversation on reopen"] = function()
    child.restart()
    setup_mock_success("Test response for restoration")

    -- Configure with restore_conversation = "session" (default)
    child.lua([[require("n00bkeys").setup({ restore_conversation = "session" })]])

    -- First session - create a conversation
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"my test question"})
    ui.submit_query()
  ]])
    wait_for_completion()

    -- Verify conversation exists
    local content_before = get_buffer_content()
    Helpers.expect.match(content_before, "my test question")
    Helpers.expect.match(content_before, "Test response for restoration")

    -- Close window (wait for history to be written)
    child.lua([[require("n00bkeys.ui").close()]])
    wait_for_history_file()

    -- Reopen - should restore the previous conversation
    child.lua([[require("n00bkeys.ui").open()]])

    -- Wait a moment for restoration to complete
    child.wait(100)

    -- Conversation should be restored
    local content_after = get_buffer_content()
    Helpers.expect.match(content_after, "my test question")
    Helpers.expect.match(content_after, "Test response for restoration")

    -- Input should be empty (ready for next message)
    local prompt = get_prompt_line()
    Helpers.expect.equality(prompt, "")
end

T["Window Management Workflows"]["restore fails gracefully when conversation not found"] = function()
    child.restart()
    setup_mock_success("Test response")

    -- Configure with restore_conversation = "session"
    child.lua([[require("n00bkeys").setup({ restore_conversation = "session" })]])

    -- Manually set an invalid conversation ID that won't exist in history
    child.lua([[vim.g.n00bkeys_last_conversation_id = "conv_invalid_12345"]])

    -- Open - should gracefully fall back to new conversation
    child.lua([[require("n00bkeys.ui").open()]])
    child.wait(100)

    -- Should have fresh state (fallback to new conversation)
    local content = get_buffer_content()
    -- Should be empty or just have minimal content, not an error
    local has_error = content:match("Error") ~= nil
    Helpers.expect.equality(has_error, false)

    -- Can still submit a query successfully
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"new question after fallback"})
    ui.submit_query()
  ]])
    wait_for_completion()

    content = get_buffer_content()
    Helpers.expect.match(content, "new question after fallback")
    Helpers.expect.match(content, "Test response")
end

-- ============================================================================
-- WORKFLOW 7: Loading States
-- User sees appropriate feedback during async operations
-- ============================================================================

T["Loading State Workflows"] = MiniTest.new_set()

T["Loading State Workflows"]["loading indicator appears immediately on submit"] = function()
    child.restart()

    -- Mock with delay to verify loading state
    child.lua([[
    vim.env.OPENAI_API_KEY = "test-key"
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      -- Don't call callback immediately
      vim.defer_fn(function()
        callback(nil, {
          choices = {
            { message = { content = "Delayed response" } }
          }
        })
      end, 500) -- 500ms delay
    end
  ]])

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"test"})
    ui.submit_query()
  ]])

    -- Check immediately - should be loading
    local is_loading = child.lua_get("require('n00bkeys.ui').state.tabs.query.is_loading")
    Helpers.expect.equality(is_loading, true)

    -- Loading indicator is now in footer (not conversation buffer)
    local footer_content = get_footer_content()
    Helpers.expect.match(footer_content, "Loading")
end

T["Loading State Workflows"]["loading clears when response received"] = function()
    child.restart()
    setup_mock_success("Test response")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"test"})
    ui.submit_query()
  ]])

    wait_for_completion()

    local is_loading = child.lua_get("require('n00bkeys.ui').state.tabs.query.is_loading")
    Helpers.expect.equality(is_loading, false)
end

T["Loading State Workflows"]["loading clears when error occurs"] = function()
    child.restart()
    setup_mock_error("Test error")

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"test"})
    ui.submit_query()
  ]])

    wait_for_completion()

    local is_loading = child.lua_get("require('n00bkeys.ui').state.tabs.query.is_loading")
    Helpers.expect.equality(is_loading, false)
end

return T
