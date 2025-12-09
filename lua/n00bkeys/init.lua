--- *n00bkeys.nvim* AI-powered Neovim keybinding assistant
---
--- MIT License Copyright (c) 2025 Brandon Fryslie
---
--- ==============================================================================
---
--- Ask natural language questions about Neovim keybindings and get
--- context-aware responses powered by OpenAI GPT models.
---
--- # Setup ~
---
--- This plugin requires setup to be called before use:
--- >
---   require("n00bkeys").setup()
--- <
---
--- # Minimal Configuration ~
--- >
---   require("n00bkeys").setup({
---     -- Uses default configuration
---   })
--- <
---
--- # Custom Configuration ~
--- >
---   require("n00bkeys").setup({
---     openai_model = "gpt-4",
---     openai_max_tokens = 1000,
---     restore_conversation = "session", -- or "always" or "never"
---     keymaps = {
---       submit = "<CR>",
---       clear = "<C-c>",
---       focus = "<C-i>",
---       apply = "<C-a>",
---       close = "<Esc>",
---       new_conversation = "<C-n>",
---     },
---     prompt_template = [[You are a Neovim expert.
---
--- {context}
---
--- Provide concise keybinding help.]],
---   })
--- <
---
--- # Usage ~
---
--- Open the n00bkeys floating window:
--- >
---   :Noobkeys
---   " or use the short alias:
---   :Nk
--- <
---
--- In the window:
--- - Type your question (placeholder text auto-clears when typing)
--- - Press `<CR>` to submit your query
--- - Press `<M-CR>` or `<A-CR>` to insert a newline (for multi-line prompts)
--- - See AI-powered response
---
--- # Keybindings ~
---
--- In n00bkeys window (all customizable):
--- - `<CR>` - Submit query to OpenAI (works in normal and insert mode)
--- - `<M-CR>` / `<A-CR>` - Insert newline in insert mode (for multi-line prompts)
--- - `<C-c>` - Clear prompt and response (normal mode)
--- - `<C-i>` - Focus prompt (enter insert mode)
--- - `<C-a>` - Apply last response to prompt (normal mode)
--- - `<C-n>` - Start a new conversation (clears current and starts fresh)
--- - `<Esc>` / `q` - Close window (normal mode)
---
--- # Configuration Options ~
---
--- API Key Setup:
--- Set OPENAI_API_KEY environment variable or create .env file
---
--- Available options:
--- - `openai_model` (string) - OpenAI model to use (default: "gpt-4o-mini")
--- - `openai_max_tokens` (number) - Max tokens in response (default: 500)
--- - `openai_temperature` (number) - Temperature for responses (default: 0.7)
--- - `openai_timeout` (number) - Request timeout in seconds (default: 30)
--- - `openai_api_key` (string|nil) - API key (use env var instead)
--- - `keymaps` (table) - Custom keybindings
--- - `prompt_template` (string|nil) - Custom system prompt template
--- - `debug` (boolean) - Enable debug logging (default: false)
--- - `restore_conversation` (string) - Conversation restore mode:
---   - "session" - Restore within Neovim session (default)
---   - "always" - Restore across Neovim restarts
---   - "never" - Always start fresh
---
--- # Context-Aware Responses ~
---
--- n00bkeys automatically detects:
--- - Neovim version
--- - Distribution (LazyVim, NvChad, AstroNvim, or Custom)
--- - Installed plugins (top 10 from lazy.nvim)
---
--- This context is included in queries to provide relevant responses.
---
--- # See Also ~
---
--- - OpenAI API: https://platform.openai.com/
--- - Source: https://github.com/brandon-fryslie/n00bkeys
--- - Report bugs: https://github.com/brandon-fryslie/n00bkeys/issues
---
---@tag n00bkeys

if _G.n00bkeysLoaded then
    return
end

local main = require("n00bkeys.main")
local config = require("n00bkeys.config")

local n00bkeys = {}

--- Setup n00bkeys plugin
---
--- This function initializes the plugin with the provided configuration.
--- It must be called before using n00bkeys.
---
--- Example: ~
--- >
---   require("n00bkeys").setup({
---     openai_model = "gpt-4o-mini",
---     openai_max_tokens = 500,
---     openai_temperature = 0.7,
---     keymaps = {
---       submit = "<CR>",
---       clear = "<C-c>",
---       focus = "<C-i>",
---       apply = "<C-a>",
---       close = "<Esc>",
---     },
---     prompt_template = "Custom prompt: {context}",
---   })
--- <
---
---@param opts table|nil Configuration options
---@field openai_model string OpenAI model to use (default: "gpt-4o-mini")
---@field openai_max_tokens number Max response tokens (default: 500)
---@field openai_temperature number Response creativity 0-1 (default: 0.7)
---@field openai_timeout number Request timeout in seconds (default: 30)
---@field openai_api_key string|nil API key (use env var instead)
---@field keymaps table Custom keybindings
---@field keymaps.submit string Submit query keybinding (default: "<CR>")
---@field keymaps.clear string Clear prompt keybinding (default: "<C-c>")
---@field keymaps.focus string Focus prompt keybinding (default: "<C-i>")
---@field keymaps.apply string Apply response keybinding (default: "<C-a>")
---@field keymaps.close string Close window keybinding (default: "<Esc>")
---@field keymaps.new_conversation string Start new conversation keybinding (default: "<C-n>")
---@field prompt_template string|nil Custom system prompt template
---@field debug boolean Enable debug logging (default: false)
---@field restore_conversation string Conversation restore mode: "session", "always", or "never" (default: "session")
---
---@tag n00bkeys.setup
function n00bkeys.setup(opts)
    local log = require("n00bkeys.util.log")

    _G.n00bkeys.config = config.setup(opts)

    log.debug("init.setup", "Registering Noobkeys command")

    -- Command handler shared by both commands
    local function command_handler()
        log.debug("init.command", "Command invoked")

        -- Check for vim errors before proceeding
        local errmsg_before = vim.v.errmsg
        if errmsg_before and errmsg_before ~= "" then
            log.error("init.command", "Pre-existing vim error: %s", errmsg_before)
        end

        require("n00bkeys.ui").open()

        -- Check for vim errors after opening
        local errmsg_after = vim.v.errmsg
        if errmsg_after and errmsg_after ~= "" and errmsg_after ~= errmsg_before then
            log.error("init.command", "Vim error occurred: %s", errmsg_after)
        end
    end

    -- Register the main command
    vim.api.nvim_create_user_command("Noobkeys", command_handler, {
        nargs = 0,
        desc = "Open n00bkeys AI keybinding assistant",
    })

    -- Register the short alias
    vim.api.nvim_create_user_command("Nk", command_handler, {
        nargs = 0,
        desc = "Open n00bkeys AI keybinding assistant (alias)",
    })

    log.debug("init.setup", "Command registration complete")

    -- Verify commands were registered successfully
    local commands = vim.api.nvim_get_commands({})
    if commands["Noobkeys"] and commands["Nk"] then
        log.debug("init.setup", "Commands verified: Noobkeys and Nk")
    else
        if not commands["Noobkeys"] then
            log.error("init.setup", "Noobkeys command NOT found in command list")
        end
        if not commands["Nk"] then
            log.error("init.setup", "Nk command NOT found in command list")
        end
    end
end

--- Enable n00bkeys
---
--- Opens the n00bkeys floating window.
--- This is typically called via the :n00bkeys command.
---
--- Example: ~
--- >
---   require("n00bkeys").enable()
--- <
---
---@param scope string|nil Internal scope parameter (for testing)
---
---@tag n00bkeys.enable
function n00bkeys.enable(scope)
    if _G.n00bkeys.config == nil then
        _G.n00bkeys.config = config.options
    end

    main.toggle(scope or "public_api_enable")
end

--- Disable n00bkeys
---
--- Closes the n00bkeys floating window.
---
--- Example: ~
--- >
---   require("n00bkeys").disable()
--- <
---
---@tag n00bkeys.disable
function n00bkeys.disable()
    main.toggle("public_api_disable")
end

--- Toggle n00bkeys window
---
--- Opens or closes the n00bkeys window depending on current state.
---
--- Example: ~
--- >
---   require("n00bkeys").toggle()
--- <
---
---@tag n00bkeys.toggle
function n00bkeys.toggle()
    if _G.n00bkeys.config == nil then
        _G.n00bkeys.config = config.options
    end

    main.toggle("public_api_toggle")
end

_G.n00bkeys = n00bkeys

_G.n00bkeysLoaded = true

return _G.n00bkeys
