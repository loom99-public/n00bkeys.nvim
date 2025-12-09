---@tag n00bkeys.history
--- History Module
--- Persistent storage for conversation history
--- Handles file I/O, conversation management, and v1→v2 migration
---@private
local M = {}

local log = require("n00bkeys.util.log")
local fs = require("n00bkeys.util.fs")

-- Constants
M.HISTORY_VERSION = 2 -- Updated to v2 for conversational storage
M.DEFAULT_MAX_ENTRIES = 100
M.HISTORY_SUBPATH = "n00bkeys/history.json"

-- Internal cache
M._cache = nil

--- Get default v2 history structure
--- @return table Default history with conversations array
function M.get_default_history()
    return {
        version = M.HISTORY_VERSION,
        conversations = {}, -- v2: array of conversations (each with messages)
    }
end

--- Get path to history file
--- Uses vim.fn.stdpath('data') for Neovim standard data location
--- @return string Absolute path to history file
function M.get_history_file_path()
    local data_dir = vim.fn.stdpath("data")
    return data_dir .. "/" .. M.HISTORY_SUBPATH
end

--- Generate conversation summary from messages
--- Uses first user message, truncated to 50 chars
--- @param messages table Array of messages
--- @return string Summary text
local function generate_summary(messages)
    for _, msg in ipairs(messages) do
        if msg.role == "user" then
            local summary = msg.content:sub(1, 50)
            if #msg.content > 50 then
                summary = summary .. "..."
            end
            return summary
        end
    end
    return "Untitled conversation"
end

--- Migrate v1 history to v2 format
--- Each v1 entry becomes a separate conversation with 2 messages
--- @param v1_data table V1 history data
--- @return table V2 history data
local function migrate_v1_to_v2(v1_data)
    log.debug("history", "Migrating v1 history to v2 (%d entries)", #(v1_data.entries or {}))

    local v2_data = M.get_default_history()

    -- Convert each v1 entry to a v2 conversation
    for i, entry in ipairs(v1_data.entries or {}) do
        local timestamp = entry.timestamp or os.date("!%Y-%m-%dT%H:%M:%SZ")
        local conv_id = "conv_" .. os.time() .. "_" .. i -- Ensure unique IDs

        local messages = {
            {
                role = "user",
                content = entry.prompt,
                timestamp = timestamp,
            },
            {
                role = "assistant",
                content = entry.response,
                timestamp = timestamp, -- Same timestamp for both in migration
            },
        }

        local conversation = {
            id = conv_id,
            created_at = timestamp,
            updated_at = timestamp,
            summary = generate_summary(messages),
            messages = messages,
        }

        table.insert(v2_data.conversations, conversation)
    end

    log.debug("history", "Migration complete: %d conversations", #v2_data.conversations)
    return v2_data
end

--- Create backup of v1 history file
--- @param path string Path to history file
--- @return boolean Success
local function backup_v1_file(path)
    local backup_path = path .. ".v1.backup"

    -- Read original file
    local file = io.open(path, "r")
    if not file then
        return false
    end
    local content = file:read("*a")
    file:close()

    -- Write backup
    local backup_file = io.open(backup_path, "w")
    if not backup_file then
        log.error("history", "Failed to create v1 backup at: %s", backup_path)
        return false
    end
    backup_file:write(content)
    backup_file:close()

    log.debug("history", "Created v1 backup at: %s", backup_path)
    return true
end

--- Load history from file with automatic v1→v2 migration
--- Returns empty history if file missing or corrupt
--- @return table History object with version and conversations
function M.load()
    -- Return cached if available
    if M._cache then
        return M._cache
    end

    local path = M.get_history_file_path()

    -- Check if file exists
    local file = io.open(path, "r")
    if not file then
        log.debug("history", "History file not found: %s (using defaults)", path)
        M._cache = M.get_default_history()
        return M._cache
    end

    -- Read file content
    local content = file:read("*a")
    file:close()

    -- Handle empty file
    if content == "" then
        log.debug("history", "Empty history file: %s (using defaults)", path)
        M._cache = M.get_default_history()
        return M._cache
    end

    -- Parse JSON
    local ok, decoded = pcall(vim.json.decode, content)
    if not ok or type(decoded) ~= "table" then
        log.error("history", "Corrupt history file: %s (using defaults)", path)
        M._cache = M.get_default_history()
        return M._cache
    end

    -- Check version and migrate if needed
    local version = decoded.version or 1 -- Default to v1 if no version field

    if version == 1 then
        -- Backup v1 file before migration
        if not backup_v1_file(path) then
            log.error("history", "Failed to backup v1 file, aborting migration")
            M._cache = M.get_default_history()
            return M._cache
        end

        -- Migrate to v2
        local v2_data = migrate_v1_to_v2(decoded)

        -- Save migrated data
        if M.save(v2_data) then
            log.debug("history", "Successfully migrated v1 → v2")
            M._cache = v2_data
            return M._cache
        else
            log.error("history", "Failed to save migrated v2 data")
            M._cache = M.get_default_history()
            return M._cache
        end
    elseif version == 2 then
        -- Validate v2 structure
        if type(decoded.conversations) ~= "table" then
            log.error("history", "Invalid v2 structure (missing conversations array)")
            M._cache = M.get_default_history()
            return M._cache
        end

        M._cache = decoded
        return M._cache
    else
        -- Unknown version
        log.error("history", "Unknown history version: %d", version)
        M._cache = M.get_default_history()
        return M._cache
    end
end

--- Save history to file
--- @param history table History object to save
--- @return boolean Success
function M.save(history)
    local path = M.get_history_file_path()

    -- Ensure directory exists
    if not fs.ensure_directory(path) then
        log.error("history", "Failed to create directory for: %s", path)
        return false
    end

    -- Encode to JSON
    local ok, json = pcall(vim.json.encode, history)
    if not ok then
        log.error("history", "Failed to encode history to JSON: %s", json)
        return false
    end

    -- Write to file
    local file, err = io.open(path, "w")
    if not file then
        log.error("history", "Failed to open history file for writing: %s (%s)", path, err)
        return false
    end

    file:write(json)
    file:close()

    -- Update cache
    M._cache = history

    log.debug("history", "Saved history to: %s (%d conversations)", path, #history.conversations)
    return true
end

--- Add or update a conversation
--- @param conversation table Conversation object with id, messages, etc.
--- @return boolean Success
function M.save_conversation(conversation)
    local history = M.load()

    -- Update timestamps
    conversation.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    if not conversation.created_at then
        conversation.created_at = conversation.updated_at
    end

    -- Update summary based on messages
    if not conversation.summary then
        conversation.summary = generate_summary(conversation.messages or {})
    end

    -- Find existing conversation or add new one
    local found = false
    for i, conv in ipairs(history.conversations) do
        if conv.id == conversation.id then
            history.conversations[i] = conversation
            found = true
            break
        end
    end

    if not found then
        -- Add to beginning (newest first)
        table.insert(history.conversations, 1, conversation)
    end

    -- Prune old conversations if over limit
    local config = require("n00bkeys.config")
    local max_conversations = config.options.history_max_items or M.DEFAULT_MAX_ENTRIES
    while #history.conversations > max_conversations do
        table.remove(history.conversations) -- Remove oldest
    end

    return M.save(history)
end

--- Get conversation by ID
--- @param conv_id string Conversation ID
--- @return table|nil Conversation object or nil if not found
function M.get_conversation(conv_id)
    local history = M.load()
    for _, conv in ipairs(history.conversations) do
        if conv.id == conv_id then
            return conv
        end
    end
    return nil
end

--- Delete conversation by ID
--- @param conv_id string Conversation ID
--- @return boolean Success
function M.delete_conversation(conv_id)
    local history = M.load()

    for i, conv in ipairs(history.conversations) do
        if conv.id == conv_id then
            table.remove(history.conversations, i)
            return M.save(history)
        end
    end

    log.error("history", "Conversation not found: %s", conv_id)
    return false
end

--- Delete conversation by index (1-indexed, newest first)
--- @param index number Conversation index
--- @return boolean Success
function M.delete_conversation_by_index(index)
    local history = M.load()

    if index < 1 or index > #history.conversations then
        log.error("history", "Invalid conversation index: %d", index)
        return false
    end

    table.remove(history.conversations, index)
    return M.save(history)
end

--- Clear all conversation history
--- @return boolean Success
function M.clear_history()
    local history = M.get_default_history()
    return M.save(history)
end

--- Get all conversations (newest first)
--- @return table Array of conversations
function M.get_conversations()
    local history = M.load()
    return history.conversations
end

--- Legacy compatibility: Get all entries (v1 format)
--- Returns conversations converted to flat entry list for backwards compatibility
--- @return table Array of entries (v1 format)
function M.get_entries()
    local history = M.load()
    local entries = {}

    -- Convert conversations to v1-style entries (first user/assistant pair only)
    for _, conv in ipairs(history.conversations) do
        local user_msg = nil
        local assistant_msg = nil

        for _, msg in ipairs(conv.messages or {}) do
            if msg.role == "user" and not user_msg then
                user_msg = msg
            elseif msg.role == "assistant" and not assistant_msg then
                assistant_msg = msg
            end
            if user_msg and assistant_msg then
                break
            end
        end

        if user_msg and assistant_msg then
            table.insert(entries, {
                timestamp = conv.created_at,
                prompt = user_msg.content,
                response = assistant_msg.content,
            })
        end
    end

    return entries
end

--- Legacy compatibility: Add entry (v1 format)
--- Creates a new conversation with one user message and one assistant message
--- @param prompt string User query
--- @param response string AI response
--- @return boolean Success
function M.add_entry(prompt, response)
    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local conv_id = "conv_" .. os.time()

    local messages = {
        {
            role = "user",
            content = prompt,
            timestamp = timestamp,
        },
        {
            role = "assistant",
            content = response,
            timestamp = timestamp,
        },
    }

    local conversation = {
        id = conv_id,
        created_at = timestamp,
        updated_at = timestamp,
        summary = generate_summary(messages),
        messages = messages,
    }

    return M.save_conversation(conversation)
end

--- Legacy compatibility: Delete entry by index (v1 format)
--- @param index number Entry index (1-indexed, newest first)
--- @return boolean Success
function M.delete_entry(index)
    return M.delete_conversation_by_index(index)
end

---@private
-- Internal: Clear cache for testing
function M._clear_cache()
    M._cache = nil
end

return M
