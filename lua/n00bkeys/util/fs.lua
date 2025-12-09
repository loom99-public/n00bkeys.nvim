--- Filesystem utilities for n00bkeys
---
---@tag n00bkeys.util.fs
---@private

local M = {}

--- Ensure directory exists, create if needed
--- @param path string File path (directory will be extracted)
--- @return boolean Success
function M.ensure_directory(path)
    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
        local ok = vim.fn.mkdir(dir, "p")
        return ok == 1
    end
    return true
end

return M
