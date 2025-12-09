local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            -- Define helper functions in child process
            child.lua([[
                _G.test_get_win_title = function()
                    -- Now using winbar on sidebar_win_id instead of floating window title
                    local ui = require("n00bkeys.ui")
                    local win_id = ui.state.sidebar_win_id or ui.state.win_id
                    if win_id and vim.api.nvim_win_is_valid(win_id) then
                        return vim.wo[win_id].winbar or ""
                    end
                    return ""
                end
            ]])
        end,
        post_once = child.stop,
    },
})

-- Tests for tab bar rendering
T["render_tab_bar()"] = MiniTest.new_set()

T["render_tab_bar()"]["shows all tabs"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local tab_bar = child.lua_get([[require("n00bkeys.ui").render_tab_bar()]])

    -- Format is now compact: [1*] 2 3 4 5 | Query
    -- Only shows active tab name, but all 5 tab numbers
    Helpers.expect.match(tab_bar, "Query") -- Active tab name shown
    Helpers.expect.match(tab_bar, "1")
    Helpers.expect.match(tab_bar, "2")
    Helpers.expect.match(tab_bar, "3")
    Helpers.expect.match(tab_bar, "4")
    Helpers.expect.match(tab_bar, "5")
end

T["render_tab_bar()"]["marks active tab"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local tab_bar = child.lua_get([[require("n00bkeys.ui").render_tab_bar()]])

    -- Query should be marked as active - format is [1*] 2 3 4 5 | Query
    Helpers.expect.match(tab_bar, "%[1%*%]") -- Tab 1 has asterisk
    Helpers.expect.match(tab_bar, "| Query") -- Tab name at end
    -- Others should not have asterisk
    Helpers.expect.no_match(tab_bar, "%[2%*%]")
end

T["render_tab_bar()"]["includes tab numbers"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local tab_bar = child.lua_get([[require("n00bkeys.ui").render_tab_bar()]])

    -- Should show numbers 1-5 (format: [1*] 2 3 4 5 | Query)
    -- Active tab shows [N*], inactive tabs just show number
    Helpers.expect.match(tab_bar, "%[1%*%]") -- Active tab 1
    Helpers.expect.match(tab_bar, " 2 ") -- Inactive tab 2
    Helpers.expect.match(tab_bar, " 3 ") -- Inactive tab 3
    Helpers.expect.match(tab_bar, " 4 ") -- Inactive tab 4
    Helpers.expect.match(tab_bar, " 5 ") -- Inactive tab 5
end

-- Tests for tab buffer creation
T["create_tab_buffer()"] = MiniTest.new_set()

T["create_tab_buffer()"]["creates query buffer as modifiable"] = function()
    child.restart()
    child.lua([[
        local ui = require("n00bkeys.ui")
        local buf_id = ui.create_tab_buffer("query")
        _G.test_buf_id = buf_id
    ]])

    local buf_id = child.lua_get("_G.test_buf_id")
    local modifiable = child.lua_get("vim.api.nvim_buf_get_option(" .. buf_id .. ", 'modifiable')")
    local filetype = child.lua_get("vim.api.nvim_buf_get_option(" .. buf_id .. ", 'filetype')")

    Helpers.expect.equality(modifiable, true)
    Helpers.expect.equality(filetype, "n00bkeys-query")
end

T["create_tab_buffer()"]["creates history buffer as read-only with stub content"] = function()
    child.restart()
    child.lua([[
        local ui = require("n00bkeys.ui")
        local buf_id = ui.create_tab_buffer("history")
        _G.test_buf_id = buf_id
    ]])

    local buf_id = child.lua_get("_G.test_buf_id")
    local modifiable = child.lua_get("vim.api.nvim_buf_get_option(" .. buf_id .. ", 'modifiable')")
    local filetype = child.lua_get("vim.api.nvim_buf_get_option(" .. buf_id .. ", 'filetype')")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")

    Helpers.expect.equality(modifiable, false)
    Helpers.expect.equality(filetype, "n00bkeys-history")
    -- History tab header changed from "Query History" to "Conversation History"
    Helpers.expect.match(table.concat(lines, "\n"), "Conversation History")
    -- Should show conversation count
    Helpers.expect.match(table.concat(lines, "\n"), "conversations")
end

T["create_tab_buffer()"]["creates context buffer with stub content"] = function()
    child.restart()
    child.lua([[
        local ui = require("n00bkeys.ui")
        local buf_id = ui.create_tab_buffer("context")
        _G.test_buf_id = buf_id
    ]])

    local buf_id = child.lua_get("_G.test_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")

    Helpers.expect.match(table.concat(lines, "\n"), "Complete System Prompt")
    Helpers.expect.match(table.concat(lines, "\n"), "keybinding assistant")
end

T["create_tab_buffer()"]["creates settings buffer with actual content"] = function()
    child.restart()
    child.lua([[
        local ui = require("n00bkeys.ui")
        local buf_id = ui.create_tab_buffer("settings")
        _G.test_buf_id = buf_id
    ]])

    local buf_id = child.lua_get("_G.test_buf_id")
    local lines = child.lua_get("vim.api.nvim_buf_get_lines(" .. buf_id .. ", 0, -1, false)")

    -- Settings Panel is fully implemented, should show actual settings UI
    Helpers.expect.match(table.concat(lines, "\n"), "Plugin Settings")
    -- Should NOT say "Coming Soon" since implementation is complete
    Helpers.expect.no_match(table.concat(lines, "\n"), "Coming Soon")
    -- Should have actual settings content
    Helpers.expect.match(table.concat(lines, "\n"), "API Key")
end

-- Tests for tab switching
T["switch_tab()"] = MiniTest.new_set()

T["switch_tab()"]["switches to history tab"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Switch to history tab
    local success = child.lua_get([[require("n00bkeys.ui").switch_tab("history")]])
    Helpers.expect.equality(success, true)

    -- Verify active tab changed
    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "history")

    -- Verify buffer was created
    local history_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.history.buf_id]])
    Helpers.expect.truthy(history_buf)
end

T["switch_tab()"]["switches to context tab"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local success = child.lua_get([[require("n00bkeys.ui").switch_tab("context")]])
    Helpers.expect.equality(success, true)

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "context")
end

T["switch_tab()"]["switches to settings tab"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local success = child.lua_get([[require("n00bkeys.ui").switch_tab("settings")]])
    Helpers.expect.equality(success, true)

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "settings")
end

T["switch_tab()"]["updates window title"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Define helper function since we called restart() manually
    child.lua([[
        _G.test_get_win_title = function()
            -- Now using winbar on sidebar_win_id instead of floating window title
            local ui = require("n00bkeys.ui")
            local win_id = ui.state.sidebar_win_id or ui.state.win_id
            if win_id and vim.api.nvim_win_is_valid(win_id) then
                return vim.wo[win_id].winbar or ""
            end
            return ""
        end
    ]])

    -- Get initial title (Query should be active - format: [1*] 2 3 4 5 | Query)
    local initial_title = child.lua_get([[_G.test_get_win_title()]])
    Helpers.expect.match(initial_title, "%[1%*%]") -- Active tab number has asterisk
    Helpers.expect.match(initial_title, "| Query") -- Tab name shown after pipe

    -- Switch to history
    child.lua([[require("n00bkeys.ui").switch_tab("history")]])

    -- Get new title (History should be active - format: 1 [2*] 3 4 5 | History)
    local new_title = child.lua_get([[_G.test_get_win_title()]])
    Helpers.expect.match(new_title, "%[2%*%]") -- History is tab 2
    Helpers.expect.match(new_title, "| History") -- Tab name shown after pipe
    Helpers.expect.no_match(new_title, "%[1%*%]") -- Query tab no longer active
end

T["switch_tab()"]["creates buffer lazily on first access"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- History buffer should not exist yet
    local history_buf_before = child.lua_get([[require("n00bkeys.ui").state.tabs.history.buf_id]])
    Helpers.expect.equality(history_buf_before, vim.NIL)

    -- Switch to history tab
    child.lua([[require("n00bkeys.ui").switch_tab("history")]])

    -- Now it should exist
    local history_buf_after = child.lua_get([[require("n00bkeys.ui").state.tabs.history.buf_id]])
    Helpers.expect.truthy(history_buf_after)
end

T["switch_tab()"]["rejects invalid tab id"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local success = child.lua_get([[require("n00bkeys.ui").switch_tab("invalid_tab")]])
    Helpers.expect.equality(success, false)

    -- Active tab should still be query
    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "query")
end

T["switch_tab()"]["returns false when no window exists"] = function()
    child.restart()

    -- Try to switch without opening window
    local success = child.lua_get([[require("n00bkeys.ui").switch_tab("history")]])
    Helpers.expect.equality(success, false)
end

-- Tests for tab navigation helpers
T["switch_to_next_tab()"] = MiniTest.new_set()

T["switch_to_next_tab()"]["cycles from query to history"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    child.lua([[require("n00bkeys.ui").switch_to_next_tab()]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "history")
end

T["switch_to_next_tab()"]["cycles from settings to query"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Switch to settings
    child.lua([[require("n00bkeys.ui").switch_tab("settings")]])

    -- Next should wrap to query
    child.lua([[require("n00bkeys.ui").switch_to_next_tab()]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "query")
end

T["switch_to_next_tab()"]["cycles through all tabs"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Start on query, cycle through all
    child.lua([[require("n00bkeys.ui").switch_to_next_tab()]]) -- -> history
    local tab1 = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])

    child.lua([[require("n00bkeys.ui").switch_to_next_tab()]]) -- -> context
    local tab2 = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])

    child.lua([[require("n00bkeys.ui").switch_to_next_tab()]]) -- -> preprompt
    local tab3 = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])

    child.lua([[require("n00bkeys.ui").switch_to_next_tab()]]) -- -> settings
    local tab4 = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])

    child.lua([[require("n00bkeys.ui").switch_to_next_tab()]]) -- -> query
    local tab5 = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])

    Helpers.expect.equality(tab1, "history")
    Helpers.expect.equality(tab2, "context")
    Helpers.expect.equality(tab3, "preprompt")
    Helpers.expect.equality(tab4, "settings")
    Helpers.expect.equality(tab5, "query")
end

T["switch_to_prev_tab()"] = MiniTest.new_set()

T["switch_to_prev_tab()"]["cycles from query to settings"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    child.lua([[require("n00bkeys.ui").switch_to_prev_tab()]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "settings")
end

T["switch_to_prev_tab()"]["cycles from history to query"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Switch to history
    child.lua([[require("n00bkeys.ui").switch_tab("history")]])

    -- Previous should go to query
    child.lua([[require("n00bkeys.ui").switch_to_prev_tab()]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "query")
end

T["switch_to_tab_by_index()"] = MiniTest.new_set()

T["switch_to_tab_by_index()"]["jumps to tab 1 (query)"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Switch to another tab first
    child.lua([[require("n00bkeys.ui").switch_tab("settings")]])

    -- Jump back to tab 1
    child.lua([[require("n00bkeys.ui").switch_to_tab_by_index(1)]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "query")
end

T["switch_to_tab_by_index()"]["jumps to tab 2 (history)"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    child.lua([[require("n00bkeys.ui").switch_to_tab_by_index(2)]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "history")
end

T["switch_to_tab_by_index()"]["jumps to tab 3 (context)"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    child.lua([[require("n00bkeys.ui").switch_to_tab_by_index(3)]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "context")
end

T["switch_to_tab_by_index()"]["jumps to tab 4 (preprompt)"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    child.lua([[require("n00bkeys.ui").switch_to_tab_by_index(4)]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "preprompt")
end

T["switch_to_tab_by_index()"]["jumps to tab 5 (settings)"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    child.lua([[require("n00bkeys.ui").switch_to_tab_by_index(5)]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "settings")
end

T["switch_to_tab_by_index()"]["rejects invalid index"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    local success = child.lua_get([[require("n00bkeys.ui").switch_to_tab_by_index(0)]])
    Helpers.expect.equality(success, false)

    success = child.lua_get([[require("n00bkeys.ui").switch_to_tab_by_index(6)]])
    Helpers.expect.equality(success, false)

    -- Active tab should still be query
    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    Helpers.expect.equality(active_tab, "query")
end

-- Tests for tab state isolation
T["tab state isolation"] = MiniTest.new_set()

T["tab state isolation"]["query tab state does not affect history tab"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Set loading in query tab
    child.lua([[require("n00bkeys.ui").set_loading(true)]])

    local query_loading = child.lua_get([[require("n00bkeys.ui").state.tabs.query.is_loading]])
    Helpers.expect.equality(query_loading, true)

    -- Switch to history tab
    child.lua([[require("n00bkeys.ui").switch_tab("history")]])

    -- History tab should not be loading
    local history_loading = child.lua_get([[require("n00bkeys.ui").state.tabs.history.is_loading]])
    Helpers.expect.equality(history_loading, false)
end

-- Tests for multi-buffer cleanup
T["multi-buffer cleanup"] = MiniTest.new_set()

T["multi-buffer cleanup"]["cleans up all tab buffers when window closes"] = function()
    child.restart()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Switch through all tabs to create their buffers
    child.lua([[require("n00bkeys.ui").switch_tab("history")]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])
    child.lua([[require("n00bkeys.ui").switch_tab("preprompt")]])
    child.lua([[require("n00bkeys.ui").switch_tab("settings")]])

    -- Close window
    child.lua([[require("n00bkeys.ui").close()]])

    -- All tab buffers should be cleaned up
    local query_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.query.buf_id]])
    local history_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.history.buf_id]])
    local context_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.context.buf_id]])
    local preprompt_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.preprompt.buf_id]])
    local settings_buf = child.lua_get([[require("n00bkeys.ui").state.tabs.settings.buf_id]])

    Helpers.expect.equality(query_buf, vim.NIL)
    Helpers.expect.equality(history_buf, vim.NIL)
    Helpers.expect.equality(context_buf, vim.NIL)
    Helpers.expect.equality(preprompt_buf, vim.NIL)
    Helpers.expect.equality(settings_buf, vim.NIL)
end

return T
