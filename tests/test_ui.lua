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

-- Tests for open() function
T["open()"] = MiniTest.new_set()

T["open()"]["creates sidebar windows"] = function()
    child.restart()

    -- Get initial window count
    local initial_win_count = child.lua_get("#vim.api.nvim_list_wins()")

    -- Open the UI
    child.lua([[require("n00bkeys.ui").open()]])

    -- Should have 3 more windows now (conversation, input, footer)
    local win_count = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count, initial_win_count + 3)
end

T["open()"]["creates buffers with correct properties"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Check conversation buffer
    local conv_buf = child.lua_get("require('n00bkeys.ui').state.conversation_buf_id")
    local conv_valid = child.lua_get("vim.api.nvim_buf_is_valid(" .. conv_buf .. ")")
    Helpers.expect.equality(conv_valid, true)

    -- Check input buffer
    local input_buf = child.lua_get("require('n00bkeys.ui').state.input_buf_id")
    local input_valid = child.lua_get("vim.api.nvim_buf_is_valid(" .. input_buf .. ")")
    Helpers.expect.equality(input_valid, true)

    -- Check footer buffer
    local footer_buf = child.lua_get("require('n00bkeys.ui').state.footer_buf_id")
    local footer_valid = child.lua_get("vim.api.nvim_buf_is_valid(" .. footer_buf .. ")")
    Helpers.expect.equality(footer_valid, true)
end

T["open()"]["implements singleton pattern"] = function()
    child.restart()

    -- Open UI twice
    child.lua([[require("n00bkeys.ui").open()]])
    local first_win_id = child.lua_get("require('n00bkeys.ui').state.sidebar_win_id")

    child.lua([[require("n00bkeys.ui").open()]])
    local second_win_id = child.lua_get("require('n00bkeys.ui').state.sidebar_win_id")

    -- Should be the same window
    Helpers.expect.equality(first_win_id, second_win_id)

    -- Should still have only 4 windows (original + 3 sidebar)
    local win_count = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count, 4)
end

-- Tests for close() function
T["close()"] = MiniTest.new_set()

T["close()"]["cleans up all windows and buffers"] = function()
    child.restart()

    -- Open UI
    child.lua([[require("n00bkeys.ui").open()]])
    local win_count_after_open = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count_after_open, 4) -- 1 original + 3 sidebar

    -- Close UI
    child.lua([[require("n00bkeys.ui").close()]])

    -- Should be back to original window count (1)
    local win_count_after_close = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count_after_close, 1)
end

T["close()"]["resets state"] = function()
    child.restart()

    -- Open and close UI
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").close()]])

    -- Check that state is reset
    local sidebar_win = child.lua_get("require('n00bkeys.ui').state.sidebar_win_id")
    local input_win = child.lua_get("require('n00bkeys.ui').state.input_win_id")
    local footer_win = child.lua_get("require('n00bkeys.ui').state.footer_win_id")

    Helpers.expect.equality(sidebar_win, vim.NIL)
    Helpers.expect.equality(input_win, vim.NIL)
    Helpers.expect.equality(footer_win, vim.NIL)
end

T["close()"]["handles already closed window"] = function()
    child.restart()

    -- Calling close when window not open should not error
    local ok = child.lua_get([[pcall(function() require("n00bkeys.ui").close() end)]])
    Helpers.expect.equality(ok, true)
end

-- Tests for get_prompt() function
T["get_prompt()"] = MiniTest.new_set()

T["get_prompt()"]["returns empty string when input is empty"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- In new UI, input starts empty (no placeholder text)
    local prompt = child.lua_get([[require("n00bkeys.ui").get_prompt()]])
    Helpers.expect.equality(prompt, "")
end

T["get_prompt()"]["returns typed text from input buffer"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Type something in the input buffer
    child.lua([[
        local ui = require("n00bkeys.ui")
        vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, -1, false, {"test question"})
    ]])

    local prompt = child.lua_get([[require("n00bkeys.ui").get_prompt()]])
    Helpers.expect.equality(prompt, "test question")
end

T["get_prompt()"]["returns empty string when no window"] = function()
    child.restart()

    -- Try to get prompt without opening window
    local prompt = child.lua_get([[require("n00bkeys.ui").get_prompt()]])
    Helpers.expect.equality(prompt, "")
end

-- Tests for set_loading() function
T["set_loading()"] = MiniTest.new_set()

T["set_loading()"]["displays loading message in footer"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").set_loading(true)]])

    -- Check that footer contains loading message
    local buf_id = child.lua_get("require('n00bkeys.ui').state.footer_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")

    Helpers.expect.match(table.concat(lines, "\n"), "Loading")
end

T["set_loading()"]["updates state"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").set_loading(true)]])

    local is_loading = child.lua_get("require('n00bkeys.ui').state.tabs.query.is_loading")
    Helpers.expect.equality(is_loading, true)
end

-- Tests for set_error() function
T["set_error()"] = MiniTest.new_set()

T["set_error()"]["displays error message in footer"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").set_error("Test error message")]])

    -- Check that footer contains error message
    local buf_id = child.lua_get("require('n00bkeys.ui').state.footer_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")

    Helpers.expect.match(table.concat(lines, "\n"), "Error: Test error message")
end

T["set_error()"]["updates state"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").set_error("Test error")]])

    local last_error = child.lua_get("require('n00bkeys.ui').state.tabs.query.last_error")
    local is_loading = child.lua_get("require('n00bkeys.ui').state.tabs.query.is_loading")

    Helpers.expect.equality(last_error, "Test error")
    Helpers.expect.equality(is_loading, false)
end

-- Tests for set_response() function
T["set_response()"] = MiniTest.new_set()

T["set_response()"]["stores response in state"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").set_response("Use :w to save")]])

    -- Check that response is stored in state
    local last_response = child.lua_get("require('n00bkeys.ui').state.tabs.query.last_response")
    Helpers.expect.equality(last_response, "Use :w to save")
end

T["set_response()"]["clears error state"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").set_error("Error")]])
    child.lua([[require("n00bkeys.ui").set_response("Success")]])

    local last_error = child.lua_get("require('n00bkeys.ui').state.tabs.query.last_error")
    local is_loading = child.lua_get("require('n00bkeys.ui').state.tabs.query.is_loading")

    Helpers.expect.equality(last_error, vim.NIL)
    Helpers.expect.equality(is_loading, false)
end

return T
