-- API Key Precedence Tests
-- Tests API key loading from all sources with correct priority order
-- ANTI-GAMING: Verifies actual file I/O and real API key resolution

local Helpers = dofile("tests/helpers.lua")
local child = Helpers.new_child_neovim()
local expect, eq = Helpers.expect, Helpers.expect.equality

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            -- Use temp directories to avoid pollution
            child.lua([[
                -- Temp HOME so ~/.env doesn't interfere
                local temp_home = vim.fn.tempname()
                vim.fn.mkdir(temp_home, "p")
                vim.env.HOME = temp_home

                -- Temp XDG config
                vim.env.XDG_CONFIG_HOME = vim.fn.tempname()
                vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, "p")

                -- Temp cwd so project .env doesn't interfere
                local temp_cwd = vim.fn.tempname()
                vim.fn.mkdir(temp_cwd, "p")
                vim.cmd("cd " .. temp_cwd)

                -- Clear env var
                vim.env.OPENAI_API_KEY = nil

                require("n00bkeys.settings")._clear_cache()
            ]])
        end,
        post_once = child.stop,
    },
})

-- Helper to test API key via observable HTTP behavior (UN-GAMEABLE)
-- Instead of trying to call internal functions, we make a real query
-- and verify the Authorization header contains the expected key
local function verify_api_key_via_http(expected_key)
    -- Setup HTTP mock that captures the Authorization header
    child.lua([[
        _G._test_http_request = nil
        local http = require("n00bkeys.http")
        http.post = function(url, headers, body, callback)
            _G._test_http_request = { url = url, headers = headers, body = body }
            vim.schedule(function()
                callback(nil, { choices = {{ message = { content = "test response" }}}})
            end)
        end
    ]])

    -- Make a query to trigger API key resolution
    child.lua([[
        require("n00bkeys.openai").query("test", function() end)
    ]])
    child.lua([[vim.wait(100)]])

    -- Verify the Authorization header contains the expected key
    local request = child.lua_get([[_G._test_http_request]])
    if not request then
        error("No HTTP request was made")
    end
    if not request.headers or not request.headers.Authorization then
        error("No Authorization header in HTTP request")
    end

    local auth_header = request.headers.Authorization
    local expected_header = "Bearer " .. expected_key
    eq(auth_header, expected_header)
end

-- Helper to verify API key is missing (shows error)
local function verify_api_key_missing()
    child.lua([[
        _G._test_result = nil
        require("n00bkeys.openai").query("test", function(err, response)
            _G._test_result = { err = err, response = response }
        end)
    ]])
    child.lua([[vim.wait(100)]])

    local result = child.lua_get([[_G._test_result]])
    expect.truthy(result.err ~= nil)
    expect.match(result.err.error, "OPENAI_API_KEY")
end

-- Helper to set API key via UI action (UN-GAMEABLE)
local function set_api_key_via_ui(api_key)
    child.lua(string.format(
        [[
        -- Mock user input (simulates typing API key)
        vim.ui.input = function(opts, callback)
            callback(%q)
        end

        -- Open UI and switch to Settings tab
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("settings")

        -- Trigger the edit action (THIS FUNCTION MUST EXIST)
        require("n00bkeys.ui").edit_api_key()
    ]],
        api_key
    ))

    -- Wait for async operations
    child.lua([[vim.wait(100)]])
end

-- ============================================================================
-- Environment Variable Tests (Priority 1 - Highest)
-- ============================================================================

T["env var has highest priority"] = function()
    -- Set API key via UI (Settings Panel)
    set_api_key_via_ui("settings-key")

    -- Verify file was written
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    local file_exists = child.lua_get(string.format([[vim.fn.filereadable(%q) == 1]], path))
    eq(file_exists, true)

    -- Set env var (should override)
    child.lua([[vim.env.OPENAI_API_KEY = "env-key"]])

    verify_api_key_via_http("env-key")
end

T["env var overrides all other sources"] = function()
    -- Set key via UI
    set_api_key_via_ui("settings-key")

    -- Create project .env file
    child.lua([[
        local cwd = vim.fn.getcwd()
        local file = io.open(cwd .. "/.env", "w")
        file:write("OPENAI_API_KEY=project-env-key\n")
        file:close()
    ]])

    -- Create user ~/.env file
    child.lua([[
        local home = vim.fn.expand("~")
        local file = io.open(home .. "/.env", "w")
        file:write("OPENAI_API_KEY=user-env-key\n")
        file:close()
    ]])

    -- Set env var (highest priority)
    child.lua([[vim.env.OPENAI_API_KEY = "env-var-key"]])

    verify_api_key_via_http("env-var-key")
end

-- ============================================================================
-- Settings Panel Tests (Priority 2)
-- ============================================================================

T["Settings Panel used when env var not set"] = function()
    -- Ensure env var is not set
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Set key via UI action
    set_api_key_via_ui("settings-panel-key")

    -- ANTI-GAMING: Verify file actually exists
    local path = child.lua_get([[require("n00bkeys.settings").get_global_settings_path()]])
    local file_exists = child.lua_get(string.format([[vim.fn.filereadable(%q) == 1]], path))
    eq(file_exists, true)

    -- ANTI-GAMING: Verify file contains the key
    child.lua(string.format(
        [[
        local file = io.open(%q, "r")
        _G._test_result = file:read("*a")
        file:close()
    ]],
        path
    ))
    local file_content = child.lua_get([[_G._test_result]])
    expect.match(file_content, "settings%-panel%-key")

    verify_api_key_via_http("settings-panel-key")
end

T["Settings Panel overrides project .env file"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Create project .env file
    child.lua([[
        local cwd = vim.fn.getcwd()
        local file = io.open(cwd .. "/.env", "w")
        file:write("OPENAI_API_KEY=project-env-key\n")
        file:close()
    ]])

    -- ANTI-GAMING: Verify .env file exists
    local env_exists = child.lua_get([[vim.fn.filereadable(vim.fn.getcwd() .. "/.env") == 1]])
    eq(env_exists, true)

    -- Set Settings Panel key via UI (higher priority)
    set_api_key_via_ui("settings-panel-key")

    verify_api_key_via_http("settings-panel-key")
end

T["Settings Panel respects scope selection"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Set global scope key via UI
    child.lua([[
        vim.ui.input = function(opts, callback)
            callback("global-key")
        end
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("settings")
        require("n00bkeys.settings").set_selected_scope("global")
        require("n00bkeys.ui").refresh_settings_buffer()
        require("n00bkeys.ui").edit_api_key()
    ]])
    child.lua([[vim.wait(100)]])

    -- Set project scope key via UI
    child.lua([[
        vim.ui.input = function(opts, callback)
            callback("project-key")
        end
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.ui").refresh_settings_buffer()
        require("n00bkeys.ui").edit_api_key()
    ]])
    child.lua([[vim.wait(100)]])

    -- Verify project scope
    child.lua([[require("n00bkeys.settings").set_selected_scope("project")]])
    verify_api_key_via_http("project-key")

    -- Verify global scope
    child.lua([[
        require("n00bkeys.settings").set_selected_scope("global")
        require("n00bkeys.settings")._clear_cache()
    ]])
    verify_api_key_via_http("global-key")
end

-- ============================================================================
-- Project .env File Tests (Priority 3)
-- ============================================================================

T["project .env used when Settings Panel empty"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Create project .env
    child.lua([[
        local cwd = vim.fn.getcwd()
        local file = io.open(cwd .. "/.env", "w")
        file:write("OPENAI_API_KEY=project-env-key\n")
        file:close()
    ]])

    verify_api_key_via_http("project-env-key")
end

T["project .env handles quoted values"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Create .env with quoted value
    child.lua([[
        local cwd = vim.fn.getcwd()
        local file = io.open(cwd .. "/.env", "w")
        file:write('OPENAI_API_KEY="quoted-key-value"\n')
        file:close()
    ]])

    verify_api_key_via_http("quoted-key-value")
end

T["project .env overrides user ~/.env"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Create user ~/.env
    child.lua([[
        local home = vim.fn.expand("~")
        local file = io.open(home .. "/.env", "w")
        file:write("OPENAI_API_KEY=user-env-key\n")
        file:close()
    ]])

    -- Create project .env (higher priority)
    child.lua([[
        local cwd = vim.fn.getcwd()
        local file = io.open(cwd .. "/.env", "w")
        file:write("OPENAI_API_KEY=project-env-key\n")
        file:close()
    ]])

    verify_api_key_via_http("project-env-key")
end

-- ============================================================================
-- User ~/.env File Tests (Priority 4)
-- ============================================================================

T["user ~/.env used when higher priorities empty"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Create user ~/.env
    child.lua([[
        local home = vim.fn.expand("~")
        local file = io.open(home .. "/.env", "w")
        file:write("OPENAI_API_KEY=user-home-key\n")
        file:close()
    ]])

    -- ANTI-GAMING: Verify file exists
    local user_env_path = child.lua_get([[vim.fn.expand("~/.env")]])
    local user_env_exists =
        child.lua_get(string.format([[vim.fn.filereadable(%q) == 1]], user_env_path))
    eq(user_env_exists, true)

    verify_api_key_via_http("user-home-key")
end

T["user ~/.env handles various formats"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Test with whitespace and quotes
    child.lua([[
        local home = vim.fn.expand("~")
        local file = io.open(home .. "/.env", "w")
        file:write("OPENAI_API_KEY = 'single-quoted-key'\n")
        file:close()
    ]])

    verify_api_key_via_http("single-quoted-key")
end

-- ============================================================================
-- Missing API Key Tests
-- ============================================================================

T["missing API key returns helpful error"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])
    -- Don't set key anywhere

    verify_api_key_missing()
end

T["empty string API key treated as missing"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = ""]])

    -- Set empty key via UI
    set_api_key_via_ui("")

    verify_api_key_missing()
end

-- ============================================================================
-- Isolation Tests (Each Source Works Independently)
-- ============================================================================

T["env var alone works"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = "only-env-var"]])
    verify_api_key_via_http("only-env-var")
end

T["Settings Panel alone works"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])
    set_api_key_via_ui("only-settings")
    verify_api_key_via_http("only-settings")
end

T["project .env alone works"] = function()
    child.lua([[
        vim.env.OPENAI_API_KEY = nil
        local cwd = vim.fn.getcwd()
        local file = io.open(cwd .. "/.env", "w")
        file:write("OPENAI_API_KEY=only-project-env\n")
        file:close()
    ]])
    verify_api_key_via_http("only-project-env")
end

T["user ~/.env alone works"] = function()
    child.lua([[
        vim.env.OPENAI_API_KEY = nil
        local home = vim.fn.expand("~")
        local file = io.open(home .. "/.env", "w")
        file:write("OPENAI_API_KEY=only-user-env\n")
        file:close()
    ]])
    verify_api_key_via_http("only-user-env")
end

return T
