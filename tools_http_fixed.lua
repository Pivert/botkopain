-- tools_http_fixed.lua - Fixed BotKopain tools using HTTP calls to Bones service

local tools = {}

-- Configuration for Bones search service (Kubernetes deployment)
local BONES_SERVICE_URL = "http://bones:5000"

-- HTTP API object (will be set during initialization)
local http_api = nil

-- Flag for initialization status
local is_initialized = false
local last_error = nil

-- Tool definitions for AI integration
local TOOLS = {
    {
        type = "function",
        ["function"] = {
            name = "search_death_coordinates",
            description = "Search for player death locations (where bones are placed) in debug.txt. When players die in the game, bones are placed at their death coordinates. This tool can find death locations for terms like: death, died, bones, os (bones), clamser (died), mort (death), décès (death), etc.",
            parameters = {
                type = "object",
                properties = {
                    username = {
                        type = "string",
                        description = "The username of the player. If not provided, searches for all players."
                    },
                    start_date = {
                        type = "string",
                        description = "Start date in format YYYY-MM-DD or YYYY-MM-DD HH:MM for range queries (Paris timezone)"
                    },
                    end_date = {
                        type = "string",
                        description = "End date in format YYYY-MM-DD or YYYY-MM-DD HH:MM for range queries (Paris timezone)"
                    },
                    date = {
                        type = "string",
                        description = "Single date in format YYYY-MM-DD (Paris timezone). Alternative to start_date/end_date."
                    },
                    limit = {
                        type = "integer",
                        description = "Maximum number of results to return. Default is 3. Results are sorted by most recent first.",
                        default = 3
                    }
                },
                required = {}
            }
        }
    },
    {
        type = "function",
        ["function"] = {
            name = "get_current_time",
            description = "Get the current date and time in Paris timezone. Useful for interpreting relative dates like 'yesterday', 'last week', 'last 3 hours', etc.",
            parameters = {
                type = "object",
                properties = {},
                required = {}
            }
        }
    }
}

-- Initialization function to set HTTP API
function tools.init(http_object)
    http_api = http_object
    if http_api then
        minetest.log("action", "[BotKopain Tools] HTTP API initialized successfully")
        is_initialized = true
        
        -- Test connectivity immediately
        minetest.after(1, function()
            tools.check_python_service()
        end)
    else
        minetest.log("warning", "[BotKopain Tools] HTTP API not provided - service functionality will be limited")
        is_initialized = false
        last_error = "HTTP API not available"
    end
end

-- HTTP request helper function with proper error handling
local function make_http_request(url, method, data)
    if not http_api then
        minetest.log("error", "[BotKopain Tools] HTTP API not available - request cannot be made")
        return nil, "HTTP API not available"
    end

    -- Validate http_api object
    if type(http_api) ~= "table" then
        minetest.log("error", "[BotKopain Tools] HTTP API is not a table, type: " .. type(http_api))
        return nil, "Invalid HTTP API object"
    end

    local request_data = {
        url = url,
        method = method,
        timeout = 10,
        data = data and minetest.write_json(data) or nil
    }

    if method == "POST" and data then
        request_data.extra_headers = {
            "Content-Type: application/json"
        }
    end

    -- Use synchronous methods first, fallback to async with polling
    local response
    local success, err = pcall(function()
        if http_api.fetch_sync then
            -- Synchronous version (preferred)
            minetest.log("action", "[BotKopain Tools] Using http_api.fetch_sync method")
            response = http_api.fetch_sync(request_data)
        elseif http_api.sync then
            -- Another possible synchronous method
            minetest.log("action", "[BotKopain Tools] Using http_api.sync method")
            response = http_api.sync(request_data)
        elseif http_api.fetch_async and http_api.fetch_async_get then
            -- Asynchronous version with polling for synchronous use
            minetest.log("action", "[BotKopain Tools] Using http_api.fetch_async method with polling")
            local handle = http_api.fetch_async(request_data)
            
            -- Poll for completion (with timeout)
            local timeout = 10
            local start_time = os.time()
            local result = nil
            
            while (os.time() - start_time) < timeout do
                result = http_api.fetch_async_get(handle)
                if result.completed then
                    break
                end
                -- Small delay to prevent CPU spinning
                minetest.after(0.1, function() end)
            end
            
            if result and result.completed then
                response = result
            else
                error("HTTP request timed out or failed")
            end
        elseif http_api.fetch then
            -- Use fetch with callback for async handling
            minetest.log("action", "[BotKopain Tools] Using http_api.fetch method with callback")
            -- For now, return error since we need sync for tools
            error("Async HTTP not supported for tools")
        else
            error("No suitable HTTP method found in http_api object")
        end
    end)

    if not success then
        minetest.log("error", "[BotKopain Tools] HTTP request failed: " .. tostring(err))
        return nil, "HTTP request failed: " .. tostring(err)
    end

    if not response then
        return nil, "No response from HTTP request"
    end

    if response.succeeded then
        if response.code == 200 then
            return response.data, nil
        else
            return nil, "HTTP error: " .. tostring(response.code) .. " - " .. tostring(response.data)
        end
    else
        return nil, "HTTP request failed: " .. tostring(response.data)
    end
end

-- Search death coordinates using HTTP call to Bones service
function tools.search_death_coordinates(username, start_date, end_date, date, limit)
    if not is_initialized then
        return "Error: Tools not initialized - " .. (last_error or "unknown error")
    end

    limit = limit or 3

    -- Build request parameters
    local params = {
        username = username,
        start_date = start_date,
        end_date = end_date,
        date = date,
        limit = limit
    }

    -- Remove nil/empty values
    for k, v in pairs(params) do
        if v == nil or v == "" then
            params[k] = nil
        end
    end

    -- Make HTTP request to Bones service
    local url = BONES_SERVICE_URL .. "/search_bones"
    local response_data, error = make_http_request(url, "POST", params)

    if error then
        minetest.log("error", "[BotKopain Tools] Bones service request failed: " .. error)
        return "Aucune coordonnée de mort trouvée. Le service de recherche est temporairement indisponible."
    end

    if not response_data then
        return "Aucune coordonnée de mort trouvée. Le service de recherche n'a pas répondu."
    end

    -- Parse JSON response
    local success, response = pcall(minetest.parse_json, response_data)
    if not success then
        minetest.log("error", "[BotKopain Tools] Failed to parse JSON response: " .. tostring(response_data))
        return "Aucune coordonnée de mort trouvée. Réponse invalide du service de recherche."
    end

    if response.error then
        minetest.log("error", "[BotKopain Tools] Python service error: " .. tostring(response.error))
        return "Aucune coordonnée de mort trouvée. Erreur du service de recherche: " .. tostring(response.error)
    end

    if response.result then
        return response.result
    end

    return "Aucune coordonnée de mort trouvée."
end

-- Get current time using HTTP call to Python service
function tools.get_current_time()
    if not is_initialized then
        -- Fallback to local time calculation
        return tools.get_local_time()
    end

    -- Make HTTP request to Bones service
    local url = BONES_SERVICE_URL .. "/current_time"
    local response_data, error = make_http_request(url, "GET", nil)

    if error then
        minetest.log("error", "[BotKopain Tools] Bones service time request failed: " .. error)
        -- Fallback to local time calculation
        return tools.get_local_time()
    end

    if not response_data then
        -- Fallback to local time calculation
        return tools.get_local_time()
    end

    -- Parse JSON response
    local success, response = pcall(minetest.parse_json, response_data)
    if not success then
        minetest.log("error", "[BotKopain Tools] Failed to parse JSON response: " .. tostring(response_data))
        -- Fallback to local time calculation
        return tools.get_local_time()
    end

    if response.current_time then
        return response.current_time
    end

    -- Fallback to local time calculation
    return tools.get_local_time()
end

-- Fallback local time function
function tools.get_local_time()
    local TIMEZONE_OFFSET = 2  -- Paris timezone (UTC+2)
    local now = os.time()
    local paris_time = now + (TIMEZONE_OFFSET * 3600)
    local day_name = os.date("%A", paris_time)
    local month_name = os.date("%B", paris_time)
    local day = os.date("%d", paris_time)
    local year = os.date("%Y", paris_time)
    local time = os.date("%H:%M", paris_time)

    return string.format("%s, %s %s, %s at %s (Paris time)", day_name, month_name, day, year, time)
end

-- Execute a tool call
function tools.execute_tool(tool_call)
    local function_name = tool_call["function"].name
    local arguments = tool_call["function"].arguments or {}

    if function_name == "search_death_coordinates" then
        return tools.search_death_coordinates(
            arguments.username,
            arguments.start_date,
            arguments.end_date,
            arguments.date,
            arguments.limit
        )
    elseif function_name == "get_current_time" then
        return tools.get_current_time()
    else
        return "Unknown tool: " .. function_name
    end
end

-- Get tool definitions for AI integration
function tools.get_tools()
    return TOOLS
end

-- Check if tools are properly initialized with HTTP API
function tools.is_initialized()
    return is_initialized
end

-- Get last error message
function tools.get_last_error()
    return last_error
end

-- Health check function to verify Bones service is available
function tools.check_python_service()
    if not http_api then
        minetest.log("error", "[BotKopain Tools] Cannot check Bones service health - HTTP API not available")
        is_initialized = false
        last_error = "HTTP API not available"
        return false
    end

    minetest.log("action", "[BotKopain Tools] Checking Bones service health at " .. BONES_SERVICE_URL .. "/health")

    local url = BONES_SERVICE_URL .. "/health"
    local success, response_data, error = pcall(function()
        return make_http_request(url, "GET", nil)
    end)

    if not success then
        minetest.log("error", "[BotKopain Tools] Exception during Bones service health check: " .. tostring(response_data))
        is_initialized = false
        last_error = "Exception during health check: " .. tostring(response_data)
        return false
    end

    if error then
        minetest.log("error", "[BotKopain Tools] Bones service health check failed: " .. error)
        is_initialized = false
        last_error = "Health check failed: " .. error
        return false
    end

    if not response_data then
        minetest.log("error", "[BotKopain Tools] Bones service health check: no response")
        is_initialized = false
        last_error = "No response from health check"
        return false
    end

    -- Parse JSON response
    local success2, response = pcall(minetest.parse_json, response_data)
    if not success2 then
        minetest.log("error", "[BotKopain Tools] Bones service health check: invalid JSON response: " .. tostring(response_data))
        is_initialized = false
        last_error = "Invalid JSON response"
        return false
    end

    if response.status == "healthy" then
        minetest.log("action", "[BotKopain Tools] Bones service is healthy and ready")
        is_initialized = true
        last_error = nil
        return true
    end

    minetest.log("error", "[BotKopain Tools] Bones service health check: unhealthy status")
    is_initialized = false
    last_error = "Service unhealthy"
    return false
end

-- Diagnostic function to test connectivity
function tools.diagnose()
    local diagnostics = {
        http_api_available = http_api ~= nil,
        initialized = is_initialized,
        last_error = last_error,
        service_url = BONES_SERVICE_URL
    }
    
    if http_api then
        diagnostics.http_api_type = type(http_api)
        diagnostics.has_fetch_sync = http_api.fetch_sync ~= nil
        diagnostics.has_sync = http_api.sync ~= nil
        diagnostics.has_fetch = http_api.fetch ~= nil
    end
    
    return diagnostics
end

return tools
