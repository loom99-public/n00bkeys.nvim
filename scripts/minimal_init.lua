-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up 'mini.test' and 'mini.doc' only when calling headless Neovim (like with `make test` or `make documentation`)
if #vim.api.nvim_list_uis() == 0 then
    -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
    -- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
    vim.cmd("set rtp+=deps/mini.nvim")

    -- Set up 'mini.test' with explicit test file filtering
    -- This prevents discovery of mini.nvim's own test files in deps/
    require("mini.test").setup({
        collect = {
            find_files = function()
                -- Collect only test_*.lua files directly in tests/ directory
                -- Using readdir ensures we only get files in tests/, not subdirectories like deps/
                local test_dir = 'tests'
                local files = vim.fn.readdir(test_dir)

                -- Filter for test_*.lua pattern and build full paths
                local test_files = {}
                for _, file in ipairs(files) do
                    if file:match('^test_.*%.lua$') then
                        table.insert(test_files, test_dir .. '/' .. file)
                    end
                end

                return test_files
            end
        }
    })

    -- Set up 'mini.doc'
    require("mini.doc").setup()
end
