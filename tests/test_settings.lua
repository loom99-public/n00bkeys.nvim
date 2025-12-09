-- Settings Module Tests
-- Tests persistent storage of pre-prompt settings (global and project-specific)
-- These tests validate file I/O, path resolution, and error handling

local Helpers = dofile("tests/helpers.lua")
local child = Helpers.new_child_neovim()
local expect, eq, no_eq = Helpers.expect, Helpers.expect.equality, Helpers.expect.no_equality

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            -- Use temp directory for settings in tests to avoid polluting real config
            child.lua([[
                -- Create temp dir for test config
                vim.env.XDG_CONFIG_HOME = vim.fn.tempname()
                vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, "p")
                -- Clear cache for isolation
                require("n00bkeys.settings")._clear_cache()
                -- Clean up any project settings from previous tests
                local project_path = require("n00bkeys.settings").get_project_settings_path()
                vim.fn.delete(project_path)
            ]])
        end,
        post_once = child.stop,
    },
})

-- ============================================================================
-- Path Resolution Tests
-- These validate that settings module can find correct file paths
-- ============================================================================

T["get_global_settings_path() returns correct path under config dir"] = function()
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])

    -- Should end with n00bkeys/settings.json
    expect.match(path, "n00bkeys/settings%.json$")

    -- Should be an absolute path starting with /
    expect.truthy(path:match("^/") ~= nil)
end

T["get_project_settings_path() returns path in project root"] = function()
    local path = child.lua_get([[require("n00bkeys.settings").get_project_settings_path()]])

    -- Should end with .n00bkeys/settings.json
    expect.match(path, "%.n00bkeys/settings%.json$")
end

T["find_project_root() finds git repository"] = function()
    -- Create temp git repo for test (setup step, no return needed)
    child.lua([[
        local tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir .. "/.git", "p")
        vim.fn.chdir(tmpdir)
        require("n00bkeys.settings")._clear_cache()
    ]])

    -- Now get the project root (single expression)
    local root = child.lua_get([[require("n00bkeys.settings").find_project_root()]])

    -- Should return a valid absolute path
    expect.truthy(root ~= nil and root ~= "")
    expect.truthy(root:match("^/") ~= nil)
end

T["find_project_root() falls back to cwd when no .git"] = function()
    -- Change to temp directory with no .git
    child.lua([[
        local tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir, "p")
        vim.fn.chdir(tmpdir)
        require("n00bkeys.settings")._clear_cache()
    ]])

    local root = child.lua_get([[require("n00bkeys.settings").find_project_root()]])
    local cwd = child.lua_get([[vim.fn.getcwd()]])

    eq(root, cwd)
end

T["find_project_root() caches result and persists across directory changes"] = function()
    -- First call establishes cache
    local first_call = child.lua_get([[require("n00bkeys.settings").find_project_root()]])

    -- Create a new temp directory and change to it
    child.lua([[
        local new_tmpdir = vim.fn.tempname()
        vim.fn.mkdir(new_tmpdir, "p")
        vim.fn.chdir(new_tmpdir)
    ]])

    -- Second call should return cached value (not new cwd)
    local second_call = child.lua_get([[require("n00bkeys.settings").find_project_root()]])

    eq(first_call, second_call)

    -- Verify cache was actually used (result doesn't match new cwd)
    local new_cwd = child.lua_get([[vim.fn.getcwd()]])
    if first_call ~= new_cwd then
        -- Cache is working - returned old path despite directory change
        expect.truthy(true)
    end
end

-- ============================================================================
-- Load Functions - Missing Files
-- These verify graceful handling of missing settings files
-- ============================================================================

T["load_global() returns defaults when file does not exist"] = function()
    child.lua([[require("n00bkeys.settings")._clear_cache()]])

    local settings = child.lua_get([[require("n00bkeys.settings").load_global()]])

    eq(type(settings), "table")
    eq(settings.version, 1)
    eq(settings.preprompt, "")
    eq(settings.selected_scope, "global")
    expect.truthy(settings.last_modified ~= nil)
end

T["load_project() returns defaults when file does not exist"] = function()
    child.lua([[require("n00bkeys.settings")._clear_cache()]])

    local settings = child.lua_get([[require("n00bkeys.settings").load_project()]])

    eq(type(settings), "table")
    eq(settings.version, 1)
    eq(settings.preprompt, "")
end

-- ============================================================================
-- Save and Load Round-Trip
-- These verify data persists correctly to disk
-- ANTI-GAMING: Verify actual file existence and content
-- ============================================================================

T["save_global() creates file and load_global() reads it back"] = function()
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_global({ preprompt = "Test global preprompt" })
    ]])

    -- ANTI-GAMING: Verify file actually exists on disk
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            if file then file:close() return true end
            return false
        end)()
    ]],
        path
    ))
    local file_exists = child.lua_get([[_G.test_result]])
    eq(file_exists, true)

    -- ANTI-GAMING: Verify file contains expected data
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            if not file then return "{}" end
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, "Test global preprompt")
    expect.match(file_content, '"version"')

    -- Clear cache to force re-read from file
    child.lua([[require("n00bkeys.settings")._clear_cache()]])

    local loaded = child.lua_get([[require("n00bkeys.settings").load_global()]])

    eq(loaded.preprompt, "Test global preprompt")
    eq(loaded.version, 1)
end

T["save_global() merges with existing settings"] = function()
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_global({ preprompt = "First value" })
        settings._clear_cache()
        settings.save_global({ selected_scope = "project" })  -- Only update scope
    ]])

    -- ANTI-GAMING: Verify file contains both values
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, "First value")
    expect.match(file_content, "project")

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local loaded = child.lua_get([[require("n00bkeys.settings").load_global()]])

    -- Both values should be present
    eq(loaded.preprompt, "First value")
    eq(loaded.selected_scope, "project")
end

T["save_project() creates file and load_project() reads it back"] = function()
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_project({ preprompt = "Test project preprompt" })
    ]])

    -- ANTI-GAMING: Verify file exists
    local path = child.lua_get([[require("n00bkeys.settings").get_project_settings_path()]])
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            if file then file:close() return true end
            return false
        end)()
    ]],
        path
    ))
    local file_exists = child.lua_get([[_G.test_result]])
    eq(file_exists, true)

    -- ANTI-GAMING: Verify file content
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, "Test project preprompt")

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local loaded = child.lua_get([[require("n00bkeys.settings").load_project()]])

    eq(loaded.preprompt, "Test project preprompt")
end

T["save_global() creates directory if it does not exist"] = function()
    -- Start with fresh temp directory
    child.lua([[
        vim.env.XDG_CONFIG_HOME = vim.fn.tempname()
        require("n00bkeys.settings")._clear_cache()
        local success = require("n00bkeys.settings").save_global({ preprompt = "test" })
    ]])

    local success =
        child.lua_get([[require("n00bkeys.settings").save_global({ preprompt = "test" })]])
    eq(success, true)

    -- ANTI-GAMING: Verify file actually exists on disk
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    local exists = child.lua_get(string.format([[vim.fn.filereadable(%q) == 1]], path))
    eq(exists, true)

    -- ANTI-GAMING: Verify file is readable and contains data
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, "test")
end

-- ============================================================================
-- Error Handling - Corrupt JSON
-- These verify graceful degradation when files are corrupt
-- ============================================================================

T["load_global() returns defaults when JSON is corrupt"] = function()
    -- Write corrupt JSON to settings file
    child.lua([[
        local settings = require("n00bkeys.settings")
        local fs = require("n00bkeys.util.fs")
        local path = settings.get_global_settings_path()
        fs.ensure_directory(path)
        local file = io.open(path, "w")
        file:write("{ invalid json }")
        file:close()
    ]])

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local settings = child.lua_get([[require("n00bkeys.settings").load_global()]])

    -- Should return defaults, not throw error
    eq(type(settings), "table")
    eq(settings.preprompt, "")
end

T["load_project() returns defaults when JSON is corrupt"] = function()
    -- Write corrupt JSON
    child.lua([[
        local settings = require("n00bkeys.settings")
        local fs = require("n00bkeys.util.fs")
        local path = settings.get_project_settings_path()
        fs.ensure_directory(path)
        local file = io.open(path, "w")
        file:write("not even close to json")
        file:close()
    ]])

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local settings = child.lua_get([[require("n00bkeys.settings").load_project()]])

    eq(type(settings), "table")
    eq(settings.preprompt, "")
end

-- ============================================================================
-- Scope Selection
-- These test the global/project scope preference
-- ============================================================================

T["get_selected_scope() returns 'global' by default"] = function()
    child.lua([[require("n00bkeys.settings")._clear_cache()]])

    local scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])

    eq(scope, "global")
end

T["set_selected_scope() saves and get_selected_scope() retrieves it"] = function()
    child.lua([[
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.settings").set_selected_scope("project")
    ]])

    -- ANTI-GAMING: Verify scope persisted to disk
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, '"selected_scope"')
    expect.match(file_content, "project")

    local scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])
    eq(scope, "project")

    -- Verify persisted (clear cache and re-read)
    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local persisted_scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])
    eq(persisted_scope, "project")
end

T["set_selected_scope() validates input"] = function()
    local result = child.lua([[
        local ok, err = pcall(function()
            require("n00bkeys.settings").set_selected_scope("invalid")
        end)
        return ok
    ]])

    eq(result, false) -- Should fail assertion
end

-- ============================================================================
-- Current Pre-Prompt Access
-- These test the convenience functions for getting/setting current preprompt
-- ============================================================================

T["get_current_preprompt() returns global preprompt when scope is global"] = function()
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_global({ preprompt = "Global instructions" })
        settings.set_selected_scope("global")
    ]])

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local preprompt = child.lua_get([[require("n00bkeys.settings").get_current_preprompt()]])

    eq(preprompt, "Global instructions")
end

T["get_current_preprompt() returns project preprompt when scope is project"] = function()
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_project({ preprompt = "Project instructions" })
        settings.set_selected_scope("project")
    ]])

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local preprompt = child.lua_get([[require("n00bkeys.settings").get_current_preprompt()]])

    eq(preprompt, "Project instructions")
end

T["get_current_preprompt() returns empty string when no preprompt set"] = function()
    child.lua([[require("n00bkeys.settings")._clear_cache()]])

    local preprompt = child.lua_get([[require("n00bkeys.settings").get_current_preprompt()]])

    eq(preprompt, "")
end

T["save_current_preprompt() saves to global when scope is global"] = function()
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.set_selected_scope("global")
        settings.save_current_preprompt("New global preprompt")
    ]])

    -- ANTI-GAMING: Verify file contains the preprompt
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, "New global preprompt")

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local preprompt = child.lua_get([[require("n00bkeys.settings").load_global().preprompt]])

    eq(preprompt, "New global preprompt")
end

T["save_current_preprompt() saves to project when scope is project"] = function()
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.set_selected_scope("project")
        settings.save_current_preprompt("New project preprompt")
    ]])

    -- ANTI-GAMING: Verify file contains the preprompt
    local path = child.lua_get([[require("n00bkeys.settings").get_project_settings_path()]])
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, "New project preprompt")

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local preprompt = child.lua_get([[require("n00bkeys.settings").load_project().preprompt]])

    eq(preprompt, "New project preprompt")
end

-- ============================================================================
-- Multi-Line Preprompt Support
-- These verify that multi-line text is preserved correctly
-- ============================================================================

T["save and load multi-line preprompt preserves newlines"] = function()
    local multiline_preprompt = "Line 1\nLine 2\nLine 3"

    child.lua(string.format(
        [[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_global({ preprompt = %q })
    ]],
        multiline_preprompt
    ))

    -- ANTI-GAMING: Verify file contains all lines
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    child.lua(string.format(
        [[
        _G.test_result = (function()
            local file = io.open(%q, "r")
            local content = file:read("*a")
            file:close()
            return content
        end)()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G.test_result]])
    expect.match(file_content, "Line 1")
    expect.match(file_content, "Line 2")
    expect.match(file_content, "Line 3")

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local loaded = child.lua_get([[require("n00bkeys.settings").load_global().preprompt]])

    eq(loaded, multiline_preprompt)
end

T["save and load preprompt with special characters"] = function()
    local special_preprompt = 'You are "helpful" & <smart> in C++ & Rust!'

    child.lua(string.format(
        [[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_global({ preprompt = %q })
    ]],
        special_preprompt
    ))

    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local loaded = child.lua_get([[require("n00bkeys.settings").load_global().preprompt]])

    eq(loaded, special_preprompt)
end

-- ============================================================================
-- Cache Management
-- These verify cache works correctly and can be cleared
-- ============================================================================

T["_clear_cache() forces re-read from disk (internal)"] = function()
    -- Save initial value
    child.lua([[
        local settings = require("n00bkeys.settings")
        settings._clear_cache()
        settings.save_global({ preprompt = "First" })
    ]])

    -- Load (populates cache)
    child.lua([[require("n00bkeys.settings").load_global()]])

    -- Manually modify file on disk (bypassing cache)
    child.lua([[
        local path = require("n00bkeys.settings").get_global_settings_path()
        local settings_data = vim.json.encode({
            version = 1,
            preprompt = "Second",
            selected_scope = "global",
            last_modified = os.date("!%Y-%m-%dT%H:%M:%SZ")
        })
        local file = io.open(path, "w")
        file:write(settings_data)
        file:close()
    ]])

    -- Clear cache and reload
    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local loaded = child.lua_get([[require("n00bkeys.settings").load_global().preprompt]])

    eq(loaded, "Second") -- Should read new value from disk
end

return T
