local log = require("n00bkeys.util.log")

local n00bkeys = {}

--- n00bkeys configuration with its default values.
---
---@type table
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
n00bkeys.options = {
    -- Prints useful logs about what event are triggered, and reasons actions are executed.
    debug = false,

    -- OpenAI API settings
    openai_model = "gpt-4o-mini",
    openai_max_tokens = 500,
    openai_temperature = 0.7,
    openai_timeout = 30,
    -- NOT recommended - use OPENAI_API_KEY environment variable instead
    openai_api_key = nil,

    -- Prompt Engineering
    prompt_template = nil, -- Custom system prompt template (nil = use default)

    -- History settings
    history_enabled = true, -- Enable/disable history capture
    history_max_items = 100, -- Max history entries to keep

    -- Conversation settings
    max_conversation_turns = 10, -- Max turns to keep in conversation context (older messages pruned)
    restore_conversation = "session", -- Conversation restore mode: "session" (Neovim instance), "always" (across restarts), "never" (always fresh)

    -- UI settings
    sidebar_width = 50, -- Width of sidebar in characters

    -- Keybindings (customizable, all buffer-local)
    keymaps = {
        -- Tab navigation
        next_tab = "<Tab>", -- Cycle to next tab
        prev_tab = "<S-Tab>", -- Cycle to previous tab
        tab_1 = "1", -- Jump to Query tab
        tab_2 = "2", -- Jump to History tab
        tab_3 = "3", -- Jump to Context tab
        tab_4 = "4", -- Jump to Settings tab

        -- Query tab actions
        submit = "<CR>", -- Submit query
        clear = "<C-c>", -- Clear prompt and status
        focus = "<C-i>", -- Focus prompt for editing
        apply = "<C-a>", -- Apply last response to prompt
        new_conversation = "<C-n>", -- Start a new conversation (clears conversation restore state)
        close = "<Esc>", -- Close window
    },
}

---@private
local defaults = vim.deepcopy(n00bkeys.options)

--- Defaults n00bkeys options by merging user provided options with the default plugin values.
---
---@param options table Module config table. See |n00bkeys.options|.
---
---@private
function n00bkeys.defaults(options)
    n00bkeys.options = vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, defaults or {}))

    -- Validate options
    assert(
        type(n00bkeys.options.debug) == "boolean",
        "`debug` must be a boolean (`true` or `false`)."
    )

    assert(type(n00bkeys.options.openai_model) == "string", "`openai_model` must be a string.")

    assert(
        type(n00bkeys.options.openai_max_tokens) == "number",
        "`openai_max_tokens` must be a number."
    )

    assert(
        type(n00bkeys.options.openai_temperature) == "number",
        "`openai_temperature` must be a number."
    )

    -- Validate prompt_template if provided
    if n00bkeys.options.prompt_template ~= nil then
        assert(
            type(n00bkeys.options.prompt_template) == "string",
            "`prompt_template` must be a string or nil."
        )
    end

    -- Validate history options
    assert(
        type(n00bkeys.options.history_enabled) == "boolean",
        "`history_enabled` must be a boolean."
    )

    assert(
        type(n00bkeys.options.history_max_items) == "number",
        "`history_max_items` must be a number."
    )

    -- Validate conversation options
    assert(
        type(n00bkeys.options.max_conversation_turns) == "number",
        "`max_conversation_turns` must be a number."
    )

    -- Validate restore_conversation option
    assert(
        type(n00bkeys.options.restore_conversation) == "string",
        "`restore_conversation` must be a string."
    )
    local valid_restore_modes = { session = true, always = true, never = true }
    assert(
        valid_restore_modes[n00bkeys.options.restore_conversation],
        "`restore_conversation` must be one of: 'session', 'always', or 'never'."
    )

    -- Validate UI options
    assert(type(n00bkeys.options.sidebar_width) == "number", "`sidebar_width` must be a number.")

    -- Validate keymaps if provided
    if n00bkeys.options.keymaps ~= nil then
        assert(type(n00bkeys.options.keymaps) == "table", "`keymaps` must be a table.")
    end

    return n00bkeys.options
end

--- Define your n00bkeys setup.
---
---@param options table Module config table. See |n00bkeys.options|.
---
---@usage `require("n00bkeys").setup()` (add `{}` with your |n00bkeys.options| table)
function n00bkeys.setup(options)
    n00bkeys.options = n00bkeys.defaults(options or {})

    log.warn_deprecation(n00bkeys.options)

    return n00bkeys.options
end

return n00bkeys
