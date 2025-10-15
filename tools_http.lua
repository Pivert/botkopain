-- tools_http.lua - BotKopain tools using HTTP calls to Bones service

local tools = {}

-- Configuration for Bones search service (Kubernetes deployment)
local BONES_SERVICE_URL = "http://bones:5000"

-- HTTP API object (will be set during initialization)
local http_api = nil

-- Flag to track if initialization has been scheduled (using global to persist across reloads)
-- Commenting out the early return to ensure tools are properly loaded
-- if _G._botkopain_tools_init_scheduled then
--     -- Already scheduled, don't schedule again
--     minetest.log("action", "[BotKopain Tools] Initialization already scheduled, skipping")
--     return tools
-- end
-- _G._botkopain_tools_init_scheduled = true

-- Tool definitions for AI integration (same as before)
tools.TOOLS = {
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
    else
        minetest.log("warning", "[BotKopain Tools] HTTP API not provided - service functionality will be limited")
    end
end

-- HTTP request helper function
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

    -- Try different possible HTTP API methods
    local response
    local success, err = pcall(function()
        if http_api.fetch_sync then
            -- Synchronous version (preferred for our use case)
            minetest.log("action", "[BotKopain Tools] Using http_api.fetch_sync method")
            response = http_api.fetch_sync(request_data)
        elseif http_api.sync then
            -- Another possible synchronous method name
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
                -- No delay possible in this context
            end

            if result and result.completed then
                response = result
            else
                error("HTTP request timed out or failed")
            end
        elseif http_api.fetch then
            -- Asynchronous version - but we'll treat it synchronously for now
            minetest.log("action", "[BotKopain Tools] Using http_api.fetch method")
            -- For now, we'll just return an error since we can't properly handle async
            error("Async HTTP request cannot be used in synchronous context")
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
    if not http_api then
        return "Error: HTTP API not available - bones search functionality disabled"
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
    if not http_api then
        -- Fallback to local time calculation if HTTP API not available
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

-- Fallback local time function (same as original)
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
    return tools.TOOLS
end

-- Check if tools are properly initialized with HTTP API
function tools.is_initialized()
    return http_api ~= nil
end

-- Health check function to verify Bones service is available
function tools.check_python_service()
    if not http_api then
        minetest.log("error", "[BotKopain Tools] Cannot check Bones service health - HTTP API not available")
        return false
    end

    minetest.log("action", "[BotKopain Tools] Checking Bones service health at " .. BONES_SERVICE_URL .. "/health")

    local url = BONES_SERVICE_URL .. "/health"
    local success, response_data, error = pcall(function()
        return make_http_request(url, "GET", nil)
    end)

    if not success then
        minetest.log("error", "[BotKopain Tools] Exception during Bones service health check: " .. tostring(response_data))
        return false
    end

    if error then
        minetest.log("error", "[BotKopain Tools] Bones service health check failed: " .. error)
        return false
    end

    if not response_data then
        minetest.log("error", "[BotKopain Tools] Bones service health check: no response")
        return false
    end

    -- Parse JSON response
    local success2, response = pcall(minetest.parse_json, response_data)
    if not success2 then
        minetest.log("error", "[BotKopain Tools] Bones service health check: invalid JSON response: " .. tostring(response_data))
        return false
    end

    if response.status == "healthy" then
        minetest.log("action", "[BotKopain Tools] Bones service is healthy")
        return true
    end

    minetest.log("error", "[BotKopain Tools] Bones service health check: unhealthy status")
    return false
end

-- Flag to track if initialization has been scheduled
local initialization_scheduled = false

-- Initialize tools module with Bones service verification
local function initialize_tools()
    minetest.log("action", "[BotKopain Tools] Initializing Bones service tools module...")

    -- Safety check: ensure tools module is available
    if not tools then
        minetest.log("error", "[BotKopain Tools] Tools module not available")
        return false
    end

    -- Check if HTTP API is available (it should be set during mod initialization)
    if not http_api then
        minetest.log("error", "[BotKopain Tools] HTTP API not available - Bones service tools cannot function")
        minetest.log("error", "[BotKopain Tools] Please ensure botkopain is listed in secure.http_mods or secure.trusted_mods in minetest.conf")
        return false
    end

    minetest.log("action", "[BotKopain Tools] HTTP API is available, checking Bones service...")

    -- Check Bones service health
    local healthy, err = pcall(function()
        return tools.check_python_service()
    end)

    if not healthy then
        minetest.log("error", "[BotKopain Tools] Error during Bones service health check: " .. tostring(err))
        minetest.log("error", "[BotKopain Tools] Bones service tools module failed to initialize")
        return false
    end

    if healthy then
        minetest.log("action", "[BotKopain Tools] Bones service tools module initialized successfully")
        return true
    else
        minetest.log("error", "[BotKopain Tools] Bones service tools module failed to connect to service")
        minetest.log("error", "[BotKopain Tools] Please ensure bones service is running at http://bones:5000")
        return false
    end
end

-- Initialize tools immediately
-- Commenting out delayed initialization that may cause callback issues
-- if not _G._botkopain_tools_after_callback_registered then
--     _G._botkopain_tools_after_callback_registered = true
--     minetest.after(2, function()
--         local success, err = pcall(initialize_tools)
--         if not success then
--             minetest.log("error", "[BotKopain Tools] Critical error during tools initialization: " .. tostring(err))
--             minetest.log("error", "[BotKopain Tools] Bones service tools module failed to start")
--         end
--     end)
-- else
--     minetest.log("action", "[BotKopain Tools] Initialization callback already registered, skipping")
-- end

-- Simple initialization without delayed callback
pcall(function()
    if http_api then
        minetest.log("action", "[BotKopain Tools] HTTP API available, tools ready")
    else
        minetest.log("warning", "[BotKopain Tools] HTTP API not available")
    end
end)

-- Clean up global flag when mod is unloaded (for development reloading)
-- minetest.register_on_shutdown(function()
--     _G._botkopain_tools_after_callback_registered = nil
--     _G._botkopain_tools_init_scheduled = nil
-- end)

return tools
