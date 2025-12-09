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

-- Tests for post() function
T["post()"] = MiniTest.new_set()

T["post()"]["handles successful request"] = function()
    child.restart()

    -- Mock vim.system to return success
    child.lua([[
    _G.mock_curl_response = '{"result": "success"}'
    _G.mock_curl_code = 0

    -- Override vim.system
    local original_system = vim.system
    vim.system = function(cmd, opts, callback)
      -- Simulate async callback
      vim.schedule(function()
        callback({
          code = _G.mock_curl_code,
          stdout = _G.mock_curl_response,
          stderr = ""
        })
      end)
    end
  ]])

    child.lua([[
    local http = require("n00bkeys.http")
    _G.test_result = nil

    http.post("https://api.test.com", {}, {query = "test"}, function(err, response)
      _G.test_result = {err = err, response = response}
    end)
  ]])

    -- Wait for async callback
    child.lua([[vim.wait(1000, function() return _G.test_result ~= nil end)]])

    local result = child.lua_get("_G.test_result")
    -- When successful, err should be nil (which becomes vim.NIL in Lua<->Neovim boundary)
    Helpers.expect.equality(result.err == nil or result.err == vim.NIL, true)
    Helpers.expect.equality(result.response.result, "success")
end

T["post()"]["handles curl errors"] = function()
    child.restart()

    -- Mock vim.system to return error
    child.lua([[
    _G.mock_curl_code = 7  -- Connection failed
    _G.mock_curl_stderr = "Failed to connect"

    vim.system = function(cmd, opts, callback)
      vim.schedule(function()
        callback({
          code = _G.mock_curl_code,
          stdout = "",
          stderr = _G.mock_curl_stderr
        })
      end)
    end
  ]])

    child.lua([[
    local http = require("n00bkeys.http")
    _G.test_result = nil

    http.post("https://api.test.com", {}, {query = "test"}, function(err, response)
      _G.test_result = {err = err, response = response}
    end)
  ]])

    child.lua([[vim.wait(1000, function() return _G.test_result ~= nil end)]])

    local result = child.lua_get("_G.test_result")
    -- When there's an error, response should be nil
    Helpers.expect.equality(result.response == nil or result.response == vim.NIL, true)
    Helpers.expect.equality(result.err.code, 7)
    Helpers.expect.match(result.err.error, "Failed to connect")
end

T["post()"]["handles JSON parse errors"] = function()
    child.restart()

    -- Mock vim.system to return invalid JSON
    child.lua([[
    vim.system = function(cmd, opts, callback)
      vim.schedule(function()
        callback({
          code = 0,
          stdout = "not valid json",
          stderr = ""
        })
      end)
    end
  ]])

    child.lua([[
    local http = require("n00bkeys.http")
    _G.test_result = nil

    http.post("https://api.test.com", {}, {query = "test"}, function(err, response)
      _G.test_result = {err = err, response = response}
    end)
  ]])

    child.lua([[vim.wait(1000, function() return _G.test_result ~= nil end)]])

    local result = child.lua_get("_G.test_result")
    Helpers.expect.equality(result.response == nil or result.response == vim.NIL, true)
    Helpers.expect.match(result.err.error, "Failed to parse JSON")
end

T["post()"]["includes custom headers"] = function()
    child.restart()

    -- Mock vim.system and capture the command
    child.lua([[
    _G.captured_curl_args = nil

    vim.system = function(cmd, opts, callback)
      _G.captured_curl_args = cmd
      vim.schedule(function()
        callback({
          code = 0,
          stdout = '{"result": "ok"}',
          stderr = ""
        })
      end)
    end
  ]])

    child.lua([[
    local http = require("n00bkeys.http")

    http.post("https://api.test.com", {Authorization = "Bearer token123"}, {query = "test"}, function(err, response)
    end)
  ]])

    child.wait(100) -- P1-3 FIX: Use child.wait() to pause parent process

    local captured_args = child.lua_get("_G.captured_curl_args")
    local args_str = table.concat(captured_args, " ")

    Helpers.expect.match(args_str, "Authorization: Bearer token123")
end

T["post()"]["sends JSON body"] = function()
    child.restart()

    -- Mock vim.system and capture the command
    child.lua([[
    _G.captured_curl_args = nil

    vim.system = function(cmd, opts, callback)
      _G.captured_curl_args = cmd
      vim.schedule(function()
        callback({
          code = 0,
          stdout = '{"result": "ok"}',
          stderr = ""
        })
      end)
    end
  ]])

    child.lua([[
    local http = require("n00bkeys.http")

    http.post("https://api.test.com", {}, {key = "value", number = 123}, function(err, response)
    end)
  ]])

    child.wait(100) -- P1-3 FIX: Use child.wait() to pause parent process

    local captured_args = child.lua_get("_G.captured_curl_args")
    local args_str = table.concat(captured_args, " ")

    -- Should contain the JSON-encoded body
    Helpers.expect.match(args_str, "key")
    Helpers.expect.match(args_str, "value")
end

return T
