-- API Key Precedence Tests
-- Tests API key loading with correct priority order
-- Kept: 6 essential tests (removed 10 redundant permutation tests)

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

-- Helper to test API key via observable HTTP behavior
local function verify_api_key_via_http(expected_key)
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

    child.lua([[
        require("n00bkeys.openai").query("test", function() end)
    ]])
    child.lua([[vim.wait(100)]])

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

-- Helper to verify API key is missing
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

-- Helper to set API key via UI action
local function set_api_key_via_ui(api_key)
    child.lua(string.format(
        [[
        vim.ui.input = function(opts, callback)
            callback(%q)
        end
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("settings")
        require("n00bkeys.ui").edit_api_key()
    ]],
        api_key
    ))
    child.lua([[vim.wait(100)]])
end

-- ============================================================================
-- Priority Tests (verify correct precedence order)
-- ============================================================================

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

T["Settings Panel overrides .env files"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])

    -- Create project .env file
    child.lua([[
        local cwd = vim.fn.getcwd()
        local file = io.open(cwd .. "/.env", "w")
        file:write("OPENAI_API_KEY=project-env-key\n")
        file:close()
    ]])

    -- Set Settings Panel key via UI (higher priority)
    set_api_key_via_ui("settings-panel-key")

    verify_api_key_via_http("settings-panel-key")
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
-- Isolation Tests (each source works independently)
-- ============================================================================

T["env var alone works"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = "only-env-var"]])
    verify_api_key_via_http("only-env-var")
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

-- ============================================================================
-- Error Cases
-- ============================================================================

T["missing API key returns helpful error"] = function()
    child.lua([[vim.env.OPENAI_API_KEY = nil]])
    verify_api_key_missing()
end

return T
