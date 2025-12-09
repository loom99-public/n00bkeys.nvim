-- Keybinding management for n00bkeys
-- Sets up buffer-local keymaps for the n00bkeys window

local M = {}

--- Setup all keymaps for the n00bkeys buffer
--- @param buf_id number Buffer ID to attach keymaps to
function M.setup_keymaps(buf_id)
    local config = require("n00bkeys.config")
    local ui = require("n00bkeys.ui")

    local keymaps = config.options.keymaps or {}
    local opts = { buffer = buf_id, noremap = true, silent = true }

    -- Tab navigation (works in all tabs)
    vim.keymap.set("n", keymaps.next_tab or "<Tab>", function()
        ui.switch_to_next_tab()
    end, vim.tbl_extend("force", opts, { desc = "Next tab" }))

    vim.keymap.set("n", keymaps.prev_tab or "<S-Tab>", function()
        ui.switch_to_prev_tab()
    end, vim.tbl_extend("force", opts, { desc = "Previous tab" }))

    -- Direct tab jumps (1-5)
    for i = 1, 5 do
        local keymap_key = "tab_" .. i
        vim.keymap.set("n", keymaps[keymap_key] or tostring(i), function()
            ui.switch_to_tab_by_index(i)
        end, vim.tbl_extend("force", opts, { desc = "Jump to tab " .. i }))
    end

    -- Context-aware Enter key
    -- In query tab: submit query
    -- In history tab: load history item
    vim.keymap.set("n", keymaps.submit or "<CR>", function()
        if ui.get_active_tab() == "history" then
            ui.load_history_item_at_cursor()
        else
            ui.submit_query()
        end
    end, vim.tbl_extend("force", opts, { desc = "Submit query / Load history" }))

    vim.keymap.set("i", keymaps.submit or "<CR>", function()
        ui.submit_query()
    end, vim.tbl_extend("force", opts, { desc = "Submit query" }))

    -- Insert newline in insert mode (Meta/Alt + Enter)
    vim.keymap.set("i", "<M-CR>", function()
        vim.api.nvim_put({ "" }, "l", true, true)
    end, vim.tbl_extend("force", opts, { desc = "Insert newline" }))

    vim.keymap.set("i", "<A-CR>", function()
        vim.api.nvim_put({ "" }, "l", true, true)
    end, vim.tbl_extend("force", opts, { desc = "Insert newline" }))

    -- Clear prompt and status (Ctrl-C) - or cancel if loading
    vim.keymap.set("n", keymaps.clear or "<C-c>", function()
        local tab_state = ui.get_tab_state("query")
        if tab_state and tab_state.is_loading then
            ui.cancel_request()
        else
            ui.clear()
        end
    end, vim.tbl_extend("force", opts, { desc = "Clear prompt / Cancel request" }))

    -- Also handle Ctrl-C in insert mode for cancelling during loading
    vim.keymap.set("i", keymaps.clear or "<C-c>", function()
        local tab_state = ui.get_tab_state("query")
        if tab_state and tab_state.is_loading then
            ui.cancel_request()
        else
            -- Default behavior: exit insert mode
            vim.cmd("stopinsert")
        end
    end, vim.tbl_extend("force", opts, { desc = "Cancel request / Exit insert" }))

    -- Start new conversation (Ctrl-N) - clears restore state and starts fresh
    vim.keymap.set("n", keymaps.new_conversation or "<C-n>", function()
        ui.start_new_conversation()
    end, vim.tbl_extend("force", opts, { desc = "Start new conversation" }))

    vim.keymap.set("i", keymaps.new_conversation or "<C-n>", function()
        ui.start_new_conversation()
    end, vim.tbl_extend("force", opts, { desc = "Start new conversation" }))

    -- Focus prompt for editing (Ctrl-I)
    vim.keymap.set("n", keymaps.focus or "<C-i>", function()
        ui.focus_prompt()
    end, vim.tbl_extend("force", opts, { desc = "Focus prompt" }))

    -- Apply last response to prompt (Ctrl-A)
    vim.keymap.set("n", keymaps.apply or "<C-a>", function()
        ui.apply_response()
    end, vim.tbl_extend("force", opts, { desc = "Apply last response to prompt" }))

    -- Context-aware Ctrl-G mapping
    -- In preprompt tab: toggle scope
    -- In settings tab: edit API key
    vim.keymap.set("n", "<C-g>", function()
        local active_tab = ui.get_active_tab()
        if active_tab == "preprompt" then
            ui.toggle_preprompt_scope()
        elseif active_tab == "settings" then
            ui.edit_api_key()
        end
    end, vim.tbl_extend("force", opts, { desc = "Toggle scope / Edit API key" }))

    -- Toggle scope (Ctrl-K) - settings tab only
    vim.keymap.set("n", "<C-k>", function()
        if ui.get_active_tab() == "settings" then
            ui.toggle_settings_scope()
        end
    end, vim.tbl_extend("force", opts, { desc = "Toggle scope (settings)" }))

    -- Toggle debug mode (Ctrl-D) - settings tab only
    vim.keymap.set("n", "<C-d>", function()
        if ui.get_active_tab() == "settings" then
            ui.toggle_debug_mode()
        end
    end, vim.tbl_extend("force", opts, { desc = "Toggle debug mode" }))

    -- History tab: delete item (d key)
    vim.keymap.set("n", "d", function()
        if ui.get_active_tab() == "history" then
            ui.delete_history_item_at_cursor()
        end
    end, vim.tbl_extend("force", opts, { desc = "Delete history item" }))

    -- History tab: clear all (c key)
    vim.keymap.set("n", "c", function()
        if ui.get_active_tab() == "history" then
            ui.clear_all_history()
        end
    end, vim.tbl_extend("force", opts, { desc = "Clear history" }))

    -- Close window (Esc or q - standard Neovim convention for modals)
    vim.keymap.set("n", keymaps.close or "<Esc>", function()
        ui.close()
    end, vim.tbl_extend("force", opts, { desc = "Close n00bkeys window" }))

    -- Also add 'q' as a common alternative for closing
    vim.keymap.set("n", "q", function()
        ui.close()
    end, vim.tbl_extend("force", opts, { desc = "Close n00bkeys window" }))
end

return M
