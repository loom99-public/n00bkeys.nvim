-- HTTP client module for n00bkeys using curl
local M = {}

--- Make an async POST request using curl
---@param url string URL to POST to
---@param headers table<string, string> HTTP headers
---@param body table Request body (will be JSON encoded)
---@param callback function(err, response) Callback with (error, response)
function M.post(url, headers, body, callback)
    -- Check if curl exists
    if vim.fn.executable("curl") == 0 then
        vim.schedule(function()
            callback({ error = "curl not found. Please install curl." }, nil)
        end)
        return
    end

    -- Build curl args
    local curl_args = {
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "--max-time",
        "30",
        "--silent",
        "--show-error",
    }

    -- Add custom headers
    for key, value in pairs(headers or {}) do
        table.insert(curl_args, "-H")
        table.insert(curl_args, key .. ": " .. value)
    end

    -- Add body
    local ok, body_json = pcall(vim.json.encode, body)
    if not ok then
        vim.schedule(function()
            callback({ error = "Failed to encode JSON body" }, nil)
        end)
        return
    end

    table.insert(curl_args, "-d")
    table.insert(curl_args, body_json)

    -- Add URL
    table.insert(curl_args, url)

    -- Execute curl using vim.system (Neovim 0.10+)
    if vim.system then
        vim.system({ "curl", unpack(curl_args) }, {
            text = true,
        }, function(result)
            vim.schedule(function()
                -- Check for curl errors
                if result.code ~= 0 then
                    callback(
                        { error = result.stderr or "Unknown curl error", code = result.code },
                        nil
                    )
                    return
                end

                -- Parse JSON response
                local parse_ok, parsed = pcall(vim.json.decode, result.stdout)
                if not parse_ok then
                    callback({ error = "Failed to parse JSON response", raw = result.stdout }, nil)
                    return
                end

                callback(nil, parsed)
            end)
        end)
    else
        -- Fallback for Neovim 0.9.x using vim.loop
        local stdout = vim.loop.new_pipe(false)
        local stderr = vim.loop.new_pipe(false)
        local stdout_data = ""
        local stderr_data = ""

        local handle
        handle = vim.loop.spawn("curl", {
            args = curl_args,
            stdio = { nil, stdout, stderr },
        }, function(code, signal)
            stdout:close()
            stderr:close()
            handle:close()

            vim.schedule(function()
                -- Check for curl errors
                if code ~= 0 then
                    callback({ error = stderr_data or "Unknown curl error", code = code }, nil)
                    return
                end

                -- Parse JSON response
                local parse_ok, parsed = pcall(vim.json.decode, stdout_data)
                if not parse_ok then
                    callback({ error = "Failed to parse JSON response", raw = stdout_data }, nil)
                    return
                end

                callback(nil, parsed)
            end)
        end)

        if not handle then
            vim.schedule(function()
                callback({ error = "Failed to spawn curl process" }, nil)
            end)
            return
        end

        stdout:read_start(function(err, data)
            if err then
                return
            end
            if data then
                stdout_data = stdout_data .. data
            end
        end)

        stderr:read_start(function(err, data)
            if err then
                return
            end
            if data then
                stderr_data = stderr_data .. data
            end
        end)
    end
end

return M
