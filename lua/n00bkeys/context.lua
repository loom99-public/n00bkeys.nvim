-- Context gathering module for n00bkeys
-- Collects rich system information to enhance LLM prompts with actionable context

local M = {}

-- Cache context for session (only gather once per buffer/filetype combo)
M._cache = nil
M._cache_key = nil

--- Get Neovim version string
--- @return string Neovim version (e.g., "0.10.0")
function M.get_neovim_version()
    local v = vim.version()
    return string.format("%d.%d.%d", v.major, v.minor, v.patch)
end

--- Detect Neovim distribution/starter pack
--- @return string Distribution name ("LazyVim", "NvChad", "AstroNvim", "LunarVim", or "Custom")
function M.detect_distribution()
    -- Check for LazyVim
    if vim.g.lazyvim_version then
        return "LazyVim"
    end

    -- Check for NvChad
    if vim.g.nvchad_version then
        return "NvChad"
    end

    -- Check for AstroNvim
    if vim.g.astronvim_version then
        return "AstroNvim"
    end

    -- Check for LunarVim
    if vim.g.lunarvim_version then
        return "LunarVim"
    end

    return "Custom"
end

--- Get list of installed plugins (all of them, not just 10)
--- @return table Array of plugin names
function M.get_plugin_list()
    local plugins = {}

    -- Try lazy.nvim first (most common)
    local has_lazy, lazy = pcall(require, "lazy")
    if has_lazy then
        local plugin_specs = lazy.plugins()
        for _, spec in ipairs(plugin_specs or {}) do
            if spec.name then
                table.insert(plugins, spec.name)
            end
        end
        return plugins
    end

    -- Try packer.nvim
    local has_packer, packer = pcall(require, "packer")
    if has_packer and packer.plugins then
        for name, _ in pairs(packer.plugins) do
            table.insert(plugins, name)
        end
        return plugins
    end

    return plugins
end

--- Get active LSP clients for current buffer
--- @return table Array of LSP client info {name, root_dir, capabilities}
function M.get_lsp_clients()
    local clients = {}
    local buf = vim.api.nvim_get_current_buf()

    -- Use newer API if available, fall back to deprecated
    local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
    local active = get_clients({ bufnr = buf })

    for _, client in ipairs(active or {}) do
        table.insert(clients, {
            name = client.name,
            root_dir = client.config and client.config.root_dir or nil,
        })
    end

    return clients
end

--- Get current diagnostic configuration
--- @return table Diagnostic config
function M.get_diagnostic_config()
    local config = vim.diagnostic.config() or {}
    return {
        virtual_text = config.virtual_text and true or false,
        signs = config.signs and true or false,
        underline = config.underline and true or false,
        update_in_insert = config.update_in_insert and true or false,
        float = config.float and true or false,
    }
end

--- Get diagnostic counts for current buffer
--- @return table Counts by severity
function M.get_diagnostic_counts()
    local buf = vim.api.nvim_get_current_buf()
    local diagnostics = vim.diagnostic.get(buf)
    local counts = { error = 0, warn = 0, info = 0, hint = 0 }

    for _, d in ipairs(diagnostics) do
        if d.severity == vim.diagnostic.severity.ERROR then
            counts.error = counts.error + 1
        elseif d.severity == vim.diagnostic.severity.WARN then
            counts.warn = counts.warn + 1
        elseif d.severity == vim.diagnostic.severity.INFO then
            counts.info = counts.info + 1
        elseif d.severity == vim.diagnostic.severity.HINT then
            counts.hint = counts.hint + 1
        end
    end

    return counts
end

--- Get keymaps matching a pattern (for relevant context)
--- @param patterns table Array of patterns to match in lhs or desc
--- @return table Array of keymap info
function M.get_relevant_keymaps(patterns)
    local keymaps = {}
    local modes = { "n", "v", "i" }
    local seen = {}

    for _, mode in ipairs(modes) do
        local maps = vim.api.nvim_get_keymap(mode)
        -- Also get buffer-local keymaps
        local ok, buf_maps = pcall(vim.api.nvim_buf_get_keymap, 0, mode)
        if ok then
            for _, m in ipairs(buf_maps) do
                table.insert(maps, m)
            end
        end

        for _, map in ipairs(maps) do
            local lhs = map.lhs or ""
            local desc = map.desc or ""
            local rhs = map.rhs or (map.callback and "[lua function]") or ""

            -- Check if this keymap matches any pattern
            for _, pattern in ipairs(patterns) do
                local pat_lower = pattern:lower()
                if
                    lhs:lower():find(pat_lower, 1, true)
                    or desc:lower():find(pat_lower, 1, true)
                    or rhs:lower():find(pat_lower, 1, true)
                then
                    local key = mode .. ":" .. lhs
                    if not seen[key] then
                        seen[key] = true
                        table.insert(keymaps, {
                            mode = mode,
                            lhs = lhs,
                            desc = desc ~= "" and desc or nil,
                            rhs = type(rhs) == "string" and rhs:sub(1, 80) or nil,
                        })
                    end
                    break
                end
            end
        end
    end

    return keymaps
end

--- Get all leader keymaps (most useful for users)
--- @return table Array of leader keymap info
function M.get_leader_keymaps()
    local keymaps = {}
    local modes = { "n", "v" }
    local seen = {}
    local leader = vim.g.mapleader or "\\"

    for _, mode in ipairs(modes) do
        local maps = vim.api.nvim_get_keymap(mode)
        local ok, buf_maps = pcall(vim.api.nvim_buf_get_keymap, 0, mode)
        if ok then
            for _, m in ipairs(buf_maps) do
                table.insert(maps, m)
            end
        end

        for _, map in ipairs(maps) do
            local lhs = map.lhs or ""
            -- Match <leader> or the actual leader key
            if
                lhs:match("^<[Ll]eader>")
                or lhs:match("^" .. vim.pesc(leader))
                or lhs:match("^ ")
            then
                local desc = map.desc or ""
                local key = mode .. ":" .. lhs
                if not seen[key] then
                    seen[key] = true
                    table.insert(keymaps, {
                        mode = mode,
                        lhs = lhs,
                        desc = desc ~= "" and desc or nil,
                    })
                end
            end
        end
    end

    -- Sort by lhs for readability
    table.sort(keymaps, function(a, b)
        return a.lhs < b.lhs
    end)

    return keymaps
end

--- Get current buffer/file context
--- @return table Buffer context info
function M.get_buffer_context()
    local buf = vim.api.nvim_get_current_buf()
    return {
        filetype = vim.bo[buf].filetype,
        buftype = vim.bo[buf].buftype,
        filename = vim.fn.expand("%:t"),
        -- Check if file has a specific linter configured
        shiftwidth = vim.bo[buf].shiftwidth,
        expandtab = vim.bo[buf].expandtab,
    }
end

--- Check for common linting/formatting plugins and their status
--- @return table Linting plugin info
function M.get_linting_info()
    local info = {
        plugins = {},
        formatters = {},
        linters = {},
    }

    -- Check for none-ls/null-ls
    local has_null_ls, null_ls = pcall(require, "null-ls")
    if has_null_ls then
        table.insert(info.plugins, "null-ls/none-ls")
        -- Try to get registered sources
        local ok, sources = pcall(function()
            return null_ls.get_sources()
        end)
        if ok and sources then
            for _, source in ipairs(sources) do
                if source.name then
                    if source.methods and source.methods[require("null-ls").methods.FORMATTING] then
                        table.insert(info.formatters, source.name)
                    else
                        table.insert(info.linters, source.name)
                    end
                end
            end
        end
    end

    -- Check for nvim-lint
    local has_lint, lint = pcall(require, "lint")
    if has_lint then
        table.insert(info.plugins, "nvim-lint")
        local ft = vim.bo.filetype
        if lint.linters_by_ft and lint.linters_by_ft[ft] then
            for _, linter in ipairs(lint.linters_by_ft[ft]) do
                table.insert(info.linters, linter)
            end
        end
    end

    -- Check for conform.nvim
    local has_conform, conform = pcall(require, "conform")
    if has_conform then
        table.insert(info.plugins, "conform.nvim")
        local ok, formatters = pcall(function()
            return conform.list_formatters()
        end)
        if ok and formatters then
            for _, f in ipairs(formatters) do
                if f.name then
                    table.insert(info.formatters, f.name)
                end
            end
        end
    end

    -- Check for trouble.nvim
    local has_trouble = pcall(require, "trouble")
    if has_trouble then
        table.insert(info.plugins, "trouble.nvim")
    end

    return info
end

--- Get which-key mappings if available
--- @return table|nil Which-key mappings or nil
function M.get_which_key_mappings()
    local has_wk, wk = pcall(require, "which-key")
    if not has_wk then
        return nil
    end

    -- which-key v3 API
    local ok, keys = pcall(function()
        return wk.get_mappings("n", "", {})
    end)
    if ok and keys then
        local mappings = {}
        for _, key in ipairs(keys) do
            if key.desc then
                table.insert(mappings, {
                    lhs = key.lhs or key.keys or "",
                    desc = key.desc,
                })
            end
        end
        return mappings
    end

    return nil
end

--- Gather all context (cached per buffer/filetype)
--- @return table Full context object
function M.collect()
    local buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype
    local cache_key = buf .. ":" .. ft

    -- Return cache if same buffer/filetype
    if M._cache and M._cache_key == cache_key then
        return M._cache
    end

    -- Gather fresh context
    M._cache = {
        neovim_version = M.get_neovim_version(),
        distribution = M.detect_distribution(),
        plugins = M.get_plugin_list(),
        buffer = M.get_buffer_context(),
        lsp_clients = M.get_lsp_clients(),
        diagnostics = {
            config = M.get_diagnostic_config(),
            counts = M.get_diagnostic_counts(),
        },
        linting = M.get_linting_info(),
        leader_keymaps = M.get_leader_keymaps(),
    }
    M._cache_key = cache_key

    return M._cache
end

--- Get context relevant to a specific query
--- @param query string The user's question
--- @return table Context filtered/augmented for the query
function M.collect_for_query(query)
    local base = M.collect()
    local query_lower = query:lower()

    -- Add query-specific keymaps based on keywords
    local patterns = {}

    -- Detect query topics and add relevant keymap patterns
    if
        query_lower:find("lint")
        or query_lower:find("warn")
        or query_lower:find("error")
        or query_lower:find("diagnostic")
    then
        vim.list_extend(
            patterns,
            { "diagnostic", "lint", "trouble", "error", "warn", "quickfix", "loclist" }
        )
    end
    if query_lower:find("format") then
        vim.list_extend(patterns, { "format", "conform", "prettier", "eslint" })
    end
    if
        query_lower:find("lsp")
        or query_lower:find("definition")
        or query_lower:find("reference")
    then
        vim.list_extend(patterns, { "lsp", "definition", "reference", "hover", "rename", "action" })
    end
    if query_lower:find("search") or query_lower:find("find") or query_lower:find("grep") then
        vim.list_extend(patterns, { "search", "find", "grep", "telescope", "fzf" })
    end
    if query_lower:find("git") or query_lower:find("commit") or query_lower:find("diff") then
        vim.list_extend(patterns, { "git", "fugitive", "gitsigns", "diff", "blame", "commit" })
    end
    if
        query_lower:find("buffer")
        or query_lower:find("tab")
        or query_lower:find("window")
        or query_lower:find("split")
    then
        vim.list_extend(patterns, { "buffer", "tab", "window", "split", "close" })
    end
    if query_lower:find("save") or query_lower:find("write") or query_lower:find("quit") then
        vim.list_extend(patterns, { "save", "write", "quit", "close" })
    end

    -- Always include some patterns if none detected
    if #patterns == 0 then
        patterns = { "leader" }
    end

    base.relevant_keymaps = M.get_relevant_keymaps(patterns)

    return base
end

--- Clear cached context (useful for testing or forcing refresh)
function M.clear_cache()
    M._cache = nil
    M._cache_key = nil
end

return M
