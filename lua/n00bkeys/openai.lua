-- OpenAI API client for n00bkeys
local http = require("n00bkeys.http")
local config = require("n00bkeys.config")
local prompt_module = require("n00bkeys.prompt")

local M = {}

local OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"

--- Get API key from all sources with correct precedence
--- Priority: env var > Settings Panel > project .env > user ~/.env > config
---@return string|nil api_key
---@return string|nil error_message
local function get_api_key()
    -- Priority 1: Environment variable (highest - for CI/testing override)
    local api_key = vim.env.OPENAI_API_KEY
    if api_key and api_key ~= "" then
        return api_key, nil
    end

    -- Priority 2: Settings Panel (UI storage)
    local settings = require("n00bkeys.settings")
    local settings_key = settings.get_current_api_key()
    if settings_key and settings_key ~= "" then
        return settings_key, nil
    end

    -- Priority 3: Project .env file
    local env_file = vim.fn.getcwd() .. "/.env"
    if vim.fn.filereadable(env_file) == 1 then
        local lines = vim.fn.readfile(env_file)
        for _, line in ipairs(lines) do
            -- Match OPENAI_API_KEY=value (with optional quotes)
            local value = line:match("^OPENAI_API_KEY%s*=%s*(.+)$")
            if value then
                -- Remove surrounding quotes if present
                value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
                return value, nil
            end
        end
    end

    -- Priority 4: User ~/.env file
    local user_env = vim.fn.expand("~/.env")
    if vim.fn.filereadable(user_env) == 1 then
        local lines = vim.fn.readfile(user_env)
        for _, line in ipairs(lines) do
            -- Match OPENAI_API_KEY=value (with optional quotes)
            local value = line:match("^OPENAI_API_KEY%s*=%s*(.+)$")
            if value then
                -- Remove surrounding quotes if present
                value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
                return value, nil
            end
        end
    end

    -- Priority 5: Config option (lowest - not recommended for security)
    if config.options.openai_api_key then
        return config.options.openai_api_key, nil
    end

    return nil, "OPENAI_API_KEY not found. Set via environment, Settings Panel, or .env file."
end

--- Query OpenAI API with a user prompt
---@param prompt string User's question
---@param callback function(err, response) Callback with (error, response_text)
function M.query(prompt, callback)
    local api_key, err = get_api_key()
    if not api_key then
        vim.schedule(function()
            callback({ error = err }, nil)
        end)
        return
    end

    -- Build messages with context-aware system prompt
    local messages = prompt_module.build_messages(prompt)

    local request_body = {
        model = config.options.openai_model,
        messages = messages, -- Now includes system prompt with context
        max_tokens = config.options.openai_max_tokens,
        temperature = config.options.openai_temperature,
    }

    local headers = {
        Authorization = "Bearer " .. api_key,
    }

    http.post(OPENAI_API_URL, headers, request_body, function(http_err, response)
        if http_err then
            callback(http_err, nil)
            return
        end

        -- Parse OpenAI response
        if response.error then
            callback({
                error = response.error.message or "OpenAI API error",
                type = response.error.type,
            }, nil)
            return
        end

        if not response.choices or #response.choices == 0 then
            callback({ error = "No response from OpenAI" }, nil)
            return
        end

        local message_content = response.choices[1].message.content
        callback(nil, message_content)
    end)
end

--- Query OpenAI API with conversation history
---@param messages table Array of conversation messages [{role, content}]
---@param callback function(err, response) Callback with (error, response_text)
function M.query_conversation(messages, callback)
    local api_key, err = get_api_key()
    if not api_key then
        vim.schedule(function()
            callback({ error = err }, nil)
        end)
        return
    end

    -- Build request messages: [system prompt] + conversation history
    local system_prompt = prompt_module.build_system_prompt()
    local request_messages = {
        { role = "system", content = system_prompt },
    }

    -- Prune messages to stay within max_conversation_turns limit
    -- A "turn" is a user message + assistant response pair
    local max_turns = config.options.max_conversation_turns or 10
    local pruned_messages = messages

    -- Count user messages to determine number of turns
    local user_count = 0
    for _, msg in ipairs(messages) do
        if msg.role == "user" then
            user_count = user_count + 1
        end
    end

    -- If we exceed max turns, prune oldest messages
    if user_count > max_turns then
        local to_skip = (user_count - max_turns) * 2 -- Skip oldest turns (user + assistant pairs)
        pruned_messages = {}
        local skipped = 0
        for _, msg in ipairs(messages) do
            if skipped < to_skip then
                skipped = skipped + 1
            else
                table.insert(pruned_messages, msg)
            end
        end
    end

    -- Add pruned conversation messages
    for _, msg in ipairs(pruned_messages) do
        table.insert(request_messages, {
            role = msg.role,
            content = msg.content,
        })
    end

    local request_body = {
        model = config.options.openai_model,
        messages = request_messages,
        max_tokens = config.options.openai_max_tokens,
        temperature = config.options.openai_temperature,
    }

    local headers = {
        Authorization = "Bearer " .. api_key,
    }

    http.post(OPENAI_API_URL, headers, request_body, function(http_err, response)
        if http_err then
            callback(http_err, nil)
            return
        end

        -- Parse OpenAI response
        if response.error then
            callback({
                error = response.error.message or "OpenAI API error",
                type = response.error.type,
            }, nil)
            return
        end

        if not response.choices or #response.choices == 0 then
            callback({ error = "No response from OpenAI" }, nil)
            return
        end

        local message_content = response.choices[1].message.content
        callback(nil, message_content)
    end)
end
return M
