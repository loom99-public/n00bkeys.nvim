-- Pre-Prompt Integration Tests
-- End-to-end tests verifying preprompts are actually included in OpenAI API calls
-- These test the complete workflow from user setting preprompt to API request

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
                require("n00bkeys.settings").clear_cache()
            ]])
            -- Define helper function in child process for JSON parsing
            child.lua([[
                _G.test_parse_last_request = function()
                    local body = _G.last_http_request.body
                    return vim.json.decode(body)
                end
            ]])
        end,
        post_once = child.stop,
    },
})

-- Mock HTTP to capture request body
local function setup_mock_http_with_capture()
    child.lua([[
        vim.env.OPENAI_API_KEY = "test-key"
        _G.last_http_request = nil

        local http = require("n00bkeys.http")
        http.post = function(url, headers, body, callback)
            -- Encode body to JSON to simulate real http.post behavior
            local body_json = vim.json.encode(body)

            -- Capture request for verification
            _G.last_http_request = {
                url = url,
                headers = headers,
                body = body_json,  -- Store as JSON string
            }

            vim.schedule(function()
                callback(nil, {
                    choices = {
                        { message = { content = "Test response" } }
                    }
                })
            end)
        end
    ]])
end

local function wait_for_completion()
    child.lua([[vim.wait(1000, function()
        return not require("n00bkeys.ui").state.tabs.query.is_loading
    end)]])
end

-- ============================================================================
-- Prompt Template Tests
-- Verify prompt.build_system_prompt() includes preprompt
-- ============================================================================

T["build_system_prompt() includes preprompt when set"] = function()
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "You are an expert Vim user." })
        require("n00bkeys.settings").clear_cache()
    ]])

    local prompt = child.lua_get([[require("n00bkeys.prompt").build_system_prompt()]])

    expect.match(prompt, "You are an expert Vim user%.")
end

T["build_system_prompt() works with empty preprompt"] = function()
    child.lua([[require("n00bkeys.settings").clear_cache()]])

    local prompt = child.lua_get([[require("n00bkeys.prompt").build_system_prompt()]])

    -- Should not contain {preprompt} placeholder
    expect.no_match(prompt, "{preprompt}")

    -- Should still contain context
    expect.truthy(prompt:match("Neovim") or prompt:match("keybinding"))
end

T["build_system_prompt() uses project preprompt when selected"] = function()
    child.lua([[
        require("n00bkeys.settings").save_project({ preprompt = "Project-specific instructions" })
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.settings").clear_cache()
    ]])

    local prompt = child.lua_get([[require("n00bkeys.prompt").build_system_prompt()]])

    expect.match(prompt, "Project%-specific instructions")
end

T["preprompt appears before context in prompt"] = function()
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "PREPROMPT_MARKER" })
        require("n00bkeys.settings").clear_cache()
    ]])

    local prompt = child.lua_get([[require("n00bkeys.prompt").build_system_prompt()]])

    local preprompt_pos = prompt:find("PREPROMPT_MARKER")
    local context_pos = prompt:find("Neovim") or prompt:find("version")

    expect.truthy(preprompt_pos ~= nil)
    expect.truthy(context_pos ~= nil)
    expect.truthy(preprompt_pos < context_pos)
end

-- ============================================================================
-- API Request Integration
-- Verify preprompts are actually sent to OpenAI API
-- ANTI-GAMING: Parse JSON structure, verify preprompt in system message
-- ============================================================================

T["query includes global preprompt in API request"] = function()
    setup_mock_http_with_capture()

    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Be extremely concise." })
        require("n00bkeys.settings").clear_cache()

        require("n00bkeys.ui").open()
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"How do I save?"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON structure and verify preprompt in system message
    local parsed = child.lua_get([[_G.test_parse_last_request()]])

    expect.truthy(parsed.messages ~= nil)
    expect.truthy(#parsed.messages >= 1)

    local system_message = parsed.messages[1]
    eq(system_message.role, "system")
    expect.match(system_message.content, "Be extremely concise")
end

T["query includes project preprompt in API request when scope is project"] = function()
    setup_mock_http_with_capture()

    child.lua([[
        require("n00bkeys.settings").save_project({ preprompt = "Focus on Python development." })
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.settings").clear_cache()

        require("n00bkeys.ui").open()
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"How do I debug?"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON and verify in correct location
    local parsed = child.lua_get([[_G.test_parse_last_request()]])

    expect.truthy(parsed.messages ~= nil)
    local system_message = parsed.messages[1]
    eq(system_message.role, "system")
    expect.match(system_message.content, "Focus on Python development")
end

T["query without preprompt still works"] = function()
    setup_mock_http_with_capture()

    child.lua([[
        require("n00bkeys.settings").clear_cache()

        require("n00bkeys.ui").open()
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"How do I quit?"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON structure
    local parsed = child.lua_get([[_G.test_parse_last_request()]])

    expect.truthy(parsed.messages ~= nil)

    -- System message should not contain placeholder
    local system_message = parsed.messages[1]
    expect.no_match(system_message.content, "{preprompt}")

    -- Should still contain context
    expect.truthy(
        system_message.content:match("Neovim") or system_message.content:match("keybinding")
    )

    -- User message should contain query
    expect.truthy(#parsed.messages >= 2)
    local user_message = parsed.messages[2]
    eq(user_message.role, "user")
    expect.match(user_message.content, "How do I quit")
end

T["multi-line preprompt is sent correctly"] = function()
    setup_mock_http_with_capture()

    child.lua([[
        require("n00bkeys.settings").save_global({
            preprompt = "Line 1: Be helpful.\nLine 2: Be concise.\nLine 3: Be accurate."
        })
        require("n00bkeys.settings").clear_cache()

        require("n00bkeys.ui").open()
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"Test query"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON and verify all lines present
    local parsed = child.lua_get([[_G.test_parse_last_request()]])

    local system_content = parsed.messages[1].content
    expect.match(system_content, "Line 1: Be helpful")
    expect.match(system_content, "Line 2: Be concise")
    expect.match(system_content, "Line 3: Be accurate")
end

-- ============================================================================
-- End-to-End User Workflows
-- Complete workflows from setting preprompt to getting response
-- ============================================================================

T["Workflow: set global preprompt -> submit query -> verify in request"] = function()
    setup_mock_http_with_capture()

    -- User opens plugin and sets preprompt
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")

        -- Simulate typing preprompt in editable area
        -- Find separator and set text 2 lines after it (separator + blank + content line)
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
        for i = 1, #lines do
            if lines[i]:match("^───") and i > 5 then
                -- i is 1-indexed separator line
                -- Want to set 1-indexed line i+2 (content line)
                -- nvim_buf_set_lines uses 0-indexed params, so use i+1, i+2
                vim.api.nvim_buf_set_lines(buf_id, i + 1, i + 2, false, {"Always suggest modal editing."})
                break
            end
        end
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf_id })
    ]])

    child.lua([[vim.wait(600)]]) -- Wait for auto-save

    -- User switches to query tab and submits
    child.lua([[
        require("n00bkeys.settings").clear_cache()
        require("n00bkeys.ui").switch_tab("query")
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"How do I copy text?"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON and verify preprompt in system message
    local parsed = child.lua_get([[_G.test_parse_last_request()]])

    local system_content = parsed.messages[1].content
    expect.match(system_content, "Always suggest modal editing")
end

T["Workflow: toggle scope -> verify correct preprompt in request"] = function()
    setup_mock_http_with_capture()

    -- Set different preprompts
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Global: Use standard Vim" })
        require("n00bkeys.settings").save_project({ preprompt = "Project: Use Neovim features" })
        require("n00bkeys.settings").clear_cache()

        require("n00bkeys.ui").open()
    ]])

    -- Submit with global scope
    child.lua([[
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"Test query 1"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON
    child.lua([[_G.test_global_parsed = _G.test_parse_last_request()]])
    local global_parsed = child.lua_get([[_G.test_global_parsed]])
    expect.match(global_parsed.messages[1].content, "Global: Use standard Vim")

    -- Switch to project scope
    child.lua([[
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.settings").clear_cache()
    ]])

    -- Submit new query
    setup_mock_http_with_capture() -- Reset capture
    child.lua([[
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"Test query 2"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON
    child.lua([[_G.test_project_parsed = _G.test_parse_last_request()]])
    local project_parsed = child.lua_get([[_G.test_project_parsed]])
    expect.match(project_parsed.messages[1].content, "Project: Use Neovim features")
end

T["Workflow: update preprompt -> verify reflected in next query"] = function()
    setup_mock_http_with_capture()

    -- Initial query
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Initial instructions" })
        require("n00bkeys.settings").clear_cache()

        require("n00bkeys.ui").open()
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"Query 1"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse first request
    child.lua([[_G.test_first_parsed = _G.test_parse_last_request()]])
    local first_parsed = child.lua_get([[_G.test_first_parsed]])
    expect.match(first_parsed.messages[1].content, "Initial instructions")

    -- Update preprompt
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Updated instructions" })
        require("n00bkeys.settings").clear_cache()
    ]])

    -- New query
    setup_mock_http_with_capture()
    child.lua([[
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"Query 2"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse second request
    child.lua([[_G.test_second_parsed = _G.test_parse_last_request()]])
    local second_parsed = child.lua_get([[_G.test_second_parsed]])
    expect.match(second_parsed.messages[1].content, "Updated instructions")
end

-- ============================================================================
-- Preprompt with Special Characters
-- Verify special characters are properly escaped/handled
-- ============================================================================

T["preprompt with quotes is handled correctly"] = function()
    setup_mock_http_with_capture()

    child.lua([[
        require("n00bkeys.settings").save_global({
            preprompt = 'Always use "visual mode" and \'normal mode\' correctly.'
        })
        require("n00bkeys.settings").clear_cache()

        require("n00bkeys.ui").open()
        local buf_id = require("n00bkeys.ui").state.input_buf_id
        vim.api.nvim_buf_set_lines(buf_id, 0, 1, false, {"Test"})
        require("n00bkeys.ui").submit_query()
    ]])

    wait_for_completion()

    -- ANTI-GAMING: Parse JSON
    local parsed = child.lua_get([[_G.test_parse_last_request()]])

    -- Should include the quotes
    expect.match(parsed.messages[1].content, "visual mode")
    expect.match(parsed.messages[1].content, "normal mode")
end

-- ============================================================================
-- Context Tab Consistency
-- Verify Context tab shows the same prompt that's sent to API
-- ============================================================================

T["Context tab shows same prompt that is sent to OpenAI"] = function()
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Consistency test preprompt" })
        require("n00bkeys.settings").clear_cache()
    ]])

    -- Get prompt from Context tab
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("context")
    ]])

    child.lua([[
        _G.test_context_content = (function()
            local buf_id = require("n00bkeys.ui").state.tabs.context.buf_id
            local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
            return table.concat(lines, "\n")
        end)()
    ]])

    local context_content = child.lua_get([[_G.test_context_content]])

    -- Get prompt that would be sent to API
    local api_prompt = child.lua_get([[require("n00bkeys.prompt").build_system_prompt()]])

    -- Context tab should show the preprompt
    expect.match(context_content, "Consistency test preprompt")

    -- The preprompt in Context should match what's in the actual system prompt
    expect.truthy(api_prompt:find("Consistency test preprompt") ~= nil)
end

return T
