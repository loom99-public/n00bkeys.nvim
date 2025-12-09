-- UI module for n00bkeys sidebar
local log = require("n00bkeys.util.log")
local M = {}

-- Track if we're already closing to prevent recursive autocmd issues
local _closing = false

-- Helper to get sidebar width from config
local function get_sidebar_width()
    local config = require("n00bkeys.config")
    return config.options.sidebar_width or 50
end

-- Footer keybinding hints (shown in readonly footer buffer)
local FOOTER_TEXT = " <CR> Send | <C-n> New | <Tab> Tab | <?> Help | q Close "

-- Highlight group names
local HL_USER_BG = "N00bkeysUserMsg"
local HL_AI_BG = "N00bkeysAiMsg"
local HL_ERROR_BG = "N00bkeysErrorMsg"

--- Setup highlight groups for chat messages
--- Uses subtle background colors: pale blue for user, pale green for AI, pale red for errors
--- User messages have dimmer text to visually distinguish from AI responses
local function setup_highlights()
    -- Pale blue background + dimmed text for user messages
    vim.api.nvim_set_hl(0, HL_USER_BG, {
        bg = "#1a2a3a", -- Subtle dark blue
        fg = "#8899aa", -- Dimmed grey-blue text
        default = true,
    })
    -- Pale green background for AI messages (normal text brightness)
    vim.api.nvim_set_hl(0, HL_AI_BG, {
        bg = "#1a2a1a", -- Subtle dark green
        default = true,
    })
    -- Pale red background for error messages
    vim.api.nvim_set_hl(0, HL_ERROR_BG, {
        bg = "#3a1a1a", -- Subtle dark red
        default = true,
    })
end

-- Tab definitions
local TABS = {
    { id = "query", label = "Query", icon = "?", order = 1 },
    { id = "history", label = "History", icon = "H", order = 2 },
    { id = "context", label = "Context", icon = "C", order = 3 },
    { id = "preprompt", label = "Pre-Prompt", icon = "P", order = 4 },
    { id = "settings", label = "Settings", icon = "S", order = 5 },
}

-- Export TABS constant for tests
M.TABS = TABS

-- Helper to get tab metadata by ID
local function get_tab_metadata(tab_id)
    for _, tab in ipairs(TABS) do
        if tab.id == tab_id then
            return tab
        end
    end
    return nil
end

-- Module state
M.state = {
    -- Sidebar layout: 3 stacked windows in a vertical split
    -- [conversation_win] - readonly, shows chat history
    -- [input_win]        - editable, single line for user input
    -- [footer_win]       - readonly, shows keybindings

    sidebar_win_id = nil, -- Main sidebar window (conversation display)
    input_win_id = nil, -- Input area window
    footer_win_id = nil, -- Footer window (keybindings)

    conversation_buf_id = nil, -- Buffer for conversation display (readonly)
    input_buf_id = nil, -- Buffer for user input (editable)
    footer_buf_id = nil, -- Buffer for footer (readonly)

    -- Legacy support for tabs (history, context, etc still use old system)
    win_id = nil, -- Alias for sidebar_win_id for backwards compat
    active_tab = "query", -- Current tab: "query" | "history" | "context" | "preprompt" | "settings"

    -- Per-tab state storage
    tabs = {
        query = { buf_id = nil, is_loading = false, last_error = nil, last_response = nil },
        history = { buf_id = nil, is_loading = false },
        context = { buf_id = nil, is_loading = false },
        preprompt = { buf_id = nil, is_loading = false },
        settings = { buf_id = nil, is_loading = false },
    },

    -- Conversation tracking for multi-turn chat
    active_conversation_id = nil, -- Current conversation ID
    current_messages = {}, -- Messages in active conversation [{role, content, timestamp}]

    -- Request cancellation tracking
    pending_request_cancelled = false, -- Flag to ignore response when cancelled
    last_submitted_prompt = nil, -- Store prompt for restoring on cancel
}

-- Timer for auto-save debouncing
M._debounce_timer = nil

--- Start a new conversation
--- Saves current conversation if exists, then initializes fresh state
function M.start_new_conversation()
    log.debug("ui", "Starting new conversation")

    -- Save current conversation if it exists
    if M.state.active_conversation_id and #M.state.current_messages > 0 then
        M.save_conversation()
    end

    -- Clear session tracking (user explicitly wants a fresh conversation)
    vim.g.n00bkeys_last_conversation_id = nil

    -- Generate new conversation ID
    M.state.active_conversation_id = "conv_" .. os.time()
    M.state.current_messages = {}

    -- Clear the UI
    M.clear()

    log.debug("ui", "New conversation started: %s", M.state.active_conversation_id)
end

--- Add a user message to the current conversation
--- @param content string Message content
function M.add_user_message(content)
    local message = {
        role = "user",
        content = content,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    table.insert(M.state.current_messages, message)
    log.debug("ui", "Added user message to conversation")
end

--- Add an assistant message to the current conversation
--- @param content string Message content
function M.add_assistant_message(content)
    local message = {
        role = "assistant",
        content = content,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    table.insert(M.state.current_messages, message)
    log.debug("ui", "Added assistant message to conversation")
end

--- Save the current conversation to history
function M.save_conversation()
    if not M.state.active_conversation_id or #M.state.current_messages == 0 then
        log.debug("ui", "No conversation to save")
        return
    end

    local config = require("n00bkeys.config")
    if not config.options.history_enabled then
        log.debug("ui", "History disabled, not saving conversation")
        return
    end

    local history = require("n00bkeys.history")

    -- Create conversation object
    local conversation = {
        id = M.state.active_conversation_id,
        messages = M.state.current_messages,
        -- created_at and updated_at will be set by history.save_conversation
        -- summary will be generated by history module
    }

    history.save_conversation(conversation)
    log.debug("ui", "Saved conversation: %s", M.state.active_conversation_id)
end

--- Load a conversation from history and set it as active
--- @param conv_id string Conversation ID to load
function M.load_conversation(conv_id)
    local history = require("n00bkeys.history")
    local conversation = history.get_conversation(conv_id)

    if not conversation then
        log.error("ui", "Conversation not found: %s", conv_id)
        return false
    end

    -- Set as active conversation
    M.state.active_conversation_id = conversation.id
    M.state.current_messages = conversation.messages or {}

    -- Track this as the last active conversation in this session
    vim.g.n00bkeys_last_conversation_id = conversation.id

    -- Render the conversation in chat UI (actually write to buffer)
    M.refresh_conversation_buffer()

    log.debug("ui", "Loaded conversation: %s", conv_id)
    return true
end

--- Get the currently active tab ID
--- @return string Active tab ID ("query" | "history" | "context" | "preprompt" | "settings")
function M.get_active_tab()
    return M.state.active_tab or "query"
end

--- Get the buffer ID of the active tab
--- @return number|nil Buffer ID, or nil if not initialized
function M.get_active_buffer()
    local tab_id = M.get_active_tab()
    return M.state.tabs[tab_id] and M.state.tabs[tab_id].buf_id
end

--- Get state for a specific tab
--- @param tab_id string Tab ID
--- @return table|nil Tab state object, or nil if invalid
function M.get_tab_state(tab_id)
    return M.state.tabs[tab_id]
end

--- Update state for a specific tab
--- @param tab_id string Tab ID
--- @param updates table Key-value pairs to update in tab state
function M.update_tab_state(tab_id, updates)
    local tab_state = M.state.tabs[tab_id]
    if tab_state then
        for key, value in pairs(updates) do
            if value == vim.NIL then
                -- vim.NIL is a sentinel for explicitly setting to nil
                tab_state[key] = nil
            else
                tab_state[key] = value
            end
        end
    end
end

--- Check if a tab ID is valid
--- @param tab_id string Tab ID to validate
--- @return boolean True if valid
function M.is_valid_tab(tab_id)
    return get_tab_metadata(tab_id) ~= nil
end

--- Render the tab bar for window title/winbar
--- Uses compact format to fit in sidebar width: [1*] 2 3 4 5
--- @return string Formatted tab bar string
function M.render_tab_bar()
    local parts = {}
    local active_tab = M.get_active_tab()
    local active_label = ""

    for _, tab in ipairs(TABS) do
        local is_active = (tab.id == active_tab)
        if is_active then
            -- Active tab shows [N*]
            table.insert(parts, string.format("[%d*]", tab.order))
            active_label = tab.label
        else
            -- Inactive tabs just show number
            table.insert(parts, tostring(tab.order))
        end
    end

    -- Format: "[1*] 2 3 4 5 | Query" - shows active tab name at end
    return table.concat(parts, " ") .. " | " .. active_label
end

--- Update the winbar (header) to show current tab state
local function update_winbar()
    if not M.state.sidebar_win_id or not vim.api.nvim_win_is_valid(M.state.sidebar_win_id) then
        return
    end
    local tab_bar = M.render_tab_bar()
    vim.wo[M.state.sidebar_win_id].winbar = " n00bkeys " .. tab_bar
end

--- Render the conversation buffer (readonly, no input area)
--- Shows conversation messages with [USER] and [AI] labels
--- @return table lines Lines of content
--- @return table line_roles Array of {start_line, end_line, role} for highlighting
function M.render_chat_buffer()
    local lines = {}
    local line_roles = {} -- Track which lines belong to which role for highlighting

    -- If we have messages, show them in chat format
    if #M.state.current_messages > 0 then
        for i, msg in ipairs(M.state.current_messages) do
            local start_line = #lines -- 0-indexed line number

            -- Add role label
            local label = "[AI]"
            if msg.role == "user" then
                label = "[USER]"
            elseif msg.role == "error" then
                label = "[ERROR]"
            end

            -- Split message content on newlines - nvim_buf_set_lines requires each line separate
            local content_lines = vim.split(msg.content, "\n", { plain = true })

            -- First line gets the label
            table.insert(lines, label .. " " .. content_lines[1])

            -- Remaining lines get indented (if any)
            for j = 2, #content_lines do
                table.insert(lines, "      " .. content_lines[j])
            end

            local end_line = #lines - 1 -- 0-indexed, inclusive

            -- Track role for this block of lines
            table.insert(line_roles, {
                start_line = start_line,
                end_line = end_line,
                role = msg.role,
            })

            -- Add blank line separator between messages
            if i < #M.state.current_messages then
                table.insert(lines, "")
            end
        end
    else
        -- Empty conversation - show minimal prompt
        table.insert(lines, "")
    end

    return lines, line_roles
end

--- Refresh the conversation buffer with current messages
--- Updates the readonly conversation display and applies syntax highlighting
function M.refresh_conversation_buffer()
    local buf_id = M.state.conversation_buf_id
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end

    local chat_lines, line_roles = M.render_chat_buffer()

    -- Make temporarily modifiable to update
    vim.bo[buf_id].modifiable = true
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, chat_lines)
    vim.bo[buf_id].modifiable = false

    -- Clear existing highlights
    vim.api.nvim_buf_clear_namespace(buf_id, -1, 0, -1)

    -- Apply background highlights for each message block
    for _, block in ipairs(line_roles) do
        local hl_group = HL_AI_BG
        if block.role == "user" then
            hl_group = HL_USER_BG
        elseif block.role == "error" then
            hl_group = HL_ERROR_BG
        end
        for line = block.start_line, block.end_line do
            -- Highlight entire line with background color
            vim.api.nvim_buf_add_highlight(buf_id, -1, hl_group, line, 0, -1)
        end
    end

    -- Scroll to bottom of conversation
    if M.state.sidebar_win_id and vim.api.nvim_win_is_valid(M.state.sidebar_win_id) then
        local line_count = vim.api.nvim_buf_line_count(buf_id)
        vim.api.nvim_win_set_cursor(M.state.sidebar_win_id, { line_count, 0 })
    end
end

--- Render the pre-prompt buffer content
--- @return table Lines of content
function M.render_preprompt_buffer()
    local settings = require("n00bkeys.settings")

    -- Get current scope and preprompt
    local scope = settings.get_selected_scope()
    local preprompt = settings.get_current_preprompt()

    -- Build radio buttons
    local global_radio = scope == "global" and "[X]" or "[ ]"
    local project_radio = scope == "project" and "[X]" or "[ ]"

    local lines = {
        "╭─ Pre-Prompt Configuration ─╮",
        "",
        string.format("Scope: %s Global   %s Project-specific", global_radio, project_radio),
        "",
        "Edit your pre-prompt below:",
        "───────────────────────────────────",
        "",
    }

    -- Add preprompt content or placeholder
    if preprompt and preprompt ~= "" then
        -- Split multi-line preprompt using vim.split to handle empty lines
        local preprompt_lines = vim.split(preprompt, "\n", { plain = true })
        for _, line in ipairs(preprompt_lines) do
            table.insert(lines, line)
        end
    else
        table.insert(lines, "(Type your custom instructions here)")
    end

    -- Add footer
    table.insert(lines, "")
    table.insert(
        lines,
        "───────────────────────────────────"
    )
    table.insert(lines, "")
    table.insert(lines, "Press <C-g> to toggle scope")
    table.insert(lines, "Changes save automatically")
    table.insert(lines, "")
    table.insert(
        lines,
        "╰─────────────────────────────────╯"
    )

    return lines
end

--- Extract preprompt text from buffer (everything after separator, before footer)
--- @param buf_id number Buffer ID
--- @return string Extracted text
function M.extract_preprompt_text(buf_id)
    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

    -- Find first separator (editable area starts after this)
    local separator_idx = nil
    for i, line in ipairs(lines) do
        if line:match("^───+") and i > 3 then
            separator_idx = i
            break
        end
    end

    if not separator_idx then
        return ""
    end

    -- Find second separator (footer starts here)
    local footer_idx = nil
    for i = separator_idx + 1, #lines do
        if lines[i]:match("^───+") then
            footer_idx = i
            break
        end
    end

    -- Extract text between separators
    local text_lines = {}
    local start_line = separator_idx + 2 -- Skip separator and blank line
    local end_line = footer_idx and (footer_idx - 1) or #lines

    for i = start_line, end_line do
        if lines[i] then
            table.insert(text_lines, lines[i])
        end
    end

    local text = table.concat(text_lines, "\n")

    -- Trim trailing whitespace
    text = text:gsub("%s+$", "")

    -- Filter out placeholder text
    if text:match("^%s*%(Type your custom instructions here%)%s*$") then
        return ""
    end

    return text
end

--- Refresh preprompt buffer after scope change
function M.refresh_preprompt_buffer()
    local buf_id = M.get_active_buffer()
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end

    -- Temporarily make buffer modifiable
    vim.bo[buf_id].modifiable = true

    -- Render new content
    local content = M.render_preprompt_buffer()
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)

    -- Keep buffer modifiable for editing
    vim.bo[buf_id].modifiable = true
end

--- Toggle preprompt scope between global and project
function M.toggle_preprompt_scope()
    local settings = require("n00bkeys.settings")
    local current = settings.get_selected_scope()
    local new_scope = current == "global" and "project" or "global"
    settings.set_selected_scope(new_scope)

    -- Refresh buffer to show new scope's content
    M.refresh_preprompt_buffer()
end

--- Setup auto-save for preprompt buffer
--- @param buf_id number Buffer ID
local function setup_preprompt_autosave(buf_id)
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf_id,
        callback = function()
            -- Debounce - use timer to avoid saving on every keystroke
            if M._debounce_timer then
                M._debounce_timer:stop()
            end
            M._debounce_timer = vim.defer_fn(function()
                local text = M.extract_preprompt_text(buf_id)
                local settings = require("n00bkeys.settings")
                local scope = settings.get_selected_scope()
                if scope == "global" then
                    settings.save_global({ preprompt = text })
                else
                    settings.save_project({ preprompt = text })
                end
            end, 500) -- 500ms debounce
        end,
    })
end

--- Render context preview showing the complete system prompt
--- @return table Lines for context buffer

--- Render the settings buffer content
--- @return table Lines of content
function M.render_settings_buffer()
    local settings = require("n00bkeys.settings")

    -- Get current values
    local scope = settings.get_selected_scope()
    local api_key = settings.get_current_api_key()
    local debug = settings.get_current_debug_mode()

    -- Build radio buttons for scope
    local global_radio = scope == "global" and "[X]" or "[ ]"
    local project_radio = scope == "project" and "[X]" or "[ ]"

    -- Mask API key for display
    local api_key_display
    if api_key ~= "" then
        -- Show masked asterisks (fixed length for security)
        api_key_display = string.rep("*", 20) .. " (set)"
    else
        api_key_display = "(not set - press <C-k> to configure)"
    end

    -- Build checkbox for debug mode
    local debug_checkbox = debug and "[X]" or "[ ]"

    local lines = {
        "╭─ Plugin Settings ─╮",
        "",
        string.format("Scope: %s Global   %s Project-specific", global_radio, project_radio),
        "",
        "OpenAI API Key:",
        "───────────────────────────────────",
        api_key_display,
        "",
        string.format("%s Enable debug logging", debug_checkbox),
        "",
        "───────────────────────────────────",
        "Actions:",
        "  <C-g>  Edit API key",
        "  <C-k>  Toggle scope (global/project)",
        "  <C-d>  Toggle debug mode",
        "",
        "Warning: API keys stored in plain text",
        "   Use .env file for better security",
        "",
        "╰─────────────────────────────────╯",
    }

    return lines
end

--- Refresh settings buffer after changes
function M.refresh_settings_buffer()
    local buf_id = M.get_active_buffer()
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end

    -- Temporarily make buffer modifiable
    vim.bo[buf_id].modifiable = true

    -- Render new content
    local content = M.render_settings_buffer()
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)

    -- Back to read-only (settings tab is not directly editable)
    vim.bo[buf_id].modifiable = false
end

--- Toggle settings scope between global and project
function M.toggle_settings_scope()
    local settings = require("n00bkeys.settings")
    local current = settings.get_selected_scope()
    local new_scope = current == "global" and "project" or "global"
    settings.set_selected_scope(new_scope)

    -- Refresh buffer to show new scope's values
    M.refresh_settings_buffer()
end

--- Toggle debug mode between enabled and disabled
function M.toggle_debug_mode()
    local settings = require("n00bkeys.settings")
    local config = require("n00bkeys.config")

    -- Get current state
    local current = settings.get_current_debug_mode()
    local new_state = not current

    -- Save to settings
    settings.save_current_debug_mode(new_state)

    -- Update runtime config (affects current session)
    config.options.debug = new_state

    -- Refresh UI
    M.refresh_settings_buffer()
end

--- Edit API key via input prompt
function M.edit_api_key()
    vim.ui.input({
        prompt = "OpenAI API Key: ",
        default = "", -- Don't show current key (security)
    }, function(input)
        if input and input ~= "" then
            local settings = require("n00bkeys.settings")
            settings.save_current_api_key(input)
            M.refresh_settings_buffer()
        end
        -- If cancelled (nil) or empty, do nothing (keep existing key)
    end)
end
--- Render history buffer content (conversation-based)
--- @return table Lines of content
function M.render_history_buffer()
    local history = require("n00bkeys.history")
    local conversations = history.get_conversations()

    local lines = {
        "",
        string.format("╭─ Conversation History (%d conversations) ─╮", #conversations),
        "",
    }

    if #conversations == 0 then
        table.insert(lines, "No conversations yet.")
        table.insert(lines, "")
        table.insert(lines, "Submit a query in the Query tab to start building history.")
    else
        for i, conv in ipairs(conversations) do
            -- Format timestamp (ISO 8601 → YYYY-MM-DD HH:MM)
            local timestamp = (conv.created_at or ""):sub(1, 16):gsub("T", " ")

            -- Get summary (truncated first message)
            local summary = conv.summary or "Untitled conversation"
            if #summary > 40 then
                summary = summary:sub(1, 37) .. "..."
            end

            -- Entry line with index
            table.insert(lines, string.format("[%d] %s | %s", i, timestamp, summary))

            -- Find assistant's response for preview
            local response_preview = ""
            for _, msg in ipairs(conv.messages or {}) do
                if msg.role == "assistant" then
                    response_preview = msg.content or ""
                    break
                end
            end

            -- Truncate response preview
            if #response_preview > 50 then
                response_preview = response_preview:sub(1, 47) .. "..."
            end

            -- Message count and response preview
            local msg_count = #(conv.messages or {})
            if response_preview ~= "" then
                table.insert(
                    lines,
                    string.format(
                        "    %d message%s | %s",
                        msg_count,
                        msg_count == 1 and "" or "s",
                        response_preview
                    )
                )
            else
                table.insert(
                    lines,
                    string.format("    %d message%s", msg_count, msg_count == 1 and "" or "s")
                )
            end

            -- Separator
            table.insert(lines, "")
        end
    end

    table.insert(
        lines,
        "───────────────────────────────────"
    )
    table.insert(lines, "<Enter> Open | d Delete | c Clear all")
    table.insert(
        lines,
        "╰─────────────────────────────────╯"
    )
    table.insert(lines, "")

    return lines
end

--- Refresh history buffer (re-render content)
function M.refresh_history_buffer()
    local buf_id = M.get_active_buffer()
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end

    vim.bo[buf_id].modifiable = true
    local lines = M.render_history_buffer()
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.bo[buf_id].modifiable = false
end

--- Extract entry index from cursor position in history buffer
--- @return number|nil Entry index (1-indexed), or nil if not on entry line
local function extract_history_index_at_cursor()
    local cursor = vim.api.nvim_win_get_cursor(M.state.win_id)
    local line_num = cursor[1]

    local buf_id = M.get_active_buffer()
    local line_text = vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1]

    -- Match pattern: "[N]" at start of line
    local index = line_text and line_text:match("^%[(%d+)%]")
    if index then
        return tonumber(index)
    end

    -- Try previous line (if cursor on Response line)
    if line_num > 1 then
        line_text = vim.api.nvim_buf_get_lines(buf_id, line_num - 2, line_num - 1, false)[1]
        index = line_text and line_text:match("^%[(%d+)%]")
        if index then
            return tonumber(index)
        end
    end

    return nil
end

--- Load history item at cursor into Query tab
function M.load_history_item_at_cursor()
    if M.get_active_tab() ~= "history" then
        return
    end

    local index = extract_history_index_at_cursor()
    if not index then
        M.set_error("No history item selected")
        return
    end

    -- Load entry
    local history = require("n00bkeys.history")
    local entries = history.get_entries()
    local entry = entries[index]

    if not entry then
        M.set_error("Invalid history item")
        return
    end

    -- Switch to Query tab
    M.switch_tab("query")

    -- Set prompt in input buffer (not conversation buffer which is read-only)
    local input_buf = M.state.input_buf_id
    if input_buf and vim.api.nvim_buf_is_valid(input_buf) then
        vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { entry.prompt })
    end

    -- Focus prompt for editing
    M.focus_prompt()
end

--- Delete history item at cursor
function M.delete_history_item_at_cursor()
    if M.get_active_tab() ~= "history" then
        return
    end

    local index = extract_history_index_at_cursor()
    if not index then
        return
    end

    -- Delete entry
    local history = require("n00bkeys.history")
    history.delete_entry(index)

    -- Refresh buffer
    M.refresh_history_buffer()
end

--- Clear all history (with confirmation)
function M.clear_all_history()
    if M.get_active_tab() ~= "history" then
        return
    end

    vim.ui.input({
        prompt = "Clear all history? (y/N): ",
    }, function(input)
        if input and input:lower() == "y" then
            local history = require("n00bkeys.history")
            history.clear()
            M.refresh_history_buffer()
        end
    end)
end

--- Open a conversation from history by index
--- @param index number Conversation index (1-indexed, newest first)
function M.open_conversation_from_history(index)
    local history = require("n00bkeys.history")
    local conversations = history.get_conversations()

    if index < 1 or index > #conversations then
        log.error("ui", "Invalid conversation index: %d", index)
        return
    end

    local conversation = conversations[index]

    -- Switch to Query tab
    M.switch_tab("query")

    -- Load the conversation
    M.load_conversation(conversation.id)
end

--- Delete a conversation by index
--- @param index number Conversation index (1-indexed, newest first)
function M.delete_conversation(index)
    local history = require("n00bkeys.history")
    history.delete_conversation_by_index(index)

    -- Refresh history buffer if we're on that tab
    if M.get_active_tab() == "history" then
        M.refresh_history_buffer()
    end
end

function M.render_context_preview()
    local prompt_module = require("n00bkeys.prompt")

    -- Build the complete system prompt that will be sent to OpenAI
    -- Use a sample query to show query-specific context
    local system_prompt = prompt_module.build_system_prompt("(sample query)")

    local lines = {
        "",
        "╭─ Complete System Prompt (verbatim) ─╮",
        "",
    }

    -- Split the full prompt into lines and add them
    local prompt_lines = vim.split(system_prompt, "\n", { plain = true })
    for _, line in ipairs(prompt_lines) do
        table.insert(lines, line)
    end

    table.insert(lines, "")
    table.insert(
        lines,
        "───────────────────────────────────"
    )
    table.insert(lines, "Above is the exact system prompt sent to OpenAI.")
    table.insert(lines, "Your question is added as the user message.")
    table.insert(lines, "Edit your custom pre-prompt in the Pre-Prompt tab.")
    table.insert(lines, "")
    table.insert(
        lines,
        "╰─────────────────────────────────╯"
    )
    table.insert(lines, "")

    return lines
end

--- Get stub content for a tab
--- @param tab_id string Tab ID
--- @return table Lines of content
function M.get_stub_content(tab_id)
    if tab_id == "history" then
        return M.render_history_buffer()
    elseif tab_id == "context" then
        return M.render_context_preview()
    elseif tab_id == "preprompt" then
        return M.render_preprompt_buffer()
    elseif tab_id == "settings" then
        return M.render_settings_buffer()
    end

    return { "[Invalid tab: " .. tostring(tab_id) .. "]" }
end

--- Create and initialize a buffer for a specific tab
--- @param tab_id string Tab ID
--- @return number Buffer ID
function M.create_tab_buffer(tab_id)
    local buf_id = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    -- Use "hide" instead of "wipe" to keep buffers when switching tabs
    vim.bo[buf_id].bufhidden = "hide"
    vim.bo[buf_id].filetype = "n00bkeys-" .. tab_id

    -- Tab-specific settings
    if tab_id == "query" then
        vim.bo[buf_id].modifiable = true
        -- Initialize with placeholder (will be set by M.open())
    elseif tab_id == "preprompt" then
        -- Preprompt tab is modifiable and has auto-save
        vim.bo[buf_id].modifiable = true
        local content = M.get_stub_content(tab_id)
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)
        -- Setup auto-save
        setup_preprompt_autosave(buf_id)
    else
        -- Set stub content first (while buffer is still modifiable)
        local content = M.get_stub_content(tab_id)
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)
        -- Then make it read-only
        vim.bo[buf_id].modifiable = false
    end

    return buf_id
end

--- Switch to a specific tab
--- @param tab_id string Tab ID to switch to
--- @return boolean Success
function M.switch_tab(tab_id)
    log.debug("ui", "Switching to tab: %s", tab_id)

    -- Validate tab ID
    if not M.is_valid_tab(tab_id) then
        log.error("ui", "Invalid tab ID: %s", tab_id)
        return false
    end

    -- Validate window exists
    if not M.state.win_id or not vim.api.nvim_win_is_valid(M.state.win_id) then
        log.error("ui", "No valid window for tab switching")
        return false
    end

    -- Get or create buffer for target tab
    local tab_state = M.get_tab_state(tab_id)
    local buf_id = tab_state.buf_id

    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        log.debug("ui", "Creating buffer for tab: %s", tab_id)
        buf_id = M.create_tab_buffer(tab_id)
        M.update_tab_state(tab_id, { buf_id = buf_id })

        -- Setup keymaps for the new buffer
        local keymaps = require("n00bkeys.keymaps")
        keymaps.setup_keymaps(buf_id)
    end

    -- Switch window to target buffer
    vim.api.nvim_win_set_buf(M.state.win_id, buf_id)

    -- Refresh context tab content on switch (always shows latest preprompt)
    if tab_id == "context" then
        local lines = M.render_context_preview()
        vim.bo[buf_id].modifiable = true
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        vim.bo[buf_id].modifiable = false
    end

    -- Refresh history tab content on switch (always shows latest entries)
    if tab_id == "history" then
        local lines = M.render_history_buffer()
        vim.bo[buf_id].modifiable = true
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        vim.bo[buf_id].modifiable = false
    end

    -- Update active tab
    M.state.active_tab = tab_id

    -- Update winbar (header) with new tab bar
    update_winbar()

    log.debug("ui", "Tab switched successfully: %s", tab_id)
    return true
end

--- Switch to next tab (cycles)
function M.switch_to_next_tab()
    local current_idx = nil
    for i, tab in ipairs(TABS) do
        if tab.id == M.get_active_tab() then
            current_idx = i
            break
        end
    end

    local next_idx = (current_idx % #TABS) + 1
    return M.switch_tab(TABS[next_idx].id)
end

--- Switch to previous tab (cycles)
function M.switch_to_prev_tab()
    local current_idx = nil
    for i, tab in ipairs(TABS) do
        if tab.id == M.get_active_tab() then
            current_idx = i
            break
        end
    end

    local prev_idx = current_idx == 1 and #TABS or current_idx - 1
    return M.switch_tab(TABS[prev_idx].id)
end

--- Switch to tab by index (1-5)
--- @param index number Tab index (1-5)
--- @return boolean Success
function M.switch_tab_by_index(index)
    if index < 1 or index > #TABS then
        log.debug("ui", "Invalid tab index: %d", index)
        return false
    end
    return M.switch_tab(TABS[index].id)
end

-- Export as alias for tests
M.switch_to_tab_by_index = M.switch_tab_by_index

-- Export as alias for tests
M.switch_to_tab = M.switch_tab

--- Create a scratch buffer with given options
--- @param name string Buffer name for identification
--- @param modifiable boolean Whether buffer is editable
--- @return number Buffer ID
local function create_scratch_buffer(name, modifiable)
    local buf = vim.api.nvim_create_buf(false, true) -- nofile, scratch
    vim.api.nvim_buf_set_name(buf, "n00bkeys://" .. name)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide" -- Keep buffer alive when hidden (don't wipe on tab switch)
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = modifiable
    return buf
end

--- Check if we should restore a conversation based on config
--- @return boolean True if restore should be attempted
local function should_restore_conversation()
    local config = require("n00bkeys.config")
    local mode = config.options.restore_conversation

    if mode == "never" then
        return false
    elseif mode == "session" then
        -- Restore if we have a last conversation ID in this session
        return vim.g.n00bkeys_last_conversation_id ~= nil
    elseif mode == "always" then
        -- Check for persisted conversation ID
        local persist_path = vim.fn.stdpath("data") .. "/n00bkeys"
        local last_conv_file = persist_path .. "/last_conversation.txt"
        return vim.fn.filereadable(last_conv_file) == 1 or vim.g.n00bkeys_last_conversation_id ~= nil
    end

    return false
end

--- Get the last conversation ID based on restore mode
--- @return string|nil Conversation ID or nil
local function get_last_conversation_id()
    local config = require("n00bkeys.config")
    local mode = config.options.restore_conversation

    if mode == "never" then
        return nil
    elseif mode == "session" then
        return vim.g.n00bkeys_last_conversation_id
    elseif mode == "always" then
        -- Try session first (faster)
        if vim.g.n00bkeys_last_conversation_id then
            return vim.g.n00bkeys_last_conversation_id
        end

        -- Fall back to persisted file
        local persist_path = vim.fn.stdpath("data") .. "/n00bkeys"
        local last_conv_file = persist_path .. "/last_conversation.txt"

        if vim.fn.filereadable(last_conv_file) == 1 then
            local lines = vim.fn.readfile(last_conv_file)
            if #lines > 0 and lines[1] ~= "" then
                return vim.trim(lines[1])
            end
        end
    end

    return nil
end

--- Persist conversation ID to disk (for "always" mode)
--- @param conv_id string Conversation ID
local function persist_conversation_id(conv_id)
    local config = require("n00bkeys.config")
    if config.options.restore_conversation ~= "always" then
        return
    end

    local persist_path = vim.fn.stdpath("data") .. "/n00bkeys"
    vim.fn.mkdir(persist_path, "p")

    local last_conv_file = persist_path .. "/last_conversation.txt"
    vim.fn.writefile({ conv_id }, last_conv_file)

    log.debug("ui", "Persisted conversation ID to %s", last_conv_file)
end

--- Attempt to restore the last conversation
--- Returns true if restore succeeded, false if failed (caller should create new conversation)
--- @return boolean Success
local function try_restore_conversation()
    local last_id = get_last_conversation_id()
    if not last_id then
        log.debug("ui", "No conversation to restore (no session state)")
        return false
    end

    log.debug("ui", "Attempting to restore conversation: %s", last_id)

    -- Use pcall to safely attempt restore (handles missing conversations gracefully)
    local ok, result = pcall(M.load_conversation, last_id)

    if ok and result then
        log.debug("ui", "Successfully restored conversation: %s", last_id)
        -- Show notification to user (P1-1: UI feedback)
        vim.notify("Conversation restored", vim.log.levels.INFO)
        return true
    else
        log.debug("ui", "Failed to restore conversation: %s (error: %s)", last_id, tostring(result))
        -- Clear the invalid session state
        vim.g.n00bkeys_last_conversation_id = nil
        return false
    end
end

--- Open the n00bkeys sidebar
function M.open()
    log.debug("ui.open", "Opening n00bkeys sidebar")

    -- Setup highlight groups for message colors
    setup_highlights()

    -- Singleton check - if sidebar already exists, just focus it
    if M.state.sidebar_win_id and vim.api.nvim_win_is_valid(M.state.sidebar_win_id) then
        log.debug("ui.open", "Sidebar already exists, focusing input")
        if M.state.input_win_id and vim.api.nvim_win_is_valid(M.state.input_win_id) then
            vim.api.nvim_set_current_win(M.state.input_win_id)
        end
        return
    end

    -- Save current window to return to later
    local prev_win = vim.api.nvim_get_current_win()

    -- Create the three buffers
    M.state.conversation_buf_id = create_scratch_buffer("conversation", false) -- readonly
    M.state.input_buf_id = create_scratch_buffer("input", true) -- editable
    M.state.footer_buf_id = create_scratch_buffer("footer", false) -- readonly

    -- Set initial content for input (empty, NO placeholder)
    vim.api.nvim_buf_set_lines(M.state.input_buf_id, 0, -1, false, { "" })

    -- Footer: keybinding hints (readonly)
    vim.bo[M.state.footer_buf_id].modifiable = true
    vim.api.nvim_buf_set_lines(M.state.footer_buf_id, 0, -1, false, { FOOTER_TEXT })
    vim.bo[M.state.footer_buf_id].modifiable = false

    -- Create vertical split on the right for sidebar
    vim.cmd("botright vsplit")
    M.state.sidebar_win_id = vim.api.nvim_get_current_win()
    M.state.win_id = M.state.sidebar_win_id -- Backwards compat alias

    -- Set width from config
    vim.api.nvim_win_set_width(M.state.sidebar_win_id, get_sidebar_width())

    -- Set conversation buffer in main sidebar window
    vim.api.nvim_win_set_buf(M.state.sidebar_win_id, M.state.conversation_buf_id)

    -- Configure conversation window
    vim.wo[M.state.sidebar_win_id].wrap = true
    vim.wo[M.state.sidebar_win_id].linebreak = true
    vim.wo[M.state.sidebar_win_id].number = false
    vim.wo[M.state.sidebar_win_id].relativenumber = false
    vim.wo[M.state.sidebar_win_id].signcolumn = "no"
    vim.wo[M.state.sidebar_win_id].winfixwidth = true

    -- Set winbar (header) to show tabs
    update_winbar()

    -- Create horizontal split below for input (3 lines high)
    vim.cmd("belowright split")
    M.state.input_win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.state.input_win_id, M.state.input_buf_id)
    vim.api.nvim_win_set_height(M.state.input_win_id, 3)

    -- Configure input window
    vim.wo[M.state.input_win_id].wrap = true
    vim.wo[M.state.input_win_id].number = false
    vim.wo[M.state.input_win_id].relativenumber = false
    vim.wo[M.state.input_win_id].signcolumn = "no"
    vim.wo[M.state.input_win_id].winfixheight = true

    -- Create horizontal split below for footer (1 line high)
    vim.cmd("belowright split")
    M.state.footer_win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.state.footer_win_id, M.state.footer_buf_id)
    vim.api.nvim_win_set_height(M.state.footer_win_id, 1)

    -- Configure footer window
    vim.wo[M.state.footer_win_id].wrap = false
    vim.wo[M.state.footer_win_id].number = false
    vim.wo[M.state.footer_win_id].relativenumber = false
    vim.wo[M.state.footer_win_id].signcolumn = "no"
    vim.wo[M.state.footer_win_id].winfixheight = true
    vim.wo[M.state.footer_win_id].cursorline = false

    -- Focus the input window and start insert mode
    -- Use vim.schedule to ensure window is fully set up before startinsert
    vim.api.nvim_set_current_win(M.state.input_win_id)
    vim.schedule(function()
        -- Double-check we're still in the right window
        if M.state.input_win_id and vim.api.nvim_win_is_valid(M.state.input_win_id) then
            vim.api.nvim_set_current_win(M.state.input_win_id)
            vim.cmd("startinsert")
        end
    end)

    -- Setup keymaps for the input buffer
    local keymaps = require("n00bkeys.keymaps")
    keymaps.setup_keymaps(M.state.input_buf_id)

    -- Also setup keymaps for conversation buffer (for navigation)
    keymaps.setup_keymaps(M.state.conversation_buf_id)

    -- Auto-redirect to input when trying to type in conversation buffer
    -- This makes it more user-friendly: click anywhere in sidebar and start typing
    vim.api.nvim_create_autocmd("InsertEnter", {
        buffer = M.state.conversation_buf_id,
        callback = function()
            -- Exit insert mode (conversation is readonly)
            vim.cmd("stopinsert")
            -- Focus the input window instead
            if M.state.input_win_id and vim.api.nvim_win_is_valid(M.state.input_win_id) then
                vim.api.nvim_set_current_win(M.state.input_win_id)
                vim.schedule(function()
                    vim.cmd("startinsert")
                end)
            end
        end,
    })

    -- Initialize query tab state for backwards compat
    M.state.active_tab = "query"
    M.update_tab_state("query", { buf_id = M.state.conversation_buf_id })

    -- Handle conversation state based on restore mode
    local config = require("n00bkeys.config")
    local mode = config.options.restore_conversation

    if mode == "never" then
        -- Always start fresh when mode is "never"
        M.state.active_conversation_id = "conv_" .. os.time()
        M.state.current_messages = {}
        -- Explicitly clear the conversation buffer to ensure fresh state
        if M.state.conversation_buf_id and vim.api.nvim_buf_is_valid(M.state.conversation_buf_id) then
            vim.bo[M.state.conversation_buf_id].modifiable = true
            vim.api.nvim_buf_set_lines(M.state.conversation_buf_id, 0, -1, false, { "" })
            vim.bo[M.state.conversation_buf_id].modifiable = false
        end
        log.debug("ui.open", "Started new conversation (restore=never): %s", M.state.active_conversation_id)
    elseif not M.state.active_conversation_id then
        -- Only attempt restore if no active conversation (first open or after explicit clear)
        local restored = false

        if should_restore_conversation() then
            restored = try_restore_conversation()
        end

        -- If restore failed, start a new conversation
        if not restored then
            M.state.active_conversation_id = "conv_" .. os.time()
            M.state.current_messages = {}
            log.debug("ui.open", "Started new conversation: %s", M.state.active_conversation_id)
        end
    end

    -- Always render the conversation buffer (handles both fresh state and preserved state from previous close)
    if #M.state.current_messages > 0 then
        M.refresh_conversation_buffer()
    end

    -- Setup autocmd for cleanup when any of our windows close
    vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(args)
            local closed_win = tonumber(args.match)
            -- If any of our windows close, close the whole sidebar
            if
                closed_win == M.state.sidebar_win_id
                or closed_win == M.state.input_win_id
                or closed_win == M.state.footer_win_id
            then
                vim.schedule(function()
                    if not _closing then
                        M.close()
                    end
                end)
            end
        end,
    })

    log.debug(
        "ui.open",
        "Sidebar opened with conversation=%s, input=%s, footer=%s",
        M.state.sidebar_win_id,
        M.state.input_win_id,
        M.state.footer_win_id
    )
end

--- Close the n00bkeys sidebar and cleanup
function M.close()
    -- Guard against recursive calls (e.g., from autocmds)
    if _closing then
        return
    end
    _closing = true

    log.debug("ui.close", "Closing n00bkeys sidebar")

    -- Save current conversation before closing (also tracks it in session)
    if M.state.active_conversation_id and #M.state.current_messages > 0 then
        M.save_conversation()
        -- Track this as the last active conversation for session restore
        vim.g.n00bkeys_last_conversation_id = M.state.active_conversation_id

        -- Persist to disk if "always" mode (P1-2: cross-session restore)
        persist_conversation_id(M.state.active_conversation_id)
    end

    -- Close all sidebar windows
    local windows_to_close = {
        M.state.footer_win_id,
        M.state.input_win_id,
        M.state.sidebar_win_id,
    }

    for _, win_id in ipairs(windows_to_close) do
        if win_id and vim.api.nvim_win_is_valid(win_id) then
            pcall(vim.api.nvim_win_close, win_id, true)
        end
    end

    -- Cleanup sidebar buffers
    local buffers_to_delete = {
        M.state.conversation_buf_id,
        M.state.input_buf_id,
        M.state.footer_buf_id,
    }

    for _, buf_id in ipairs(buffers_to_delete) do
        if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
            pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
        end
    end

    -- Cleanup all tab buffers (legacy)
    for tab_id, tab_state in pairs(M.state.tabs) do
        if tab_state.buf_id and vim.api.nvim_buf_is_valid(tab_state.buf_id) then
            pcall(vim.api.nvim_buf_delete, tab_state.buf_id, { force = true })
        end
        -- Reset tab state
        tab_state.buf_id = nil
        tab_state.is_loading = false
        tab_state.last_error = nil
        tab_state.last_response = nil
    end

    -- Reset state (but don't clear active_conversation_id - keep it for restore)
    M.state.sidebar_win_id = nil
    M.state.input_win_id = nil
    M.state.footer_win_id = nil
    M.state.conversation_buf_id = nil
    M.state.input_buf_id = nil
    M.state.footer_buf_id = nil
    M.state.win_id = nil
    M.state.active_tab = "query" -- Reset to default

    _closing = false
end

--- Get the current prompt text from the input buffer
--- Reads all lines from the dedicated input buffer
---@return string The prompt text
function M.get_prompt()
    -- Use the dedicated input buffer
    local buf_id = M.state.input_buf_id
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        log.debug("ui", "No valid input buffer")
        return ""
    end

    -- Get all lines from input buffer
    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

    -- Join and trim
    local prompt = table.concat(lines, "\n")
    prompt = vim.trim(prompt)

    return prompt
end

--- Update the footer text
---@param text string Text to show in footer
local function update_footer(text)
    local buf_id = M.state.footer_buf_id
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end
    vim.bo[buf_id].modifiable = true
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { text })
    vim.bo[buf_id].modifiable = false
end

--- Set the loading state and update UI
---@param is_loading boolean Whether we're loading
function M.set_loading(is_loading)
    -- Update state
    M.update_tab_state("query", { is_loading = is_loading })

    -- Update footer to show loading status with cancel hint
    if is_loading then
        update_footer(" Loading... (<C-c> Cancel) ")
    else
        update_footer(FOOTER_TEXT)
    end
end

--- Display an error message in the UI
---@param error_msg string The error message to display
function M.set_error(error_msg)
    -- Update state
    M.update_tab_state("query", { is_loading = false, last_error = error_msg })

    -- Show error in footer temporarily
    update_footer(" Error: " .. error_msg .. " ")

    -- Reset footer after 3 seconds
    vim.defer_fn(function()
        update_footer(FOOTER_TEXT)
    end, 3000)

    log.debug("ui", "Error displayed: %s", error_msg)
end

--- Display a response in the UI (legacy - now handled by conversation buffer)
---@param response string The response text to display
function M.set_response(response)
    -- Update state
    M.update_tab_state(
        "query",
        { is_loading = false, last_response = response, last_error = vim.NIL }
    )

    -- Response is now handled by conversation buffer via add_assistant_message() + refresh
    -- This function is kept for backwards compatibility
    log.debug("ui", "Response stored in state")
end

--- Submit the current query to the AI
function M.submit_query()
    local prompt = M.get_prompt()

    -- Check for empty prompt
    if prompt == "" then
        log.debug("ui", "Empty prompt, showing error")
        M.set_error("Please enter a question")
        return
    end

    log.debug("ui", "Submitting query: %s", prompt)

    -- Initialize conversation if needed
    if not M.state.active_conversation_id then
        M.state.active_conversation_id = "conv_" .. os.time()
    end

    -- Store prompt for possible cancellation restore
    M.state.last_submitted_prompt = prompt
    M.state.pending_request_cancelled = false

    -- Add user message to conversation
    M.add_user_message(prompt)

    -- Update conversation display to show user message (but keep input buffer until success)
    M.refresh_conversation_buffer()

    -- Show loading state
    M.set_loading(true)

    -- Call OpenAI API with conversation history
    local openai = require("n00bkeys.openai")
    openai.query_conversation(M.state.current_messages, function(err, response)
        -- Schedule UI update to run in main event loop
        vim.schedule(function()
            -- Check if request was cancelled
            if M.state.pending_request_cancelled then
                log.debug("ui", "Request was cancelled, ignoring response")
                M.state.pending_request_cancelled = false
                return
            end

            if not err then
                -- Clear the input buffer on success
                if M.state.input_buf_id and vim.api.nvim_buf_is_valid(M.state.input_buf_id) then
                    vim.api.nvim_buf_set_lines(M.state.input_buf_id, 0, -1, false, { "" })
                end

                -- Add assistant response to conversation
                M.add_assistant_message(response)

                -- Update conversation display
                M.refresh_conversation_buffer()

                -- Store last_response for apply_response functionality
                M.update_tab_state("query", { last_response = response })

                -- Clear loading state and restore footer
                M.set_loading(false)

                -- Save conversation to history
                M.save_conversation()
            else
                -- On error, remove the user message from conversation (so they can retry)
                if #M.state.current_messages > 0 then
                    table.remove(M.state.current_messages)
                end

                -- Extract error message from error object
                local error_msg = err.error or tostring(err)

                -- Add error to conversation display so it's visible
                M.add_error_message(error_msg)
                M.refresh_conversation_buffer()

                -- Clear loading state first (so footer shows error, not loading)
                M.update_tab_state("query", { is_loading = false })

                M.set_error(error_msg)
            end
        end)
    end)
end

--- Add an error message to the conversation display
--- @param content string Error message content
function M.add_error_message(content)
    local message = {
        role = "error",
        content = "Error: " .. content,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    table.insert(M.state.current_messages, message)
    log.debug("ui", "Added error message to conversation")
end

--- Clear and start a new conversation
function M.clear()
    -- Save current conversation if it has messages
    if M.state.active_conversation_id and #M.state.current_messages > 0 then
        M.save_conversation()
    end

    -- Generate new conversation ID
    M.state.active_conversation_id = "conv_" .. os.time() .. "_" .. math.random(1000, 9999)
    M.state.current_messages = {}

    -- Clear conversation display
    M.refresh_conversation_buffer()

    -- Clear input buffer (no placeholder text!)
    if M.state.input_buf_id and vim.api.nvim_buf_is_valid(M.state.input_buf_id) then
        vim.api.nvim_buf_set_lines(M.state.input_buf_id, 0, -1, false, { "" })
    end

    -- Reset tab state
    M.update_tab_state("query", {
        is_loading = false,
        last_error = vim.NIL,
        last_response = vim.NIL,
    })

    -- Focus input window
    if M.state.input_win_id and vim.api.nvim_win_is_valid(M.state.input_win_id) then
        vim.api.nvim_set_current_win(M.state.input_win_id)
        vim.cmd("startinsert")
    end
end

--- Focus the input area for editing
function M.focus_prompt()
    if not M.state.input_win_id or not vim.api.nvim_win_is_valid(M.state.input_win_id) then
        return
    end

    -- Switch to input window
    vim.api.nvim_set_current_win(M.state.input_win_id)

    -- Enter insert mode
    vim.cmd("startinsert")
end

--- Apply the last response as the new prompt
function M.apply_response()
    -- Validate we're in query tab
    local tab_state = M.get_tab_state("query")
    if not tab_state.last_response then
        M.set_error("No response to apply")
        return
    end

    local buf_id = M.state.input_buf_id
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end

    -- Put last response in input buffer for editing
    local response_lines = vim.split(tab_state.last_response, "\n")
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, response_lines)

    -- Focus input for editing
    M.focus_prompt()
end

--- Cancel pending request and restore the user's prompt
--- Called via <C-c> during loading state
function M.cancel_request()
    local tab_state = M.get_tab_state("query")

    -- Only cancel if we're actually loading
    if not tab_state.is_loading then
        log.debug("ui", "cancel_request called but not loading, ignoring")
        return
    end

    log.debug("ui", "Cancelling pending request")

    -- Mark request as cancelled (callback will check this flag)
    M.state.pending_request_cancelled = true

    -- Remove the user message we added to conversation
    if #M.state.current_messages > 0 then
        table.remove(M.state.current_messages)
    end

    -- Refresh conversation display (removes the pending user message)
    M.refresh_conversation_buffer()

    -- Restore the prompt to input buffer
    if M.state.last_submitted_prompt then
        local buf_id = M.state.input_buf_id
        if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
            local prompt_lines = vim.split(M.state.last_submitted_prompt, "\n")
            vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, prompt_lines)
        end
    end

    -- Clear loading state and restore footer
    M.set_loading(false)

    -- Focus input for editing
    M.focus_prompt()

    log.debug("ui", "Request cancelled, prompt restored")
end

return M
