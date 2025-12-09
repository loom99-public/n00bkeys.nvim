-- Tests for context gathering module

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

T["get_neovim_version"] = function()
    local version = child.lua_get([[require("n00bkeys.context").get_neovim_version()]])

    -- Should be a string
    Helpers.expect.equality(type(version), "string")

    -- Should match pattern "X.Y.Z"
    local parts = vim.split(version, ".", { plain = true })
    Helpers.expect.equality(#parts >= 2, true)

    -- Parts should be numeric
    for _, part in ipairs(parts) do
        Helpers.expect.equality(tonumber(part) ~= nil, true)
    end
end

T["detect_distribution"] = function()
    -- In test environment (no distro), should return "Custom"
    local distro = child.lua_get([[require("n00bkeys.context").detect_distribution()]])

    Helpers.expect.equality(type(distro), "string")

    -- Should return one of the known distros or "Custom"
    local valid_distros = { "LazyVim", "NvChad", "AstroNvim", "LunarVim", "Custom" }
    local is_valid = false
    for _, v in ipairs(valid_distros) do
        if distro == v then
            is_valid = true
            break
        end
    end
    Helpers.expect.equality(is_valid, true)
end

T["detect_distribution with LazyVim"] = function()
    -- Mock LazyVim global
    child.lua([[vim.g.lazyvim_version = "10.0.0"]])
    local distro = child.lua_get([[require("n00bkeys.context").detect_distribution()]])

    Helpers.expect.equality(distro, "LazyVim")
end

T["get_plugin_list"] = function()
    local plugins = child.lua_get([[require("n00bkeys.context").get_plugin_list()]])

    -- Should be a table
    Helpers.expect.equality(type(plugins), "table")

    -- Should be an array (all values should be strings if present)
    for i, plugin in ipairs(plugins) do
        Helpers.expect.equality(type(plugin), "string")
    end
end

T["collect"] = function()
    -- Clear any cached data first
    child.lua([[require("n00bkeys.context")._clear_cache()]])

    local ctx = child.lua_get([[require("n00bkeys.context").collect()]])

    -- Should have all required fields
    Helpers.expect.equality(type(ctx.neovim_version), "string")
    Helpers.expect.equality(type(ctx.distribution), "string")
    Helpers.expect.equality(type(ctx.plugins), "table")
end

T["collect caches result"] = function()
    -- Clear cache first
    child.lua([[require("n00bkeys.context")._clear_cache()]])

    -- Track how many times get_neovim_version is called
    child.lua([[
    _G.gather_count = 0
    local context = require("n00bkeys.context")
    local original_get_neovim_version = context.get_neovim_version
    context.get_neovim_version = function()
      _G.gather_count = _G.gather_count + 1
      return original_get_neovim_version()
    end
  ]])

    -- Call collect twice
    child.lua([[require("n00bkeys.context").collect()]])
    child.lua([[require("n00bkeys.context").collect()]])

    local count = child.lua_get("_G.gather_count")

    -- Should only gather once (cached)
    Helpers.expect.equality(count, 1)
end

T["_clear_cache (internal)"] = function()
    -- Populate cache
    child.lua([[require("n00bkeys.context").collect()]])

    -- Clear cache
    child.lua([[require("n00bkeys.context")._clear_cache()]])

    -- Check cache is cleared
    local cache = child.lua_get([[require("n00bkeys.context")._cache]])
    Helpers.expect.equality(cache, vim.NIL)
end

return T
