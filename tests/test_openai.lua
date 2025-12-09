local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            -- Use temp directories to avoid .env file interference
            child.lua([[
                -- Temp HOME so ~/.env doesn't interfere
                local temp_home = vim.fn.tempname()
                vim.fn.mkdir(temp_home, "p")
                vim.env.HOME = temp_home

                -- Temp cwd so project .env doesn't interfere
                local temp_cwd = vim.fn.tempname()
                vim.fn.mkdir(temp_cwd, "p")
                vim.cmd("cd " .. temp_cwd)

                -- Clear env var
                vim.env.OPENAI_API_KEY = nil
            ]])
        end,
        post_once = child.stop,
    },
})

-- Tests for query() function
T["query()"] = MiniTest.new_set()

T["query()"]["handles successful response"] = function()
    child.restart()

    -- Setup test environment with API key
    child.lua([[
    vim.env.OPENAI_API_KEY = "test-api-key-123"

    -- Mock http.post to return success
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      vim.schedule(function()
        callback(nil, {
          choices = {
            {
              message = {
                content = "Use :w to save the file"
              }
            }
          }
        })
      end)
    end
  ]])

    child.lua([[
    local openai = require("n00bkeys.openai")
    _G.test_result = nil

    openai.query("How do I save?", function(err, response)
      _G.test_result = {err = err, response = response}
    end)
  ]])

    child.lua([[vim.wait(1000, function() return _G.test_result ~= nil end)]])

    local result = child.lua_get("_G.test_result")
    Helpers.expect.equality(result.err == nil or result.err == vim.NIL, true)
    Helpers.expect.equality(result.response, "Use :w to save the file")
end

T["query()"]["handles missing API key"] = function()
    child.restart()

    -- Ensure no API key is set - use temp directories
    child.lua([[
    -- Temp HOME so ~/.env doesn't interfere
    local temp_home = vim.fn.tempname()
    vim.fn.mkdir(temp_home, "p")
    vim.env.HOME = temp_home

    -- Temp cwd so project .env doesn't interfere
    local temp_cwd = vim.fn.tempname()
    vim.fn.mkdir(temp_cwd, "p")
    vim.cmd("cd " .. temp_cwd)

    vim.env.OPENAI_API_KEY = nil
    require("n00bkeys").setup()  -- Initialize config
  ]])

    child.lua([[
    local openai = require("n00bkeys.openai")
    _G.test_result = nil

    openai.query("How do I save?", function(err, response)
      _G.test_result = {err = err, response = response}
    end)
  ]])

    child.lua([[vim.wait(1000, function() return _G.test_result ~= nil end)]])

    local result = child.lua_get("_G.test_result")
    Helpers.expect.equality(result.response == nil or result.response == vim.NIL, true)
    Helpers.expect.match(result.err.error, "OPENAI_API_KEY not found")
end

T["query()"]["handles API error response"] = function()
    child.restart()

    child.lua([[
    vim.env.OPENAI_API_KEY = "test-api-key-123"

    -- Mock http.post to return API error
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      vim.schedule(function()
        callback(nil, {
          error = {
            message = "Invalid API key",
            type = "invalid_request_error"
          }
        })
      end)
    end
  ]])

    child.lua([[
    local openai = require("n00bkeys.openai")
    _G.test_result = nil

    openai.query("How do I save?", function(err, response)
      _G.test_result = {err = err, response = response}
    end)
  ]])

    child.lua([[vim.wait(1000, function() return _G.test_result ~= nil end)]])

    local result = child.lua_get("_G.test_result")
    Helpers.expect.equality(result.response == nil or result.response == vim.NIL, true)
    Helpers.expect.match(result.err.error, "Invalid API key")
end

T["query()"]["handles empty response"] = function()
    child.restart()

    child.lua([[
    vim.env.OPENAI_API_KEY = "test-api-key-123"

    -- Mock http.post to return empty choices
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      vim.schedule(function()
        callback(nil, {
          choices = {}
        })
      end)
    end
  ]])

    child.lua([[
    local openai = require("n00bkeys.openai")
    _G.test_result = nil

    openai.query("How do I save?", function(err, response)
      _G.test_result = {err = err, response = response}
    end)
  ]])

    child.lua([[vim.wait(1000, function() return _G.test_result ~= nil end)]])

    local result = child.lua_get("_G.test_result")
    Helpers.expect.equality(result.response == nil or result.response == vim.NIL, true)
    Helpers.expect.match(result.err.error, "No response from OpenAI")
end

T["query()"]["includes API key in headers"] = function()
    child.restart()

    child.lua([[
    vim.env.OPENAI_API_KEY = "sk-test123456"
    _G.captured_headers = nil

    -- Mock http.post to capture headers
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      _G.captured_headers = headers
      vim.schedule(function()
        callback(nil, {
          choices = {
            { message = { content = "test" } }
          }
        })
      end)
    end
  ]])

    child.lua([[
    local openai = require("n00bkeys.openai")
    openai.query("test", function() end)
  ]])

    child.lua([[vim.wait(100)]])

    local headers = child.lua_get("_G.captured_headers")
    Helpers.expect.match(headers.Authorization, "Bearer sk%-test123456")
end

T["query()"]["sends correct request format"] = function()
    child.restart()

    child.lua([[
    vim.env.OPENAI_API_KEY = "test-key"
    _G.captured_body = nil

    -- Mock http.post to capture request body
    local http = require("n00bkeys.http")
    http.post = function(url, headers, body, callback)
      _G.captured_body = body
      vim.schedule(function()
        callback(nil, {
          choices = {
            { message = { content = "test" } }
          }
        })
      end)
    end
  ]])

    child.lua([[
    require("n00bkeys").setup()
    local openai = require("n00bkeys.openai")
    openai.query("How do I quit Vim?", function() end)
  ]])

    child.lua([[vim.wait(100)]])

    local body = child.lua_get("_G.captured_body")

    -- Verify model and config
    Helpers.expect.equality(body.model, "gpt-4o-mini")
    Helpers.expect.equality(body.max_tokens, 500)
    Helpers.expect.equality(body.temperature, 0.7)

    -- Verify messages array has system and user messages
    Helpers.expect.equality(#body.messages, 2)

    -- First message should be system prompt
    Helpers.expect.equality(body.messages[1].role, "system")
    Helpers.expect.match(body.messages[1].content, "keybinding assistant")

    -- Second message should be user query
    Helpers.expect.equality(body.messages[2].role, "user")
    Helpers.expect.equality(body.messages[2].content, "How do I quit Vim?")
end

return T
