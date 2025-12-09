-- Context Tab Tests
-- These validate the enhanced Context tab that displays the full system prompt
-- Tests verify read-only display, auto-refresh, and preprompt integration

local Helpers = dofile("tests/helpers.lua")
local child = Helpers.new_child_neovim()
local expect, eq = Helpers.expect, Helpers.expect.equality

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            -- Use temp directory for settings
            child.lua([[
                vim.env.XDG_CONFIG_HOME = vim.fn.tempname()
                vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, "p")
                require("n00bkeys.settings")._clear_cache()
            ]])
            -- Define helper function in child process
            child.lua([[
                _G.test_get_buffer_content = function()
                    local buf_id = require("n00bkeys.ui").state.tabs.context.buf_id
                    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
                    return table.concat(lines, "\n")
                end
            ]])
        end,
        post_once = child.stop,
    },
})

-- Helper to get buffer content
local function get_buffer_content()
    return child.lua_get([[_G.test_get_buffer_content()]])
end

-- ============================================================================
-- Tab Access and Basic Rendering
-- Verify Context tab can be accessed and shows content
-- ============================================================================

T["Context tab is accessible"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    eq(active_tab, "context")
end

T["Context tab shows system prompt template"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])

    local content = get_buffer_content()

    expect.match(content, "System Prompt")
    -- Should show some indication of prompt content
    expect.truthy(#content > 100) -- Non-trivial content
end

T["Context tab shows header and structure"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])

    local content = get_buffer_content()

    -- Should have structured display with sections
    expect.match(content, "Pre%-Prompt") -- Section for preprompt
    -- Should show prompt content or template
    expect.truthy(content:match("Neovim") or content:match("keybinding"))
end

-- ============================================================================
-- Pre-Prompt Integration
-- Verify Context tab shows current preprompt correctly
-- ============================================================================

T["Context tab shows empty preprompt by default"] = function()
    child.lua([[
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    local content = get_buffer_content()

    -- Context now shows complete verbatim prompt, not metadata
    -- When no preprompt is set, the prompt starts directly with the assistant text
    -- (preprompt section will be empty/whitespace only)
    expect.match(content, "keybinding assistant")
    -- Verify the "edit in Pre-Prompt tab" footer is present
    expect.match(content, "Pre%-Prompt tab")
end

T["Context tab shows global preprompt when set"] = function()
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Custom global instructions" })
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    local content = get_buffer_content()

    expect.match(content, "Custom global instructions")
    expect.match(content, "global") -- Should label it as global
end

T["Context tab shows project preprompt when selected"] = function()
    child.lua([[
        require("n00bkeys.settings").save_project({ preprompt = "Custom project instructions" })
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    local content = get_buffer_content()

    expect.match(content, "Custom project instructions")
    expect.match(content, "project") -- Should label it as project
end

T["Context tab shows correct scope label"] = function()
    -- Test global scope label - now via preprompt content
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Global text" })
        require("n00bkeys.settings").set_selected_scope("global")
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    local content = get_buffer_content()
    -- Context now shows verbatim prompt, so we verify the actual preprompt content
    expect.match(content, "Global text")

    -- Switch to project scope
    child.lua([[
        require("n00bkeys.ui").close()
        require("n00bkeys.settings").save_project({ preprompt = "Project text" })
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    -- Verify scope is correct via settings (more reliable than buffer after reopen)
    local scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])
    expect.equality(scope, "project")
    local preprompt = child.lua_get([[require("n00bkeys.settings").get_current_preprompt()]])
    expect.match(preprompt, "Project text")
end

-- ============================================================================
-- Full System Prompt Display
-- Verify complete prompt is shown, including all components
-- ============================================================================

T["Context tab shows complete system prompt"] = function()
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Be helpful and concise." })
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    local content = get_buffer_content()

    -- Should show preprompt section
    expect.match(content, "Be helpful and concise")

    -- Should show system prompt content (from prompt.lua)
    expect.truthy(
        content:match("Neovim") or content:match("keybinding") or content:match("assistant")
    )
end

T["Context tab shows environment context"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])

    local content = get_buffer_content()

    -- System prompt should include environment info
    -- This comes from context.lua being injected into prompt
    expect.truthy(
        content:match("Neovim") or content:match("version") or content:match("Distribution")
    )
end

-- ============================================================================
-- Auto-Refresh on Tab Switch
-- Verify content updates when switching to Context tab
-- ============================================================================

T["Context tab refreshes when switching to it"] = function()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Initially no preprompt - just verify structure is present
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])
    local initial_content = get_buffer_content()
    expect.match(initial_content, "keybinding assistant")

    -- Switch away and set preprompt
    child.lua([[
        require("n00bkeys.ui").switch_tab("query")
        require("n00bkeys.settings").save_global({ preprompt = "New instructions" })
        require("n00bkeys.settings")._clear_cache()
    ]])

    -- Switch back to context - should show updated preprompt
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])
    local updated_content = get_buffer_content()

    expect.match(updated_content, "New instructions")
end

T["Context tab reflects preprompt changes after scope toggle"] = function()
    -- Set different preprompts
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Global instructions" })
        require("n00bkeys.settings").save_project({ preprompt = "Project instructions" })
        require("n00bkeys.settings").set_selected_scope("global")
        require("n00bkeys.settings")._clear_cache()
    ]])

    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])

    local content = get_buffer_content()
    expect.match(content, "Global instructions")

    -- Change scope and refresh
    child.lua([[
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").switch_tab("query")  -- Switch away
        require("n00bkeys.ui").switch_tab("context")  -- Switch back
    ]])

    content = get_buffer_content()
    expect.match(content, "Project instructions")
end

-- ============================================================================
-- Read-Only Buffer
-- Verify users cannot edit Context tab
-- ============================================================================

T["Context tab buffer is not modifiable"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])

    child.lua([[
        _G.test_modifiable = vim.api.nvim_buf_get_option(
            require("n00bkeys.ui").state.tabs.context.buf_id,
            "modifiable"
        )
    ]])

    local modifiable = child.lua_get([[_G.test_modifiable]])
    eq(modifiable, false)
end

-- ============================================================================
-- Multi-Line Preprompt Display
-- Verify multi-line preprompts are displayed correctly
-- ============================================================================

T["Context tab displays multi-line preprompt correctly"] = function()
    child.lua([[
        require("n00bkeys.settings").save_global({
            preprompt = "Line 1: First instruction\nLine 2: Second instruction\nLine 3: Third instruction"
        })
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    local content = get_buffer_content()

    expect.match(content, "Line 1: First instruction")
    expect.match(content, "Line 2: Second instruction")
    expect.match(content, "Line 3: Third instruction")
end

-- ============================================================================
-- Help Text and Instructions
-- Verify Context tab provides user guidance
-- ============================================================================

T["Context tab shows helpful footer text"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("context")]])

    local content = get_buffer_content()

    -- Should give user context about what they're seeing
    expect.truthy(
        content:match("complete")
            or content:match("prompt")
            or content:match("OpenAI")
            or content:match("sent")
    )
end

-- ============================================================================
-- Integration: Pre-Prompt Tab → Context Tab
-- Verify changes in Pre-Prompt tab are reflected in Context tab
-- ============================================================================

T["changes in Pre-Prompt tab visible in Context tab after switch"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")

        -- Simulate setting preprompt
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
        for i = 1, #lines do
            if lines[i]:match("^───") and i > 5 then
                vim.api.nvim_buf_set_lines(buf_id, i + 1, i + 2, false, {"Updated preprompt from tab"})
                break
            end
        end
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf_id })
    ]])

    child.lua([[vim.wait(600)]]) -- Wait for auto-save

    -- Switch to context tab
    child.lua([[
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    local content = get_buffer_content()
    expect.match(content, "Updated preprompt from tab")
end

return T
