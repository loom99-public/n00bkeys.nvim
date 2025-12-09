# n00bkeys

> Learn Neovim keybindings with AI-powered assistance

An intelligent Neovim plugin that helps you discover keybindings through natural language queries. Powered by OpenAI, it provides context-aware responses based on your Neovim configuration.

## Features

- Ask questions in natural language about Neovim keybindings
- Get context-aware responses based on your environment
- Works with LazyVim, NvChad, AstroNvim, and custom configs
- Floating window UI with intuitive keybindings
- Customizable prompts and keymaps
- Async OpenAI integration (non-blocking)

## Requirements

- Neovim 0.9.5+
- curl (for HTTP requests)
- OpenAI API key

## Installation

### lazy.nvim (recommended)

```lua
{
  "brandon-fryslie/n00bkeys",
  config = function()
    require("n00bkeys").setup({
      -- Optional: customize configuration
      keymaps = {
        submit = "<CR>",
        clear = "<C-c>",
        focus = "<C-i>",
        apply = "<C-a>",
        close = "<Esc>",
      },
    })
  end,
}
```

### packer.nvim

```lua
use {
  "brandon-fryslie/n00bkeys",
  config = function()
    require("n00bkeys").setup()
  end,
}
```

### vim-plug

```vim
Plug 'brandon-fryslie/n00bkeys'

lua << EOF
  require("n00bkeys").setup()
EOF
```

## Quick Start

1. **Set up OpenAI API key:**
   ```bash
   export OPENAI_API_KEY="sk-your-api-key-here"
   ```

   Or create a `.env` file in your project root:
   ```
   OPENAI_API_KEY=sk-your-api-key-here
   ```

2. **Open n00bkeys:**
   ```vim
   :Noobkeys
   " or use the short alias:
   :Nk
   ```

3. **Ask a question:**
   ```
   Type: "how do I save a file?"
   Press: <CR> to submit

   For multi-line prompts:
   Press: <M-CR> or <A-CR> to insert newlines
   Press: <CR> when ready to submit
   ```

4. **Get your answer!**
   ```
   Response: Use :w to save the current file
   ```

## Keybindings

In the n00bkeys floating window:

| Key | Action |
|-----|--------|
| `<CR>` | Submit your query |
| `<C-c>` | Clear prompt and response |
| `<C-i>` | Focus prompt (enter insert mode) |
| `<C-a>` | Apply last response to prompt |
| `<Esc>` | Close the window |

All keybindings are customizable via `setup()`.

## Configuration

### Default Configuration

```lua
require("n00bkeys").setup({
  debug = false,

  -- OpenAI settings
  openai_model = "gpt-4o-mini",
  openai_max_tokens = 500,
  openai_temperature = 0.7,
  openai_timeout = 30,
  openai_api_key = nil, -- Use env var instead

  -- Keybindings (customize as needed)
  keymaps = {
    submit = "<CR>",
    clear = "<C-c>",
    focus = "<C-i>",
    apply = "<C-a>",
    close = "<Esc>",
  },

  -- Custom system prompt template (optional)
  prompt_template = nil,
})
```

### Custom Keybindings Example

```lua
require("n00bkeys").setup({
  keymaps = {
    submit = "<leader>s",
    clear = "<leader>c",
    focus = "<leader>f",
    apply = "<leader>a",
    close = "q",
  },
})
```

### Using GPT-4 Instead of GPT-4o-mini

```lua
require("n00bkeys").setup({
  openai_model = "gpt-4",
  openai_max_tokens = 1000,
})
```

### Custom System Prompt

```lua
require("n00bkeys").setup({
  prompt_template = [[You are a Neovim expert assistant.
Help users learn Neovim by providing clear, concise answers.
Focus on practical keybindings and commands.

User's Environment:
{context}

Keep responses under 150 words.]],
})
```

## API Key Setup

n00bkeys requires an OpenAI API key. There are three ways to provide it:

### 1. Environment Variable (Recommended)

```bash
export OPENAI_API_KEY="sk-your-api-key-here"
```

Add to your `~/.bashrc`, `~/.zshrc`, or equivalent.

### 2. Project .env File

Create a `.env` file in your project root:
```
OPENAI_API_KEY=sk-your-api-key-here
```

**Important:** Add `.env` to your `.gitignore` to avoid committing your API key!

### 3. Configuration (Not Recommended)

```lua
require("n00bkeys").setup({
  openai_api_key = "sk-your-api-key-here", -- Don't commit this!
})
```

**Warning:** Never commit your API key to version control!

## Usage Examples

### Basic Query

```
Q: "how do I switch between windows?"
A: Use <C-w>w to cycle through windows, or <C-w>h/j/k/l to move directionally.
```

### Distribution-Aware Response

If you're using LazyVim:
```
Q: "how do I open the file explorer?"
A: In LazyVim, use <leader>e to toggle Neo-tree file explorer.
```

### Multi-Turn Conversation

1. Ask: "how do I delete a line?"
2. Get: "Use dd in normal mode"
3. Press `<C-a>` to copy response to prompt
4. Ask: "what about deleting multiple lines?"
5. Get context-aware follow-up answer

## Troubleshooting

### "OPENAI_API_KEY not found" Error

**Solution:** Set your API key using one of the methods above.

```bash
export OPENAI_API_KEY="sk-your-key"
```

### "curl not found" Error

**Solution:** Install curl:
```bash
# macOS
brew install curl

# Ubuntu/Debian
sudo apt-get install curl

# Arch Linux
sudo pacman -S curl
```

### Slow Responses

**Cause:** Network latency or OpenAI API load

**Solutions:**
- Use a faster model: `openai_model = "gpt-3.5-turbo"`
- Reduce max tokens: `openai_max_tokens = 300`
- Check your internet connection

### Window Doesn't Open

**Solution:** Check for errors:
```vim
:messages
```

Common issues:
- Plugin not installed correctly
- Neovim version too old (requires 0.9.5+)

### Rate Limit Errors

**Cause:** Too many requests to OpenAI API

**Solution:** Wait a moment and try again. n00bkeys automatically handles rate limits with exponential backoff.

## Development

### Running Tests

```bash
make deps  # Install test dependencies
make test  # Run all tests
```

### Linting

```bash
make lint  # Run stylua and luacheck
```

### Documentation

```bash
make documentation  # Generate help docs
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`make test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Guidelines

- Write tests for new features
- Follow existing code style
- Update documentation
- Keep commits focused and descriptive

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [mini.nvim](https://github.com/echasnovski/mini.nvim) for testing and documentation
- Powered by [OpenAI](https://openai.com/) GPT models
- Inspired by the Neovim community's commitment to learning

## See Also

- [Neovim Documentation](https://neovim.io/doc/)
- [LazyVim](https://www.lazyvim.org/)
- [NvChad](https://nvchad.com/)
- [AstroNvim](https://astronvim.com/)
