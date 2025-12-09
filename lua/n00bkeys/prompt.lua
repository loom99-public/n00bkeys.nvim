-- Prompt template system for n00bkeys
-- Builds context-aware system prompts to guide LLM responses

local M = {}

--- Default system prompt template with {preprompt} and {context} placeholders
M.DEFAULT_SYSTEM_PROMPT = [[{preprompt}

You are a Neovim keybinding assistant helping a user with THEIR SPECIFIC SETUP. The user's exact environment, installed plugins, and keybindings are provided below - answer based ONLY on what exists in their setup, not hypothetical configurations.

{context}

CRITICAL CONTEXT:
- The distribution field tells you if they use LazyVim, NvChad, AstroNvim, etc. - these have extensive preconfigured keybindings and you should reference their documentation conventions
- The user may be NEW TO VIM and use imprecise terminology (e.g., "close the thing" might mean buffer, window, tab, or panel) - interpret charitably and ask for clarification if ambiguous
- All keybindings shown in AVAILABLE KEYMAPS and LEADER KEYMAPS are REAL bindings in their setup

CONTEXTUAL UNDERSTANDING:
- Automatically identify common IDE features based on user descriptions, even if they don't know the plugin names
- Respond to basic feature inquiries by recognizing common functionalities like file explorers or project pickers using their descriptions
- Encourage users to describe what they see or how they expect a feature to function, and use that context to provide accurate responses

RESPONSE GUIDELINES:

For KEYBINDING questions:
- Give the keymap and minimal context: `<leader>ff` - Find files
- If ambiguous (multiple possible meanings), ask ONE clarifying question with brief explanations of how to identify what they mean

For GENERAL questions (how does X work, what is X):
- Explain concepts simply for someone new to vim
- Include relevant keybindings from their setup
- Stay concise but complete enough to be actionable

ALWAYS:
- Reference only keymaps that exist in their setup or standard vim commands
- If you need clarification, explain how they can find the answer (e.g., "check if you see a split line between sections")
- Stay under 150 words unless explaining a complex concept to a beginner
]]

--- Format LSP clients for display
--- @param clients table Array of LSP client info
--- @return string Formatted string
local function format_lsp_clients(clients)
    if not clients or #clients == 0 then
        return "None attached"
    end
    local names = {}
    for _, c in ipairs(clients) do
        table.insert(names, c.name)
    end
    return table.concat(names, ", ")
end

--- Format keymaps for display
--- @param keymaps table Array of keymap info
--- @return string Formatted string
local function format_keymaps(keymaps)
    if not keymaps or #keymaps == 0 then
        return "  (none found)"
    end

    local lines = {}
    for _, km in ipairs(keymaps) do
        local line = string.format("  %s: %s", km.lhs, km.desc or km.rhs or "(no description)")
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

--- Format diagnostic config for display
--- @param diag table Diagnostic info
--- @return string Formatted string
local function format_diagnostics(diag)
    if not diag then
        return "Unknown"
    end

    local parts = {}
    local config = diag.config or {}
    local counts = diag.counts or {}

    -- Current counts
    if counts.error > 0 or counts.warn > 0 or counts.info > 0 or counts.hint > 0 then
        table.insert(
            parts,
            string.format(
                "Current: %d errors, %d warnings, %d info, %d hints",
                counts.error,
                counts.warn,
                counts.info,
                counts.hint
            )
        )
    else
        table.insert(parts, "Current: No diagnostics in buffer")
    end

    -- Display settings
    local display = {}
    if config.virtual_text then
        table.insert(display, "virtual_text")
    end
    if config.signs then
        table.insert(display, "signs")
    end
    if config.underline then
        table.insert(display, "underline")
    end
    if config.float then
        table.insert(display, "float")
    end
    if #display > 0 then
        table.insert(parts, "Display: " .. table.concat(display, ", "))
    end

    return table.concat(parts, "\n  ")
end

--- Format linting info for display
--- @param linting table Linting info
--- @return string Formatted string
local function format_linting(linting)
    if not linting then
        return "Unknown"
    end

    local parts = {}

    if #(linting.plugins or {}) > 0 then
        table.insert(parts, "Plugins: " .. table.concat(linting.plugins, ", "))
    end
    if #(linting.linters or {}) > 0 then
        table.insert(parts, "Linters (this filetype): " .. table.concat(linting.linters, ", "))
    end
    if #(linting.formatters or {}) > 0 then
        table.insert(parts, "Formatters: " .. table.concat(linting.formatters, ", "))
    end

    if #parts == 0 then
        return "No linting plugins detected"
    end

    return table.concat(parts, "\n  ")
end

--- Format context object as detailed text for LLM
--- @param context table Context object from context.collect_for_query()
--- @return string Formatted context string
function M.format_context(context)
    local buf = context.buffer or {}
    local plugins = context.plugins or {}

    -- Build plugin list (categorized for relevance)
    local plugin_str = #plugins > 0 and table.concat(plugins, ", ") or "none detected"

    -- Build the full context
    local sections = {}

    -- Basic environment
    table.insert(
        sections,
        string.format(
            [[== ENVIRONMENT ==
Neovim: %s
Distribution: %s
Current file: %s (filetype: %s)
LSP servers: %s]],
            context.neovim_version or "unknown",
            context.distribution or "Custom",
            buf.filename or "unnamed",
            buf.filetype or "none",
            format_lsp_clients(context.lsp_clients)
        )
    )

    -- Diagnostics section
    table.insert(
        sections,
        string.format(
            [[== DIAGNOSTICS ==
  %s]],
            format_diagnostics(context.diagnostics)
        )
    )

    -- Linting section
    table.insert(
        sections,
        string.format(
            [[== LINTING/FORMATTING ==
  %s]],
            format_linting(context.linting)
        )
    )

    -- Relevant keymaps (the most important part!)
    if context.relevant_keymaps and #context.relevant_keymaps > 0 then
        table.insert(
            sections,
            string.format(
                [[== AVAILABLE KEYMAPS (matching user's question) ==
%s]],
                format_keymaps(context.relevant_keymaps)
            )
        )
    end

    -- Leader keymaps (sample)
    if context.leader_keymaps and #context.leader_keymaps > 0 then
        -- Only include first 30 to avoid token bloat
        local sample = {}
        for i = 1, math.min(30, #context.leader_keymaps) do
            table.insert(sample, context.leader_keymaps[i])
        end
        table.insert(
            sections,
            string.format(
                [[== LEADER KEYMAPS (user's custom bindings) ==
%s]],
                format_keymaps(sample)
            )
        )
    end

    -- Plugins (for context on what's available)
    table.insert(
        sections,
        string.format(
            [[== INSTALLED PLUGINS ==
%s]],
            plugin_str
        )
    )

    return table.concat(sections, "\n\n")
end

--- Build system prompt with injected pre-prompt and context
--- @param user_query string|nil Optional user query for query-specific context
--- @return string System prompt with preprompt and context
function M.build_system_prompt(user_query)
    local config = require("n00bkeys.config")
    local context_module = require("n00bkeys.context")
    local settings = require("n00bkeys.settings")

    -- Get template (custom or default)
    local template = config.options.prompt_template or M.DEFAULT_SYSTEM_PROMPT

    -- Gather context - use query-specific if we have a query
    local ctx
    if user_query and user_query ~= "" then
        ctx = context_module.collect_for_query(user_query)
    else
        ctx = context_module.collect()
    end

    local context_str = M.format_context(ctx)

    -- Get current pre-prompt
    local preprompt = settings.get_current_preprompt() or ""

    -- Inject both placeholders
    local prompt = template:gsub("{context}", context_str)
    prompt = prompt:gsub("{preprompt}", preprompt)

    return prompt
end

--- Build messages array for OpenAI API
--- @param user_query string User's question
--- @return table Messages array with system and user messages
function M.build_messages(user_query)
    -- Pass the query so we can get query-specific context
    local system_prompt = M.build_system_prompt(user_query)

    return {
        { role = "system", content = system_prompt },
        { role = "user", content = user_query },
    }
end

return M
