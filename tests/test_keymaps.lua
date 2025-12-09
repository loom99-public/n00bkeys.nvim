-- Tests for keybinding system

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

T["clear()"] = function()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Set a response first
    child.lua([[require("n00bkeys.ui").set_response("Test response")]])

    -- Clear
    child.lua([[require("n00bkeys.ui").clear()]])

    -- Conversation buffer should be cleared (empty or minimal content)
    local conv_buf_id = child.lua_get("require('n00bkeys.ui').state.conversation_buf_id")
    local conv_lines =
        child.lua_get("vim.api.nvim_buf_get_lines(" .. conv_buf_id .. ", 0, -1, false)")

    -- Should have minimal content after clear
    Helpers.expect.equality(#conv_lines <= 2, true)

    -- Input prompt should be empty after clear
    local prompt = child.lua_get([[require("n00bkeys.ui").get_prompt()]])
    Helpers.expect.equality(prompt, "")
end

T["focus_prompt()"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").focus_prompt()]])

    -- Should be in insert mode
    local mode = child.lua_get([[vim.api.nvim_get_mode().mode]])
    Helpers.expect.equality(mode, "i")
end

T["apply_response() with no response"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").apply_response()]])

    -- Error now shown in footer and stored in tab state (not conversation buffer)
    local last_error = child.lua_get([[require("n00bkeys.ui").get_tab_state("query").last_error]])

    Helpers.expect.match(last_error, "No response")
end

T["apply_response() with response"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").set_response("Use :w to save")]])
    child.lua([[require("n00bkeys.ui").apply_response()]])

    -- Prompt should contain the response
    local prompt = child.lua_get([[require("n00bkeys.ui").get_prompt()]])
    Helpers.expect.equality(prompt, "Use :w to save")

    -- Should be in insert mode after apply
    local mode = child.lua_get([[vim.api.nvim_get_mode().mode]])
    Helpers.expect.equality(mode, "i")
end

T["keymaps module is loaded"] = function()
    -- Open UI (should load keymaps module)
    child.lua([[require("n00bkeys.ui").open()]])

    -- Verify the keymaps module exists
    local keymaps_loaded = child.lua_get([[package.loaded["n00bkeys.keymaps"] ~= nil]])
    Helpers.expect.equality(keymaps_loaded, true)
end

T["custom keymaps via config"] = function()
    -- Setup with custom keymaps
    child.lua([[
    require("n00bkeys").setup({
      keymaps = {
        submit = "<leader>qq",
      }
    })
  ]])

    child.lua([[require("n00bkeys.ui").open()]])

    -- Verify config was applied (indirectly by checking it doesn't error)
    local buf_id = child.lua_get("require('n00bkeys.ui').state.tabs.query.buf_id")
    Helpers.expect.equality(type(buf_id), "number")
end

T["state tracks last_response"] = function()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Initially no last_response
    local initial = child.lua_get("require('n00bkeys.ui').state.tabs.query.last_response")
    Helpers.expect.equality(initial, vim.NIL)

    -- After setting response, last_response should be set
    child.lua([[require("n00bkeys.ui").set_response("Test response")]])
    local after = child.lua_get("require('n00bkeys.ui').state.tabs.query.last_response")
    Helpers.expect.equality(after, "Test response")
end

return T
