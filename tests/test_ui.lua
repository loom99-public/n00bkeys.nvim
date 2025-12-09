-- UI Structure Tests
-- Core UI functionality tests (window/buffer creation, cleanup)
-- Kept: 6 essential tests (removed 15 trivial state tests covered by workflows)

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

-- Core UI structure tests
T["open()"] = MiniTest.new_set()

T["open()"]["creates sidebar windows"] = function()
    child.restart()

    local initial_win_count = child.lua_get("#vim.api.nvim_list_wins()")
    child.lua([[require("n00bkeys.ui").open()]])
    local win_count = child.lua_get("#vim.api.nvim_list_wins()")

    -- Should have 3 more windows now (conversation, input, footer)
    Helpers.expect.equality(win_count, initial_win_count + 3)
end

T["open()"]["implements singleton pattern"] = function()
    child.restart()

    child.lua([[require("n00bkeys.ui").open()]])
    local first_win_id = child.lua_get("require('n00bkeys.ui').state.sidebar_win_id")

    child.lua([[require("n00bkeys.ui").open()]])
    local second_win_id = child.lua_get("require('n00bkeys.ui').state.sidebar_win_id")

    Helpers.expect.equality(first_win_id, second_win_id)
end

T["close()"] = MiniTest.new_set()

T["close()"]["cleans up all windows"] = function()
    child.restart()

    child.lua([[require("n00bkeys.ui").open()]])
    local win_count_after_open = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count_after_open, 4)

    child.lua([[require("n00bkeys.ui").close()]])
    local win_count_after_close = child.lua_get("#vim.api.nvim_list_wins()")
    Helpers.expect.equality(win_count_after_close, 1)
end

T["close()"]["handles already closed window"] = function()
    child.restart()

    local ok = child.lua_get([[pcall(function() require("n00bkeys.ui").close() end)]])
    Helpers.expect.equality(ok, true)
end

T["get_prompt()"] = MiniTest.new_set()

T["get_prompt()"]["returns typed text from input buffer"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    child.lua([[
        local ui = require("n00bkeys.ui")
        vim.api.nvim_buf_set_lines(ui.state.input_buf_id, 0, -1, false, {"test question"})
    ]])

    local prompt = child.lua_get([[require("n00bkeys.ui").get_prompt()]])
    Helpers.expect.equality(prompt, "test question")
end

T["get_prompt()"]["returns empty string when no window"] = function()
    child.restart()

    local prompt = child.lua_get([[require("n00bkeys.ui").get_prompt()]])
    Helpers.expect.equality(prompt, "")
end

return T
