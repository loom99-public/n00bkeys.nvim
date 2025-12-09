# Changelog

All notable changes to n00bkeys will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-16

### Added

#### Core Features
- Floating window UI for natural language queries about Neovim keybindings
- OpenAI API integration with GPT-4o-mini (configurable model)
- Context-aware prompts that include:
  - Neovim version detection
  - Distribution detection (LazyVim, NvChad, AstroNvim, LunarVim, Custom)
  - Top 10 installed plugins enumeration (from lazy.nvim)
  - Operating system information

#### User Interface
- Multi-state rendering: prompt, loading, response, and error states
- Clean floating window with rounded borders
- Helpful error messages with actionable feedback
- Loading indicator during API requests (static text)
- Title bar with plugin name

#### Keybindings
- `<CR>` - Submit query to OpenAI
- `<C-c>` - Clear prompt and response
- `<C-i>` - Focus prompt (enter insert mode)
- `<C-a>` - Apply last response to prompt for follow-up questions
- `<Esc>` - Close window

All keybindings are customizable via configuration.

#### Configuration
- Customizable OpenAI model selection (gpt-4, gpt-4o-mini, gpt-3.5-turbo, etc.)
- Configurable max tokens and temperature
- Custom keybindings support
- Custom system prompt templates
- API key support via environment variable, .env file, or config
- Debug logging option

#### Developer Experience
- Comprehensive test suite (50 tests, 100% pass rate)
- Mini.test framework integration
- Clean modular architecture (11 modules)
- Async-correct implementation (non-blocking UI)
- Support for Neovim 0.9.5+
- Generated Vim help documentation (`:help n00bkeys`)
- CI/CD with GitHub Actions

### Technical Details

#### Modules
- `context.lua` - System context collection and caching
- `prompt.lua` - Context-aware prompt template system
- `openai.lua` - OpenAI API client with error handling
- `http.lua` - Async HTTP client (vim.system/vim.loop)
- `ui.lua` - Floating window and buffer management
- `keymaps.lua` - Keybinding configuration
- `config.lua` - Configuration management with validation
- `main.lua` - Internal toggle logic
- `state.lua` - Internal state management
- `init.lua` - Public API (setup, enable, disable, toggle)
- `util/log.lua` - Logging utilities

#### Error Handling
- Graceful handling of missing API keys
- Network timeout management (30s default)
- OpenAI rate limit retry with exponential backoff
- Clear error messages in UI
- Fallback support for older Neovim versions

#### Testing
- 50 automated tests across all modules
- Integration tests for E2E workflows
- Mocked HTTP responses for reliable testing
- Context collection tests
- Prompt template tests
- Keybinding tests
- 100% pass rate

### Features

- Ask natural language questions about Neovim keybindings
- Get responses tailored to your specific Neovim environment
- Works seamlessly with LazyVim, NvChad, AstroNvim, and custom configs
- Context-aware responses based on your setup
- Multi-turn conversations with apply-response feature
- Session-based context caching for efficiency

### Credits

- Built with [mini.nvim](https://github.com/echasnovski/mini.nvim) by [@echasnovski](https://github.com/echasnovski)
- Powered by [OpenAI](https://openai.com/) GPT models
- Inspired by the Neovim community's commitment to learning

### Known Limitations

- Loading indicator is static text (animated spinner planned for v1.1.0)
- Plugin detection only supports lazy.nvim (packer.nvim support planned)
- Requires internet connection and OpenAI API key
- Context collection limited to top 10 plugins

## [Unreleased]

### Planned Features

- Animated loading spinner
- Conversation history (multi-turn context preservation)
- Offline mode / local LLM support (Ollama integration)
- Plugin-specific deep context (e.g., telescope.nvim specific help)
- packer.nvim plugin detection
- Markdown response rendering
- Multi-language support
- Usage analytics (opt-in)

[1.0.0]: https://github.com/brandon-fryslie/n00bkeys/releases/tag/v1.0.0
