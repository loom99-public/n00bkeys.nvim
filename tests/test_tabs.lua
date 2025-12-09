-- Tab Navigation Tests
-- Essential tab switching functionality tests
-- Kept: 12 tests (removed 23 redundant variations)

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

-- Tab bar rendering (1 consolidated test)
T["render_tab_bar()"] = MiniTest.new_set()

T["render_tab_bar()"]["shows all tabs with active marker"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local tab_bar = child.lua_get([[require("n00bkeys.ui").render_tab_bar()]])

    -- Should show all 5 tabs with numbers
    Helpers.expect.match(tab_bar, "1")
    Helpers.expect.match(tab_bar, "2")
    Helpers.expect.match(tab_bar, "3")
    Helpers.expect.match(tab_bar, "4")
    Helpers.expect.match(tab_bar, "5")
    -- Active tab (Query) should be marked
    Helpers.expect.match(tab_bar, "%[1%*%]")
    Helpers.expect.match(tab_bar, "Query")
end

-- Tab buffer creation (2 tests - one per buffer type)
T["create_tab_buffer()"] = MiniTest.new_set()

T["create_tab_buffer()"]["creates modifiable query buffer"] = function()
    child.restart()
    child.lua([[
        local ui = require("n00bkeys.ui")
        _G.test_buf_id = ui.create_tab_buffer("query")
    ]])

    local buf_id = child.lua_get("_G.test_buf_id")
    local modifiable = child.lua_get("vim.api.nvim_buf_get_option(" .. buf_id .. ", 'modifiable')")
    Helpers.expect.equality(modifiable, true)
end

T["create_tab_buffer()"]["creates read-only history buffer"] = function()
    child.restart()
    child.lua([[
        local ui = require("n00bkeys.ui")
        _G.test_buf_id = ui.create_tab_buffer("history")
    ]])

    local buf_id = child.lua_get("_G.test_buf_id")
    local modifiable = child.lua_get("vim.api.nvim_buf_get_option(" .. buf_id .. ", 'modifiable')")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")

    Helpers.expect.equality(modifiable, false)
    Helpers.expect.match(table.concat(lines, "\n"), "Conversation History")
end

-- Tab switching (4 tests for core functionality)
T["switch_tab()"] = MiniTest.new_set()

T["switch_tab()"]["switches between tabs"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Switch to history
    local success = child.lua_get([[require("n00bkeys.ui").switch_tab("history")]])
    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])

    Helpers.expect.equality(success, true)
    Helpers.expect.equality(active_tab, "history")
end

T["switch_tab()"]["rejects invalid tab id"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local success = child.lua_get([[require("n00bkeys.ui").switch_tab("invalid")]])
    Helpers.expect.equality(success, false)
end

T["switch_to_next_tab()"] = MiniTest.new_set()

T["switch_to_next_tab()"]["cycles through all tabs"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Start at query (tab 1), cycle through all 5
    local tabs = {}
    for i = 1, 5 do
        table.insert(tabs, child.lua_get([[require("n00bkeys.ui").get_active_tab()]]))
        child.lua([[require("n00bkeys.ui").switch_to_next_tab()]])
    end

    -- Should have visited all tabs
    Helpers.expect.equality(tabs[1], "query")
    Helpers.expect.equality(tabs[2], "history")
    Helpers.expect.equality(tabs[3], "context")
    Helpers.expect.equality(tabs[4], "preprompt")
    Helpers.expect.equality(tabs[5], "settings")

    -- Should cycle back to query
    local final_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(final_tab, "query")
end

T["switch_to_prev_tab()"] = MiniTest.new_set()

T["switch_to_prev_tab()"]["cycles backward through tabs"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- From query, prev should go to settings (wrap around)
    child.lua([[require("n00bkeys.ui").switch_to_prev_tab()]])
    local tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(tab, "settings")
end

T["switch_to_tab_by_index()"] = MiniTest.new_set()

T["switch_to_tab_by_index()"]["jumps to any tab by index"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Jump to tab 3 (context)
    local success = child.lua_get([[require("n00bkeys.ui").switch_tab_by_index(3)]])
    local tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])

    Helpers.expect.equality(success, true)
    Helpers.expect.equality(tab, "context")
end

T["switch_to_tab_by_index()"]["rejects invalid index"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local success = child.lua_get([[require("n00bkeys.ui").switch_tab_by_index(99)]])
    Helpers.expect.equality(success, false)
end

-- Tab state isolation (1 test)
T["tab state isolation"] = MiniTest.new_set()

T["tab state isolation"]["tab states are independent"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Modify query tab state
    child.lua([[require("n00bkeys.ui").update_tab_state("query", { is_loading = true })]])

    -- Verify history tab is not affected
    local history_loading = child.lua_get([[require("n00bkeys.ui").get_tab_state("history").is_loading]])
    Helpers.expect.equality(history_loading, false)
end

-- Buffer cleanup (1 test)
T["multi-buffer cleanup"] = MiniTest.new_set()

T["multi-buffer cleanup"]["cleans up all tab buffers when closed"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Switch to multiple tabs to create their buffers
    child.lua([[require("n00bkeys.ui").switch_tab("history")]])
    child.lua([[require("n00bkeys.ui").switch_tab("settings")]])

    -- Get buffer IDs before close
    local query_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.query.buf_id]])
    local history_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.history.buf_id]])
    local settings_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.settings.buf_id]])

    -- Close the UI
    child.lua([[require("n00bkeys.ui").close()]])

    -- All buffers should be invalid now
    local query_valid = child.lua_get("vim.api.nvim_buf_is_valid(" .. query_buf .. ")")
    local history_valid = child.lua_get("vim.api.nvim_buf_is_valid(" .. history_buf .. ")")
    local settings_valid = child.lua_get("vim.api.nvim_buf_is_valid(" .. settings_buf .. ")")

    Helpers.expect.equality(query_valid, false)
    Helpers.expect.equality(history_valid, false)
    Helpers.expect.equality(settings_valid, false)
end

return T
