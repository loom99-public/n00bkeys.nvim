local Helpers = dofile("tests/helpers.lua")

-- See https://github.com/echasnovski/mini.nvim/blob/main/lua/mini/test.lua for more documentation

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        -- This will be executed before every (even nested) case
        pre_case = function()
            -- Restart child process with custom 'init.lua' script
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        -- This will be executed one after all tests from this set are finished
        post_once = child.stop,
    },
})

-- Tests related to the `setup` method.
T["setup()"] = MiniTest.new_set()

T["setup()"]["sets exposed methods and default options value"] = function()
    child.lua([[require('n00bkeys').setup()]])

    -- global object that holds your plugin information
    Helpers.expect.global_type(child, "_G.n00bkeys", "table")

    -- public methods
    Helpers.expect.global_type(child, "_G.n00bkeys.toggle", "function")
    Helpers.expect.global_type(child, "_G.n00bkeys.disable", "function")
    Helpers.expect.global_type(child, "_G.n00bkeys.enable", "function")

    -- config
    Helpers.expect.global_type(child, "_G.n00bkeys.config", "table")

    -- assert the value, and the type
    Helpers.expect.config(child, "debug", false)
    Helpers.expect.config_type(child, "debug", "boolean")
end

T["setup()"]["overrides default values"] = function()
    child.lua([[require('n00bkeys').setup({
        -- write all the options with a value different than the default ones
        debug = true,
    })]])

    -- assert the value, and the type
    Helpers.expect.config(child, "debug", true)
    Helpers.expect.config_type(child, "debug", "boolean")
end

-- Tests for Ex command invocation
T["Ex command"] = MiniTest.new_set()

T["Ex command"]["Noobkeys and Nk commands exist after setup"] = function()
    child.lua([[require('n00bkeys').setup()]])

    -- Check both commands exist
    local commands = child.api.nvim_get_commands({})
    if not commands["Noobkeys"] then
        error("Noobkeys command was not registered")
    end
    if not commands["Nk"] then
        error("Nk command was not registered")
    end
end

T["Ex command"]["Noobkeys command opens window without errors"] = function()
    child.lua([[require('n00bkeys').setup()]])

    -- Clear any previous errors
    child.lua([[vim.v.errmsg = ""]])

    -- Execute the command
    child.cmd("Noobkeys")

    -- Check for any Vim errors
    local errmsg = child.lua_get([[vim.v.errmsg]])
    if errmsg ~= "" then
        error(string.format("Ex command produced error: %s", errmsg))
    end

    -- Verify window opened
    local win_id = child.lua_get([[require("n00bkeys.ui").state.win_id]])
    if not win_id then
        error("Window was not created")
    end

    -- Verify window is valid
    local is_valid = child.api.nvim_win_is_valid(win_id)
    if not is_valid then
        error("Window is not valid")
    end
end

T["Ex command"]["Nk alias opens window without errors"] = function()
    child.lua([[require('n00bkeys').setup()]])

    -- Clear any previous errors
    child.lua([[vim.v.errmsg = ""]])

    -- Execute the alias command
    child.cmd("Nk")

    -- Check for any Vim errors
    local errmsg = child.lua_get([[vim.v.errmsg]])
    if errmsg ~= "" then
        error(string.format("Ex command produced error: %s", errmsg))
    end

    -- Verify window opened
    local win_id = child.lua_get([[require("n00bkeys.ui").state.win_id]])
    if not win_id then
        error("Window was not created")
    end

    -- Verify window is valid
    local is_valid = child.api.nvim_win_is_valid(win_id)
    if not is_valid then
        error("Window is not valid")
    end
end

T["Ex command"]["captures vim errors in errmsg"] = function()
    child.lua([[require('n00bkeys').setup()]])

    -- Clear errmsg
    child.lua([[vim.v.errmsg = ""]])

    -- Execute command
    child.cmd("Noobkeys")

    -- Get and display any error for debugging
    local errmsg = child.lua_get([[vim.v.errmsg]])
    local exception = child.lua_get([[vim.v.exception]])
    local throwpoint = child.lua_get([[vim.v.throwpoint]])

    if errmsg ~= "" then
        print(string.format("\nvim.v.errmsg: %s", errmsg))
    end
    if exception ~= vim.NIL and exception ~= "" then
        print(string.format("\nvim.v.exception: %s", exception))
    end
    if throwpoint ~= vim.NIL and throwpoint ~= "" then
        print(string.format("\nvim.v.throwpoint: %s", throwpoint))
    end

    -- This test succeeds if no errors, but prints them for visibility
    MiniTest.expect.equality(errmsg, "")
end

T["Ex command"]["no E939 parsing errors"] = function()
    child.lua([[require('n00bkeys').setup()]])

    -- Test that neither command triggers E939 (the old N00bkeys error)
    child.lua([[vim.v.errmsg = ""]])
    child.cmd("Noobkeys")
    local errmsg1 = child.lua_get([[vim.v.errmsg]])

    child.cmd("close")

    child.lua([[vim.v.errmsg = ""]])
    child.cmd("Nk")
    local errmsg2 = child.lua_get([[vim.v.errmsg]])

    -- Neither should have E939 or "Positive count required"
    if errmsg1:match("E939") or errmsg1:match("Positive count required") then
        error(string.format("Noobkeys triggered E939: %s", errmsg1))
    end
    if errmsg2:match("E939") or errmsg2:match("Positive count required") then
        error(string.format("Nk triggered E939: %s", errmsg2))
    end
end

return T
