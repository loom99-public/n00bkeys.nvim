--- Settings Module
--- Persistent storage for pre-prompt settings (global and project-specific)
--- Handles file I/O, path resolution, and caching
local M = {}

local log = require("n00bkeys.util.log")

-- Internal state cache
M._cache = {
    global = nil, -- Cached global settings
    project = nil, -- Cached project settings
    project_root = nil, -- Cached project root path
}

-- Constants
M.SETTINGS_VERSION = 1
M.DEFAULT_SCOPE = "global"
M.GLOBAL_SUBPATH = "n00bkeys/settings.json"
M.PROJECT_SUBPATH = ".n00bkeys/settings.json"

--- Get default settings structure
--- @return table Default settings
function M.get_default_settings()
    return {
        version = M.SETTINGS_VERSION,
        preprompt = "",
        openai_api_key = "",
        debug_enabled = false,
        selected_scope = M.DEFAULT_SCOPE,
        last_modified = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

--- Get path to global settings file
--- Uses vim.fn.stdpath('config') for Neovim standard location
--- @return string Absolute path to global settings file
function M.get_global_settings_path()
    local config_dir = vim.fn.stdpath("config")
    return config_dir .. "/" .. M.GLOBAL_SUBPATH
end

--- Find project root directory
--- Searches upward for .git directory, falls back to cwd
--- @return string Absolute path to project root
function M.find_project_root()
    if M._cache.project_root then
        return M._cache.project_root
    end

    -- Start from current working directory
    local cwd = vim.fn.getcwd()
    local path = cwd

    -- Search upward for .git directory
    while path ~= "/" do
        if vim.fn.isdirectory(path .. "/.git") == 1 then
            M._cache.project_root = path
            return path
        end
        path = vim.fn.fnamemodify(path, ":h")
    end

    -- Fall back to cwd if no .git found
    M._cache.project_root = cwd
    return cwd
end

--- Get path to project settings file
--- @return string Absolute path to project settings file
function M.get_project_settings_path()
    local project_root = M.find_project_root()
    return project_root .. "/" .. M.PROJECT_SUBPATH
end

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

--- Load global settings from file
--- Returns defaults if file missing or corrupt
--- @return table Settings table
function M.load_global()
    -- Return cached if available
    if M._cache.global then
        return M._cache.global
    end

    local path = M.get_global_settings_path()

    -- Check if file exists
    local file = io.open(path, "r")
    if not file then
        log.debug("settings", "Global settings file not found: %s (using defaults)", path)
        M._cache.global = M.get_default_settings()
        return M._cache.global
    end

    -- Read file content
    local content = file:read("*a")
    file:close()

    -- Parse JSON
    local ok, decoded = pcall(vim.json.decode, content)
    if not ok or type(decoded) ~= "table" then
        log.error("settings", "Corrupt global settings file: %s (using defaults)", path)
        M._cache.global = M.get_default_settings()
        return M._cache.global
    end

    -- Validate version
    if decoded.version ~= M.SETTINGS_VERSION then
        log.error(
            "settings",
            "Unsupported settings version: %d (expected %d)",
            decoded.version or 0,
            M.SETTINGS_VERSION
        )
        -- Could add migration logic here in future
    end

    M._cache.global = decoded
    return M._cache.global
end

--- Load project settings from file
--- Returns defaults if file missing or corrupt
--- @return table Settings table
function M.load_project()
    -- Return cached if available
    if M._cache.project then
        return M._cache.project
    end

    local path = M.get_project_settings_path()

    -- Check if file exists
    local file = io.open(path, "r")
    if not file then
        log.debug("settings", "Project settings file not found: %s (using defaults)", path)
        M._cache.project = M.get_default_settings()
        return M._cache.project
    end

    -- Read file content
    local content = file:read("*a")
    file:close()

    -- Parse JSON
    local ok, decoded = pcall(vim.json.decode, content)
    if not ok or type(decoded) ~= "table" then
        log.error("settings", "Corrupt project settings file: %s (using defaults)", path)
        M._cache.project = M.get_default_settings()
        return M._cache.project
    end

    M._cache.project = decoded
    return M._cache.project
end

--- Save global settings to file
--- @param settings table Settings to save (will merge with defaults)
--- @return boolean Success
function M.save_global(settings)
    local path = M.get_global_settings_path()

    -- Ensure directory exists
    if not M.ensure_directory(path) then
        log.error("settings", "Failed to create directory for: %s", path)
        return false
    end

    -- Merge with existing settings
    local current = M.load_global()
    local updated = vim.tbl_deep_extend("force", current, settings)
    updated.last_modified = os.date("!%Y-%m-%dT%H:%M:%SZ")

    -- Encode to JSON
    local ok, json = pcall(vim.json.encode, updated)
    if not ok then
        log.error("settings", "Failed to encode settings to JSON: %s", json)
        return false
    end

    -- Write to file
    local file, err = io.open(path, "w")
    if not file then
        log.error("settings", "Failed to open settings file for writing: %s (%s)", path, err)
        return false
    end

    file:write(json)
    file:close()

    -- Update cache
    M._cache.global = updated

    log.debug("settings", "Saved global settings to: %s", path)
    return true
end

--- Save project settings to file
--- @param settings table Settings to save (will merge with defaults)
--- @return boolean Success
function M.save_project(settings)
    local path = M.get_project_settings_path()

    -- Ensure directory exists
    if not M.ensure_directory(path) then
        log.error("settings", "Failed to create directory for: %s", path)
        return false
    end

    -- Merge with existing settings
    local current = M.load_project()
    local updated = vim.tbl_deep_extend("force", current, settings)
    updated.last_modified = os.date("!%Y-%m-%dT%H:%M:%SZ")

    -- Encode to JSON
    local ok, json = pcall(vim.json.encode, updated)
    if not ok then
        log.error("settings", "Failed to encode settings to JSON: %s", json)
        return false
    end

    -- Write to file
    local file, err = io.open(path, "w")
    if not file then
        log.error("settings", "Failed to open settings file for writing: %s (%s)", path, err)
        return false
    end

    file:write(json)
    file:close()

    -- Update cache
    M._cache.project = updated

    log.debug("settings", "Saved project settings to: %s", path)
    return true
end

--- Clear cached settings (useful for testing)
function M.clear_cache()
    M._cache.global = nil
    M._cache.project = nil
    M._cache.project_root = nil
end

--- Get the selected scope (global or project)
--- Always reads from global settings
--- @return string "global" or "project"
function M.get_selected_scope()
    local global = M.load_global()
    return global.selected_scope or M.DEFAULT_SCOPE
end

--- Set the selected scope
--- Always saves to global settings
--- @param scope string "global" or "project"
--- @return boolean Success
function M.set_selected_scope(scope)
    assert(scope == "global" or scope == "project", "Invalid scope: " .. tostring(scope))

    local ok = M.save_global({ selected_scope = scope })
    return ok
end

--- Get the current pre-prompt based on selected scope
--- @return string Pre-prompt text (may be empty)
function M.get_current_preprompt()
    local scope = M.get_selected_scope()

    if scope == "global" then
        local global = M.load_global()
        return global.preprompt or ""
    else
        local project = M.load_project()
        return project.preprompt or ""
    end
end

--- Save pre-prompt to current scope
--- @param preprompt string Pre-prompt text
--- @return boolean Success
function M.save_current_preprompt(preprompt)
    local scope = M.get_selected_scope()

    if scope == "global" then
        return M.save_global({ preprompt = preprompt })
    else
        return M.save_project({ preprompt = preprompt })
    end
end

--- Get the current API key based on selected scope
--- @return string API key (may be empty)
function M.get_current_api_key()
    local scope = M.get_selected_scope()

    if scope == "global" then
        local global = M.load_global()
        return global.openai_api_key or ""
    else
        local project = M.load_project()
        return project.openai_api_key or ""
    end
end

--- Save API key to current scope
--- @param api_key string API key
--- @return boolean Success
function M.save_current_api_key(api_key)
    local scope = M.get_selected_scope()

    if scope == "global" then
        return M.save_global({ openai_api_key = api_key })
    else
        return M.save_project({ openai_api_key = api_key })
    end
end

--- Get the current debug mode based on selected scope
--- @return boolean Debug enabled
function M.get_current_debug_mode()
    local scope = M.get_selected_scope()

    if scope == "global" then
        local global = M.load_global()
        return global.debug_enabled or false
    else
        local project = M.load_project()
        return project.debug_enabled or false
    end
end

--- Save debug mode to current scope
--- @param enabled boolean Debug enabled
--- @return boolean Success
function M.save_current_debug_mode(enabled)
    local scope = M.get_selected_scope()

    if scope == "global" then
        return M.save_global({ debug_enabled = enabled })
    else
        return M.save_project({ debug_enabled = enabled })
    end
end

return M
