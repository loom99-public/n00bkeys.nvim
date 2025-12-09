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

-- E2E integration tests
T["E2E"] = MiniTest.new_set()

T["E2E"]["full flow with successful response"] = function()
    child.restart()

    -- Setup mocks
    child.lua([[
    vim.env.OPENAI_API_KEY = "test-key"

    -- Mock http.post
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      vim.schedule(function()
        callback(nil, {
          choices = {
            { message = { content = "Use :w to save the file" } }
          }
        })
      end)
    end
  ]])

    -- Open UI
    child.lua([[require("n00bkeys.ui").open()]])

    -- Verify windows opened (sidebar has 3 windows)
    local win_count = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count, 4) -- Original + 3 sidebar windows

    -- Set a query
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"How do I save?"})
  ]])

    -- Submit the query
    child.lua([[require("n00bkeys.ui").submit_query()]])

    -- Wait for async response
    child.lua([[vim.wait(1000, function()
    return not require("n00bkeys.ui").state.tabs.query.is_loading
  end)]])

    -- Verify response is displayed in conversation buffer
    local buf_id = child.lua_get("require('n00bkeys.ui').state.conversation_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")
    local content = table.concat(lines, "\n")

    -- New UI uses [AI] labels instead of "Response:"
    Helpers.expect.match(content, "%[AI%]")
    Helpers.expect.match(content, "Use :w to save the file")
end

T["E2E"]["handles error response"] = function()
    child.restart()

    -- Setup mocks
    child.lua([[
    vim.env.OPENAI_API_KEY = "test-key"

    -- Mock http.post to return error
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      vim.schedule(function()
        callback({error = "API error occurred"}, nil)
      end)
    end
  ]])

    -- Open UI
    child.lua([[require("n00bkeys.ui").open()]])

    -- Set a query
    child.lua([[
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"How do I save?"})
  ]])

    -- Submit the query
    child.lua([[require("n00bkeys.ui").submit_query()]])

    -- Wait for async response
    child.lua([[vim.wait(1000, function()
    return not require("n00bkeys.ui").state.tabs.query.is_loading
  end)]])

    -- Verify error is displayed in conversation buffer (now shows [ERROR])
    local buf_id = child.lua_get("require('n00bkeys.ui').state.conversation_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")
    local content = table.concat(lines, "\n")

    Helpers.expect.match(content, "Error:")
    Helpers.expect.match(content, "API error occurred")
end

T["E2E"]["rejects empty prompt"] = function()
    child.restart()

    -- Open UI
    child.lua([[require("n00bkeys.ui").open()]])

    -- Try to submit without typing anything (input buffer starts empty)
    child.lua([[require("n00bkeys.ui").submit_query()]])

    -- Verify error is shown in footer
    local footer_buf = child.lua_get("require('n00bkeys.ui').state.footer_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. footer_buf .. ", 0, -1, false)")
    local content = table.concat(lines, "\n")

    Helpers.expect.match(content, "Error:")
    Helpers.expect.match(content, "Please enter a question")
end

T["E2E"]["submit_query integrates all modules"] = function()
    child.restart()

    -- Setup mocks
    child.lua([[
    vim.env.OPENAI_API_KEY = "test-key"
    _G.api_called = false

    -- Mock http.post to verify it gets called with correct data
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      _G.api_called = true
      _G.api_url = url
      _G.api_body = body
      vim.schedule(function()
        callback(nil, {
          choices = {
            { message = { content = "Response text" } }
          }
        })
      end)
    end
  ]])

    -- Open UI and submit query
    child.lua([[
    require("n00bkeys.ui").open()
    local ui = require("n00bkeys.ui")
    vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, 1, false, {"test query"})
    ui.submit_query()
  ]])

    -- Wait for completion
    child.lua([[vim.wait(1000, function()
    return not require("n00bkeys.ui").state.tabs.query.is_loading
  end)]])

    -- Verify API was called
    local api_called = child.lua_get("_G.api_called")
    Helpers.expect.equality(api_called, true)

    -- Verify OpenAI API URL
    local api_url = child.lua_get("_G.api_url")
    Helpers.expect.match(api_url, "api%.openai%.com")

    -- Verify request body contains messages
    local api_body = child.lua_get("_G.api_body")

    -- Should have at least 2 messages: system and user
    Helpers.expect.truthy(#api_body.messages >= 2)

    -- First message should be system prompt with context
    Helpers.expect.equality(api_body.messages[1].role, "system")
    Helpers.expect.match(api_body.messages[1].content, "keybinding assistant")

    -- Last message should be the user query
    local last_msg = api_body.messages[#api_body.messages]
    Helpers.expect.equality(last_msg.role, "user")
    Helpers.expect.equality(last_msg.content, "test query")
end

return T
