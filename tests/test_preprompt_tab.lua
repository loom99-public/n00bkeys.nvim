-- Pre-Prompt Tab Tests
-- These validate the editable Pre-Prompt tab UI with radio buttons and auto-save
-- Tests follow workflow-first approach: verify what users see and can do

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
            -- Define helper functions in child process
            child.lua([[
                _G.test_get_buffer_lines = function()
                    local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
                    return vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
                end

                _G.test_find_editable_area = function()
                    local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
                    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

                    -- Find the first separator after header (line with "───")
                    for i = 1, #lines do
                        if lines[i]:match("^───+") and i > 3 then
                            -- Editable area starts 2 lines after separator (separator + blank line)
                            -- Return value will be used with nvim_buf_set_lines which expects 0-indexed start
                            -- Separator at 1-indexed line i, editable at i+2, so return i+1 for 0-indexed access
                            return i + 1  -- Return 0-indexed line number for editable area
                        end
                    end

                    error("Could not find editable area separator in buffer")
                end
            ]])
        end,
        post_once = child.stop,
    },
})

-- Helper to get buffer lines
local function get_buffer_lines()
    return child.lua_get([[_G.test_get_buffer_lines()]])
end

-- Helper to find editable area start (first line after separator)
-- This makes tests flexible to layout changes
local function find_editable_area()
    return child.lua_get([[_G.test_find_editable_area()]])
end

-- ============================================================================
-- Tab Navigation and Access
-- Verify Pre-Prompt tab exists and can be accessed
-- ============================================================================

T["Pre-Prompt tab exists as 4th tab"] = function()
    child.lua([[require("n00bkeys.ui").open()]])

    local tabs = child.lua_get([[require("n00bkeys.ui").TABS]])

    -- Find preprompt tab
    local preprompt_tab = nil
    for _, tab in ipairs(tabs) do
        if tab.id == "preprompt" then
            preprompt_tab = tab
            break
        end
    end

    expect.truthy(preprompt_tab ~= nil)
    eq(preprompt_tab.order, 4)
    eq(preprompt_tab.label, "Pre-Prompt")
end

T["user can switch to Pre-Prompt tab by pressing 4"] = function()
    child.lua([[require("n00bkeys.ui").open()]])

    -- Press "4" to switch to preprompt tab
    child.lua([[require("n00bkeys.ui").switch_tab_by_index(4)]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    eq(active_tab, "preprompt")
end

T["Pre-Prompt tab can be accessed via switch_tab()"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("preprompt")]])

    local active_tab = child.lua_get([[require("n00bkeys.ui").get_active_tab()]])
    eq(active_tab, "preprompt")
end

-- ============================================================================
-- Buffer Layout and Rendering
-- Verify UI renders correctly with all expected elements
-- ============================================================================

T["Pre-Prompt tab renders header and footer"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("preprompt")]])

    local lines = get_buffer_lines()

    expect.match(lines[1], "Pre%-Prompt Configuration")
    expect.match(table.concat(lines, "\n"), "Edit your pre%-prompt")
end

T["Pre-Prompt tab shows instructions"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("preprompt")]])

    local lines = get_buffer_lines()
    local content = table.concat(lines, "\n")

    expect.match(content, "toggle scope")
    expect.match(content, "Changes save automatically")
end

-- ============================================================================
-- Radio Button UI - Visual Representation
-- Verify radio buttons render correctly based on selected scope
-- ============================================================================

T["radio buttons show Global selected by default"] = function()
    child.lua([[require("n00bkeys.ui").open()]])
    child.lua([[require("n00bkeys.ui").switch_tab("preprompt")]])

    local lines = get_buffer_lines()

    -- Find the radio button line
    local radio_line = nil
    for _, line in ipairs(lines) do
        if line:match("Scope:") then
            radio_line = line
            break
        end
    end

    expect.truthy(radio_line ~= nil)
    expect.match(radio_line, "%[X%].*Global")
    expect.match(radio_line, "%[ %].*Project")
end

T["radio buttons show Project selected after toggle"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    -- Toggle scope to project
    child.lua([[require("n00bkeys.ui").toggle_preprompt_scope()]])

    local lines = get_buffer_lines()

    -- Find radio line
    local radio_line = nil
    for _, line in ipairs(lines) do
        if line:match("Scope:") then
            radio_line = line
            break
        end
    end

    expect.match(radio_line, "%[ %].*Global")
    expect.match(radio_line, "%[X%].*Project")
end

-- ============================================================================
-- Scope Toggle Functionality
-- Verify <C-g> toggles between global and project
-- ============================================================================

T["toggle_preprompt_scope() switches from global to project"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    local initial_scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])
    eq(initial_scope, "global")

    child.lua([[require("n00bkeys.ui").toggle_preprompt_scope()]])

    local new_scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])
    eq(new_scope, "project")
end

T["toggle_preprompt_scope() switches from project to global"] = function()
    child.lua([[
        require("n00bkeys.settings").set_selected_scope("project")
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    child.lua([[require("n00bkeys.ui").toggle_preprompt_scope()]])

    local new_scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])
    eq(new_scope, "global")
end

T["scope toggle persists across sessions"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
        require("n00bkeys.ui").toggle_preprompt_scope()  -- Set to project
    ]])

    -- Close and reopen (simulates new session)
    child.lua([[
        require("n00bkeys.ui").close()
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    local scope = child.lua_get([[require("n00bkeys.settings").get_selected_scope()]])
    eq(scope, "project")
end

-- ============================================================================
-- Content Loading Based on Scope
-- Verify correct preprompt is loaded when scope changes
-- ============================================================================

T["switching scope loads different preprompt content"] = function()
    -- Set different preprompts for each scope
    child.lua([[
        require("n00bkeys.settings").save_global({ preprompt = "Global instructions" })
        require("n00bkeys.settings").save_project({ preprompt = "Project instructions" })
        require("n00bkeys.settings")._clear_cache()
    ]])

    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    local lines = get_buffer_lines()
    expect.match(table.concat(lines, "\n"), "Global instructions")

    -- Toggle to project
    child.lua([[require("n00bkeys.ui").toggle_preprompt_scope()]])

    lines = get_buffer_lines()
    expect.match(table.concat(lines, "\n"), "Project instructions")
end

T["empty preprompt shows placeholder text"] = function()
    child.lua([[
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    local lines = get_buffer_lines()
    local content = table.concat(lines, "\n")

    -- Should show placeholder or help text when empty
    expect.truthy(
        content:match("Type")
            or content:match("custom instructions")
            or content:match("No pre%-prompt")
    )
end

-- ============================================================================
-- Buffer Modifiability
-- Verify users can edit the preprompt text area
-- ============================================================================

T["preprompt buffer is modifiable"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    child.lua([[
        _G.test_modifiable = vim.api.nvim_buf_get_option(
            require("n00bkeys.ui").state.tabs.preprompt.buf_id,
            "modifiable"
        )
    ]])

    local modifiable = child.lua_get([[_G.test_modifiable]])
    eq(modifiable, true)
end

T["user can type text in preprompt buffer"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    -- Find editable area dynamically
    local editable_line = find_editable_area()

    -- Simulate typing in the buffer (move to editable area and insert text)
    child.lua(string.format(
        [[
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        vim.api.nvim_buf_set_lines(buf_id, %d, %d, false, {"Test preprompt text"})
    ]],
        editable_line,
        editable_line + 1
    ))

    local lines = get_buffer_lines()
    expect.match(table.concat(lines, "\n"), "Test preprompt text")
end

-- ============================================================================
-- Text Extraction
-- Verify preprompt text can be extracted from buffer correctly
-- ============================================================================

T["extract_preprompt_text() extracts user text from buffer"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")

        -- Manually set buffer content to test extraction
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        local lines = {
            "╭─ Pre-Prompt Configuration ─╮",
            "",
            "Scope: [X] Global   [ ] Project-specific",
            "",
            "Edit your pre-prompt below:",
            "───────────────────────────────────",
            "",
            "This is my custom preprompt",
            "It has multiple lines",
            "",
            "───────────────────────────────────",
            "",
            "Press <C-g> to toggle scope",
            "",
            "╰─────────────────────────────────╯"
        }
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    ]])

    local extracted = child.lua_get([[require("n00bkeys.ui").extract_preprompt_text(
        require("n00bkeys.ui").state.tabs.preprompt.buf_id
    )]])

    -- Should extract only the editable content
    expect.match(extracted, "This is my custom preprompt")
    expect.match(extracted, "It has multiple lines")
    -- Should NOT include UI chrome
    expect.no_match(extracted, "╭─")
    expect.no_match(extracted, "Press <C%-g>")
end

T["extract_preprompt_text() ignores placeholder text"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")

        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        local lines = {
            "╭─ Pre-Prompt Configuration ─╮",
            "",
            "Scope: [X] Global   [ ] Project-specific",
            "",
            "Edit your pre-prompt below:",
            "───────────────────────────────────",
            "",
            "(Type your custom instructions here)",
            "",
            "───────────────────────────────────",
        }
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    ]])

    local extracted = child.lua_get([[require("n00bkeys.ui").extract_preprompt_text(
        require("n00bkeys.ui").state.tabs.preprompt.buf_id
    )]])

    -- Should return empty or minimal text (placeholder ignored)
    local trimmed = extracted:gsub("^%s+", ""):gsub("%s+$", "")
    eq(#trimmed, 0)
end

-- ============================================================================
-- Auto-Save Functionality
-- Verify text changes are persisted automatically
-- ============================================================================

T["text changes trigger auto-save"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    -- Find editable area dynamically
    local editable_line = find_editable_area()

    -- Trigger TextChanged autocmd
    child.lua(string.format(
        [[
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        vim.api.nvim_buf_set_lines(buf_id, %d, %d, false, {"Auto-saved preprompt text"})
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf_id })
    ]],
        editable_line,
        editable_line + 1
    ))

    -- Wait for debounce timer (1000ms to be safe - any reasonable debounce should be < 1s)
    child.lua([[vim.wait(1000)]])

    -- Verify saved
    child.lua([[require("n00bkeys.settings")._clear_cache()]])
    local saved_preprompt = child.lua_get([[require("n00bkeys.settings").get_current_preprompt()]])

    expect.match(saved_preprompt, "Auto%-saved preprompt text")
end

T["auto-save persists across window close and reopen"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    local editable_line = find_editable_area()

    -- Set text
    child.lua(string.format(
        [[
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        vim.api.nvim_buf_set_lines(buf_id, %d, %d, false, {"Persistent preprompt"})
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf_id })
    ]],
        editable_line,
        editable_line + 1
    ))

    child.lua([[vim.wait(1000)]]) -- Wait for save

    -- Close and reopen
    child.lua([[
        require("n00bkeys.ui").close()
        require("n00bkeys.settings")._clear_cache()
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    -- Verify preprompt was persisted by checking settings directly (more reliable than buffer)
    local saved_preprompt = child.lua_get([[require("n00bkeys.settings").get_current_preprompt()]])
    expect.match(saved_preprompt, "Persistent preprompt")
end

-- ============================================================================
-- Multi-Line Preprompt Support
-- Verify multi-line text is handled correctly
-- ============================================================================

T["multi-line preprompt text is preserved"] = function()
    child.lua([[
        require("n00bkeys.settings").save_global({
            preprompt = "Line 1\nLine 2\nLine 3"
        })
        require("n00bkeys.settings")._clear_cache()

        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    local lines = get_buffer_lines()
    local content = table.concat(lines, "\n")

    expect.match(content, "Line 1")
    expect.match(content, "Line 2")
    expect.match(content, "Line 3")
end

-- ============================================================================
-- Integration: Scope + Content + Save
-- End-to-end workflow tests
-- ============================================================================

T["complete workflow: toggle scope, edit text, verify saved"] = function()
    child.lua([[
        require("n00bkeys.ui").open()
        require("n00bkeys.ui").switch_tab("preprompt")
    ]])

    -- Get editable line dynamically
    local editable_line = find_editable_area()

    -- Start with global
    child.lua(string.format(
        [[
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        vim.api.nvim_buf_set_lines(buf_id, %d, %d, false, {"Global preprompt text"})
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf_id })
    ]],
        editable_line,
        editable_line + 1
    ))

    child.lua([[vim.wait(1000)]])

    -- Toggle to project
    child.lua([[require("n00bkeys.ui").toggle_preprompt_scope()]])

    -- Get new editable line after toggle (buffer content changed)
    local editable_line2 = find_editable_area()

    child.lua(string.format(
        [[
        local buf_id = require("n00bkeys.ui").state.tabs.preprompt.buf_id
        vim.api.nvim_buf_set_lines(buf_id, %d, %d, false, {"Project preprompt text"})
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf_id })
    ]],
        editable_line2,
        editable_line2 + 1
    ))

    child.lua([[vim.wait(1000)]])

    -- Verify both saved correctly
    child.lua([[require("n00bkeys.settings")._clear_cache()]])

    local global_preprompt = child.lua_get([[require("n00bkeys.settings").load_global().preprompt]])
    local project_preprompt =
        child.lua_get([[require("n00bkeys.settings").load_project().preprompt]])

    expect.match(global_preprompt, "Global preprompt text")
    expect.match(project_preprompt, "Project preprompt text")
end

return T
