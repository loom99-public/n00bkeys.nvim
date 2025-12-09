# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**n00bkeys** is a production-ready Neovim plugin that helps users discover keybindings through AI-powered natural language queries. Users type questions like "how do I save a file?" and receive context-aware responses from OpenAI based on their Neovim environment (version, distribution, installed plugins).

**Status:** v1.0.0 - Feature complete and fully tested (80 passing tests, 100% coverage of user workflows)

**Commands:** `:Noobkeys` (main), `:Nk` (alias)

## Development Commands

```bash
# Install test dependencies (mini.nvim)
make deps

# Run all tests (no API key required - uses mocked HTTP)
make test

# Run tests on specific Neovim versions (requires bob)
make test-nightly
make test-0.8.3

# Format and lint
make lint

# Generate help documentation from code annotations
make documentation

# Static analysis
make luals

# Run all checks (documentation, lint, luals, test)
make all
```

## Plugin Architecture

### Module Organization

The codebase follows standard Neovim plugin structure with clear separation of concerns:

```
lua/n00bKeys/
├── init.lua       - Public API (setup, enable, disable, toggle)
├── main.lua       - Internal toggle/state coordination
├── config.lua     - Configuration management and validation
├── state.lua      - Global plugin state (enabled/disabled tracking)
├── ui.lua         - Floating window UI and buffer management
├── keymaps.lua    - Keymap registration for n00bkeys window
├── openai.lua     - OpenAI API client
├── http.lua       - Async HTTP client using curl
├── prompt.lua     - System prompt generation with context
├── context.lua    - Environment detection (nvim version, distro, plugins)
└── util/log.lua   - Debug logging utilities
```

### Data Flow

1. **User Command** → `:Noobkeys` or `:Nk` calls `ui.open()`
2. **UI Open** → `ui.open()` creates floating window and buffer
3. **Keymaps Setup** → `keymaps.setup()` registers buffer-local keybindings
4. **User Query** → User types question and presses `<CR>` → `ui.submit_query()`
5. **Prompt Augmentation** → `prompt.build_system_prompt()` adds context from `context.gather()`
6. **API Call** → `openai.query()` → `http.post()` (async curl)
7. **Response Display** → Callback updates buffer via `ui.set_response()` or `ui.set_error()`
8. **State Tracking** → `ui.state.last_response` stored for apply action

### Key Design Decisions

**Async HTTP**: Uses `vim.loop.spawn` with curl for non-blocking API calls. All callbacks use `vim.schedule()` for thread safety.

**UI State Management**: `ui.state` tracks window/buffer IDs, loading state, last response. Singleton pattern - only one window at a time.

**Context Detection**:
- Neovim version: `vim.version()`
- Distribution: Detects LazyVim/NvChad/AstroNvim by config files
- Plugins: Queries lazy.nvim for installed plugins

**API Key Priority**:
1. `OPENAI_API_KEY` environment variable
2. `.env` file in cwd
3. `openai_api_key` config option (not recommended)

**Buffer Layout**:
```
Line 0: [User prompt here]
Line 1: [empty]
Line 2: Loading... / Response: <text> / Error: <text>
Lines 3+: [multi-line response continues]
```

## Testing Philosophy

Tests follow a strict **workflow-first, anti-gaming** approach documented in `tests/TESTING_STRATEGY.md`.

**IMPORTANT:** See `tests/TESTING_GAPS_ANALYSIS.md` for lessons learned about testing gaps at the Vim command layer. When modifying Ex commands or adding Vimscript integration, read that document first.

### Core Principles

1. **Test Complete Workflows**: Never test isolated functions - test entire user journeys
2. **Mock Only External APIs**: HTTP calls are mocked, everything else is real
3. **Verify Observable Outcomes**: Check buffer content users see, not internal state
4. **Resist Gaming**: Tests must fail if implementation is stubbed/incomplete
5. **Test All User-Facing Interfaces**: Test both Lua API (`require("n00bkeys").enable()`) and Ex commands (`:N00bkeys`) separately

### Test Structure

All tests use `mini.test` with child Neovim processes:
- Each test calls `child.restart()` for clean slate
- HTTP mocked via `setup_mock_success()` / `setup_mock_error()`
- Helpers in `tests/helpers.lua` for assertions and buffer inspection
- 100% passing without any API key or manual setup

### Running Specific Tests

```bash
# Single test file
nvim --headless --noplugin -u ./scripts/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/test_user_workflows.lua')"

# All tests
make test
```

### Test Categories

- **User Workflows** (24 tests): Complete user journeys from open → query → response
- **Integration** (4 tests): Full flow with real module interaction
- **Component Tests** (47 tests): UI, OpenAI, Keymaps, HTTP, Config, Context, etc.

## Common Modification Patterns

### Adding a New Keybinding

1. Update `config.lua` default options with new keymap
2. Add keymap registration in `keymaps.lua:setup_keymaps()`
3. Implement handler function in `ui.lua`
4. Add workflow test in `tests/test_user_workflows.lua`
5. Update documentation in `init.lua` header comments
6. Run `make documentation` to regenerate help

### Changing OpenAI Model/Parameters

Configuration in `config.lua:options`:
- `openai_model` - Model name (default: "gpt-4o-mini")
- `openai_max_tokens` - Max response length (default: 500)
- `openai_temperature` - Creativity 0-1 (default: 0.7)
- `openai_timeout` - Request timeout seconds (default: 30)

### Modifying System Prompt

Edit `prompt.lua:build_system_prompt()`. Context variables available:
- `nvim_version` - From `context.get_neovim_version()`
- `distribution` - From `context.detect_distribution()`
- `plugins` - From `context.get_plugins()`

### Adding New Context Detection

1. Add detection function in `context.lua` (e.g., `get_colorscheme()`)
2. Call from `context.gather()` and add to returned table
3. Use in `prompt.lua:build_system_prompt()`
4. Add test in `tests/test_context.lua`

## Debugging

Enable debug logging:
```lua
require("n00bkeys").setup({ debug = true })
```

View logs:
```vim
:messages
```

Log locations in code:
- `log.debug(module_name, format, ...)` - Only if debug enabled
- `log.error(module_name, format, ...)` - Always logged

## Global State

Plugin stores state in `_G.n00bkeys`:
```lua
_G.n00bkeys = {
  config = { ... },      -- From config.setup()
  is_enabled = bool,     -- From state.lua
}
```

UI state in `require("n00bkeys.ui").state`:
```lua
{
  win_id = number,
  buf_id = number,
  is_loading = boolean,
  last_error = string,
  last_response = string,
}
```

## Documentation Generation

Uses `mini.doc` to generate `doc/n00bkeys.txt` from Lua annotations:
- Tag format: `---@tag tagname`
- Section format: `--- Section Name ~`
- Code examples: `--- >`...`--- <`
- Dynamic content: `---@eval return "text"`

After modifying annotations, run `make documentation` to regenerate help file.

## Important Constraints

- **Neovim 0.9.5+ required** for floating window API
- **curl required** for HTTP requests
- **No external Lua dependencies** (pure Lua + Neovim stdlib)
- **Single window policy** - ui.open() focuses existing window if open
- **Thread safety** - All async callbacks wrapped in `vim.schedule()`
- **No plugin manager assumptions** - Works with lazy.nvim, packer, vim-plug, manual install
