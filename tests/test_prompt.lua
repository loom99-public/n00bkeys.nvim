-- Tests for prompt template system

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

T["format_context()"] = function()
    child.lua([[
    local context = {
      neovim_version = "0.10.0",
      distribution = "LazyVim",
      plugins = {"telescope.nvim", "nvim-tree"}
    }
    _G.formatted = require("n00bkeys.prompt").format_context(context)
  ]])

    local formatted = child.lua_get("_G.formatted")

    -- Should include all context elements
    Helpers.expect.equality(type(formatted), "string")
    Helpers.expect.equality(formatted:match("0.10.0") ~= nil, true)
    Helpers.expect.equality(formatted:match("LazyVim") ~= nil, true)
    Helpers.expect.equality(formatted:match("telescope%.nvim") ~= nil, true)
end

T["format_context() with no plugins"] = function()
    child.lua([[
    local context = {
      neovim_version = "0.9.5",
      distribution = "Custom",
      plugins = {}
    }
    _G.formatted = require("n00bkeys.prompt").format_context(context)
  ]])

    local formatted = child.lua_get("_G.formatted")

    -- Should handle empty plugin list gracefully
    Helpers.expect.equality(formatted:match("none detected") ~= nil, true)
end

T["build_system_prompt()"] = function()
    child.lua([[
    _G.system_prompt = require("n00bkeys.prompt").build_system_prompt()
  ]])

    local prompt = child.lua_get("_G.system_prompt")

    -- Should include context
    Helpers.expect.equality(type(prompt), "string")
    Helpers.expect.equality(prompt:match("ENVIRONMENT") ~= nil, true)
    Helpers.expect.equality(prompt:match("Neovim:") ~= nil, true)

    -- Should include prompt instructions
    Helpers.expect.equality(prompt:match("keybinding assistant") ~= nil, true)
end

T["build_messages()"] = function()
    child.lua([[
    _G.messages = require("n00bkeys.prompt").build_messages("how do I save?")
  ]])

    local messages = child.lua_get("_G.messages")

    -- Should have system and user messages
    Helpers.expect.equality(#messages, 2)
    Helpers.expect.equality(messages[1].role, "system")
    Helpers.expect.equality(messages[2].role, "user")
    Helpers.expect.equality(messages[2].content, "how do I save?")

    -- System message should contain context
    Helpers.expect.equality(messages[1].content:match("ENVIRONMENT") ~= nil, true)
end

T["custom template via config"] = function()
    child.lua([[
    require("n00bkeys").setup({
      prompt_template = "Custom template: {context}\n\nEnd of template."
    })
    _G.system_prompt = require("n00bkeys.prompt").build_system_prompt()
  ]])

    local prompt = child.lua_get("_G.system_prompt")

    -- Should use custom template
    Helpers.expect.equality(prompt:match("^Custom template:") ~= nil, true)
    Helpers.expect.equality(prompt:match("End of template%.$") ~= nil, true)
end

return T
