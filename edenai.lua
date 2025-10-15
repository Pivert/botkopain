-- EdenAI API integration for BotKopain
-- Direct connection to EdenAI without Python gateway

minetest.log("action", "[BotKopain CRITICAL] Loading edenai.lua from /workdir/luanti/mods/botkopain")

local edenai = {}

-- Configuration
local EDENAI_API_KEY = minetest.settings:get("botkopain_edenai_api_key") or ""
local EDENAI_PROJECT_ID = minetest.settings:get("botkopain_edenai_project_id") or ""
-- 🔍 SOLUTION FINALE : Utiliser le proxy local comme solution permanente
-- Le proxy corrige les bugs de Luanti (Content-Type, Authorization, etc.)
local EDENAI_URL_TEMPLATE = "https://api.edenai.run/v2/aiproducts/askyoda/v2/%s/ask_llm"

-- HTTP API - sera défini depuis init.lua
local http_api = nil

-- Mode debug
local debug_mode = false

-- Fonction pour log en mode debug
local function debug_log(message)
    if debug_mode then
        minetest.log("action", "[BotKopain DEBUG] " .. message)
    end
end

-- Fonction pour activer/désactiver le debug
function edenai.set_debug_mode(enabled)
    debug_mode = enabled
    minetest.log("action", "[BotKopain] Mode debug " .. (enabled and "ACTIVÉ" or "DÉSACTIVÉ"))
end

-- Escape JSON strings properly
local function escape_json_string(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub('\\', '\\\\')  -- Escape backslashes first
    str = str:gsub('"', '\\"')    -- Escape quotes
    str = str:gsub('\n', '\\n')   -- Escape newlines
    str = str:gsub('\r', '\\r')   -- Escape carriage returns
    str = str:gsub('\t', '\\t')   -- Escape tabs
    return str
end

-- Fonction pour définir l'API HTTP depuis init.lua
function edenai.set_http_api(api)
    http_api = api
end

-- Fonction pour obtenir l'API HTTP (pour les tests)
function edenai.get_http_api()
    return http_api
end

-- Mod storage for persistent history
local storage = minetest.get_mod_storage()

-- Conversation history management with mod_storage
local conversation_histories = {}

-- Load history from mod_storage
local function load_history_from_storage(key)
    local data = storage:get_string(key)
    if data and data ~= "" then
        return minetest.parse_json(data) or {}
    end
    return {}
end

-- ConversationHistory class equivalent
local ConversationHistory = {}
ConversationHistory.__index = ConversationHistory

function ConversationHistory.new()
    local self = setmetatable({}, ConversationHistory)
    self.exchanges = {}  -- Recent exchanges (max 10)
    self.compacted = {}  -- Compacted exchanges (max 5)
    self.is_public = false  -- Default to private history
    self.player_name = nil
    return self
end

function ConversationHistory:add_exchange(question, response, player)
    -- Filter out greetings
    if self:_is_greeting(question) then
        return
    end

    local exchange = {
        question = question,
        response = response,
        player = player or "unknown",
        timestamp = os.time(),
        is_compacted = false
    }

    table.insert(self.exchanges, exchange)

    -- Trigger compaction if we have more than 10 exchanges
    if #self.exchanges > 10 then
        self:_compact_oldest_exchanges()
    end
    
    -- Save to storage
    self:save_to_storage()
end

function ConversationHistory:_compact_oldest_exchanges()
    -- Check if we have enough exchanges to compact
    if #self.exchanges < 5 then
        return
    end

    -- Remove oldest compacted if we have 5
    if #self.compacted >= 5 then
        table.remove(self.compacted, 1)
    end

    -- Take 5 oldest exchanges
    local to_compact = {}
    for i = 1, 5 do
        if #self.exchanges > 0 then
            table.insert(to_compact, table.remove(self.exchanges, 1))
        end
    end

    -- Create compacted summary using EdenAI
    self:_create_compacted_summary_with_ai(to_compact)
end

function ConversationHistory:_create_compacted_summary_with_ai(exchanges)
    if #exchanges == 0 then
        return
    end

    -- Prepare conversation text for AI compaction
    local conversation_text = ""
    local start_time = nil
    local end_time = nil
    
    for _, exchange in ipairs(exchanges) do
        conversation_text = conversation_text .. exchange.player .. ": " .. exchange.question .. "\n"
        conversation_text = conversation_text .. "BotKopain: " .. exchange.response .. "\n"
        
        if not start_time or exchange.timestamp < start_time then
            start_time = exchange.timestamp
        end
        if not end_time or exchange.timestamp > end_time then
            end_time = exchange.timestamp
        end
    end

    -- Create compaction prompt
    local compaction_prompt = "Please create a concise summary (100-150 words) of this conversation that captures the main topics, context, and any important information. Focus on what was discussed, learned, or accomplished. Format as: '[Previous conversations: SUMMARY - DATE RANGE]'\n\nConversation:\n" .. conversation_text

    -- Call EdenAI for compaction
    edenai.compact_conversation(compaction_prompt, function(summary)
        if summary and summary ~= "" then
            -- Format date range
            local start_date = os.date("%Y-%m-%d %H:%M", start_time)
            local end_date = os.date("%Y-%m-%d %H:%M", end_time)
            local date_range = start_date .. " to " .. end_date
            
            -- Create compacted entry
            local compacted_entry = {
                summary = "[Previous conversations: " .. summary .. " - " .. date_range .. "]",
                timestamp = os.time(),
                is_compacted = true,
                original_count = #exchanges,
                start_time = start_time,
                end_time = end_time
            }
            
            table.insert(self.compacted, compacted_entry)
            self:save_to_storage()
        end
    end)
end

function ConversationHistory:_split_words(text)
    local words = {}
    for word in text:gmatch("%w+") do
        table.insert(words, word)
    end
    return words
end

function ConversationHistory:_is_greeting(message)
    local greetings = {
        "bonjour", "bonsoir", "salut", "hello", "hey", "hi", "coucou",
        "bonjour!", "bonsoir!", "salut!", "hello!", "hey!", "hi!", "coucou!",
        "'soir", "bijour", "ola"
    }
    
    local lower_message = message:lower()
    for _, greeting in ipairs(greetings) do
        if lower_message == greeting then
            return true
        end
    end
    return false
end

function ConversationHistory:_contains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

function ConversationHistory:save_to_storage()
    local storage_key = self.is_public and "public_history" or "player_" .. (self.player_name or "unknown")
    local data_to_save = {
        exchanges = {},
        compacted = {}
    }
    
    -- Save recent exchanges
    for i = 1, math.min(#self.exchanges, 10) do
        local exchange = self.exchanges[i]
        table.insert(data_to_save.exchanges, {
            question = exchange.question,
            response = exchange.response,
            player = exchange.player,
            timestamp = exchange.timestamp
        })
    end
    
    -- Save compacted entries
    for i = 1, math.min(#self.compacted, 5) do
        local compacted = self.compacted[i]
        table.insert(data_to_save.compacted, {
            summary = compacted.summary,
            timestamp = compacted.timestamp,
            is_compacted = compacted.is_compacted,
            original_count = compacted.original_count,
            start_time = compacted.start_time,
            end_time = compacted.end_time
        })
    end
    
    edenai.save_history_to_storage(storage_key, data_to_save)
end

function ConversationHistory:get_history()
    local history = {}
    
    -- Add compacted history first (as context)
    for _, compacted in ipairs(self.compacted) do
        table.insert(history, {
            user = "system",
            assistant = compacted.summary
        })
    end
    
    -- Add recent exchanges in correct format for EdenAI API
    for _, exchange in ipairs(self.exchanges) do
        table.insert(history, {
            user = exchange.player,
            assistant = exchange.question
        })
        table.insert(history, {
            user = "assistant", 
            assistant = exchange.response
        })
    end
    
    -- Limit total history size
    if #history > 30 then
        local limited_history = {}
        local start_idx = #history - 29
        for i = start_idx, #history do
            table.insert(limited_history, history[i])
        end
        return limited_history
    end
    
    return history
end

function ConversationHistory:_limit_words(text, max_words)
    local words = {}
    for word in text:gmatch("%S+") do
        table.insert(words, word)
        if #words >= max_words then
            break
        end
    end
    return table.concat(words, " ")
end

-- Load history from mod_storage
local function load_history_from_storage(key)
    local data = storage:get_string(key)
    if data and data ~= "" then
        return minetest.parse_json(data) or {}
    end
    return {}
end

-- Save history to mod_storage
local function save_history_to_storage(key, data)
    storage:set_string(key, minetest.write_json(data))
end

-- Make the functions accessible from methods
edenai.load_history_from_storage = load_history_from_storage
edenai.save_history_to_storage = save_history_to_storage

-- Get or create conversation history for a player
function edenai.get_conversation_history(player_name)
    if not conversation_histories[player_name] then
        -- Load from storage first
        local stored_history = load_history_from_storage("player_" .. player_name)
        local history = ConversationHistory.new()
        history.player_name = player_name
        
        -- Restore stored exchanges if any
        if stored_history and #stored_history > 0 then
            for _, exchange in ipairs(stored_history) do
                -- Add directly without triggering save to avoid recursion
                table.insert(history.exchanges, {
                    question = exchange.question,
                    response = exchange.response,
                    player = exchange.player,
                    timestamp = exchange.timestamp,
                    is_compacted = false
                })
            end
        end
        
        conversation_histories[player_name] = history
    end
    return conversation_histories[player_name]
end

-- Format response to single line, max 4 sentences, sans retours à la ligne
function edenai.format_single_line(text)
    -- Retirer TOUS les retours à la ligne et caractères de nouvelle ligne
    text = text:gsub("[\n\r]", " ")
    text = text:gsub("%s+", " ")
    text = text:trim()
    
    -- For tool responses, we want to preserve all information
    -- Just remove extra whitespace and ensure single line
    local result = text
    
    -- S'assurer qu'il n'y a vraiment aucun retour à la ligne
    result = result:gsub("[\n\r]", " ")
    result = result:gsub("  +", " ")  -- Éliminer les espaces multiples
    result = result:trim()
    
    return result
end

-- Function to handle tool calls
function edenai.handle_tool_calls(tool_calls, tools_module)
    if not tool_calls or #tool_calls == 0 then
        debug_log("No tool calls to handle")
        return nil
    end
    
    debug_log("Handling " .. #tool_calls .. " tool calls")
    local tool_results = {}
    
    for _, tool_call in ipairs(tool_calls) do
        local function_name = tool_call["function"].name
        local arguments = tool_call["function"].arguments or {}
        
        minetest.log("action", "[BotKopain] Calling tool: " .. function_name)
        debug_log("Tool arguments: " .. minetest.write_json(arguments))
        
        -- Execute the tool
        local result = tools_module.execute_tool(tool_call)
        debug_log("Tool result: " .. tostring(result):sub(1, 100))
        
        table.insert(tool_results, {
            tool_call_id = tool_call.id,
            role = "tool",
            name = function_name,
            content = result
        })
    end
    
    return tool_results
end

-- Main function to get chat response from EdenAI with tool support
function edenai.get_chat_response(player_name, message, online_players, tools_module)
    if not http_api then
        minetest.log("error", "[BotKopain] API HTTP non disponible - ajoutez 'secure.http_mods = botkopain' dans minetest.conf")
        return function(callback)
            callback("Erreur: API HTTP non disponible")
        end
    end

    if EDENAI_API_KEY == "" or EDENAI_PROJECT_ID == "" then
        minetest.log("error", "[BotKopain] Configuration EdenAI manquante - vérifiez minetest.conf")
        return function(callback)
            callback("Erreur: Configuration EdenAI manquante - utilisez /bkstatus pour vérifier")
        end
    end

    -- Get conversation history
    local history = edenai.get_conversation_history(player_name)
    local history_list = history:get_history()

    -- Use the actual message parameter (keep it simple as in working version)
    local full_query = message

    -- Build URL
    local url = string.format(EDENAI_URL_TEMPLATE, EDENAI_PROJECT_ID)
    
    -- Prepare headers
    local extra_headers = {
        "Authorization: Bearer " .. EDENAI_API_KEY,
        "Content-Type: application/json",
        "Accept: application/json"
    }
    
    -- Debug with masked credentials
    debug_log("Authorization: Bearer " .. EDENAI_API_KEY:sub(1, 8) .. "..." .. EDENAI_API_KEY:sub(-4))
    debug_log("Project ID: " .. EDENAI_PROJECT_ID:sub(1, 8) .. "..." .. EDENAI_PROJECT_ID:sub(-4))

    -- Build JSON payload with enhanced query for tool usage
    local enhanced_query = full_query
    
    -- Add tool context if tools module is provided
    if tools_module then
        local tools = tools_module.get_tools()
        if tools and #tools > 0 then
            debug_log("Tools available: " .. tostring(#tools) .. " tools")
            
            -- Enhance query with tool awareness
            enhanced_query = enhanced_query .. "\n\n[SYSTEM: You have access to tools for searching player death coordinates. If asked about player deaths, coordinates, or bones, respond with TOOL_CALL:function_name(arguments) format, then I'll provide the results for your natural response.]"
        end
    end
    
    local payload = {
        query = enhanced_query,
        llm_provider = "mistral",
        llm_model = "mistral-small-latest",  -- This is the working model
        k = 5,
        max_tokens = 250,
        min_score = 0.4,
        temperature = 0.2,
        history = {}
    }
    
    -- CRITICAL DEBUG: Log the exact payload being sent
    minetest.log("action", "[BotKopain CRITICAL] Payload model: " .. payload.llm_model)
    minetest.log("action", "[BotKopain CRITICAL] Payload provider: " .. payload.llm_provider)
    
    -- Only add simple history if present and valid
    if #history_list > 0 then
        local valid_history = {}
        for i, entry in ipairs(history_list) do
            -- Ensure both user and assistant have content
            if entry.assistant and entry.assistant ~= "" and entry.user then
                table.insert(valid_history, {
                    user = entry.user,
                    assistant = entry.assistant
                })
            end
        end
        
        -- Use only last 2 valid entries to avoid empty content
        if #valid_history > 0 then
            payload.history = {}
            local start_idx = math.max(1, #valid_history - 1)
            for i = start_idx, #valid_history do
                table.insert(payload.history, valid_history[i])
            end
        else
            payload.history = {}
        end
    else
        payload.history = {}
    end

    -- Build JSON manually to avoid minetest.write_json issues with empty arrays
    local json_parts = {}
    table.insert(json_parts, '"query":"' .. escape_json_string(enhanced_query) .. '"')
    table.insert(json_parts, '"llm_provider":"mistral"')
    table.insert(json_parts, '"llm_model":"mistral-small-latest"')  -- Fixed model name
    table.insert(json_parts, '"k":5')
    table.insert(json_parts, '"max_tokens":250')
    table.insert(json_parts, '"min_score":0.4')
    table.insert(json_parts, '"temperature":0.2')
    
    -- Force history to be an array, never null
    if #payload.history > 0 then
        local history_json = minetest.write_json(payload.history)
        table.insert(json_parts, '"history":' .. history_json)
    else
        table.insert(json_parts, '"history":[]')
    end
    
    local json_data = "{" .. table.concat(json_parts, ",") .. "}"
    
    -- CRITICAL DEBUG: Log the exact JSON being sent
    minetest.log("action", "[BotKopain CRITICAL] Full JSON being sent: " .. json_data)

    -- DEBUG CRITICAL : Vérifier que le nouveau code est chargé
    minetest.log("action", "[BotKopain CRITICAL] History payload type: " .. type(payload.history) .. " count: " .. tostring(#payload.history))
    
    debug_log("URL: " .. url)
    debug_log("Extra Headers: " .. minetest.write_json(extra_headers))
    debug_log("History list count: " .. tostring(#history_list))
    if #history_list > 0 then
        debug_log("Last history entry: " .. minetest.write_json(history_list[#history_list]))
    end
    debug_log("JSON Payload: " .. json_data)
    
    -- Debug essential information
    debug_log("URL: " .. url)
    debug_log("Model: mistral-small-latest")
    debug_log("Tools module present: " .. tostring(tools_module ~= nil))
    
    -- Vérification finale du JSON
    if json_data:find('"history":null') then
        minetest.log("error", "[BotKopain CRITICAL] JSON still contains null history!")
        minetest.log("error", "[BotKopain CRITICAL] Payload history: " .. minetest.write_json(payload.history))
    end
    minetest.log("action", "[BotKopain] Envoi requête EdenAI pour " .. player_name)

    -- Make HTTP request (async) - use callback directly
    local callback_function = nil
    
    http_api.fetch({
        url = url,
        method = "POST",
        data = json_data,
        extra_headers = extra_headers,  -- Format correct : array de strings
        timeout = 10
    }, function(result)
        local final_response

        if result.succeeded and result.code == 200 then
            local response_data = minetest.parse_json(result.data)
            if response_data then
                -- Debug response
                debug_log("Response received from EdenAI")
                
                -- Check if the model wants to call tools - handle both response formats
                debug_log("Response data: " .. minetest.write_json(response_data))
                
                -- Check for tool calls in different possible locations
                local tool_calls = nil
                if response_data.tool_calls and #response_data.tool_calls > 0 then
                    tool_calls = response_data.tool_calls
                elseif response_data.choices and response_data.choices[1] and response_data.choices[1].tool_calls and #response_data.choices[1].tool_calls > 0 then
                    tool_calls = response_data.choices[1].tool_calls
                end
                
                if tool_calls and tools_module and #tool_calls > 0 then
                    minetest.log("action", "[BotKopain] Tool calls detected: " .. tostring(#tool_calls))
                    
                    -- Execute tool calls
                    local tool_results = edenai.handle_tool_calls(tool_calls, tools_module)
                    
                    if tool_results and #tool_results > 0 then
                        -- Build follow-up request with tool results
                        local followup_payload = {
                            query = full_query,
                            llm_provider = "mistral",
                            llm_model = "mistral-small-latest",
                            k = 5,
                            max_tokens = 250,
                            min_score = 0.4,
                            temperature = 0.2,
                            history = payload.history,
                            tool_results = tool_results
                        }
                        
                        local followup_json = minetest.write_json(followup_payload)
                        
                        -- Make follow-up request
                        http_api.fetch({
                            url = url,
                            method = "POST",
                            data = followup_json,
                            extra_headers = extra_headers,
                            timeout = 10,
                            extra_body = {preference = "cost"}  -- Match Python example
                        }, function(followup_result)
                            local final_response
                            if followup_result and followup_result.succeeded and followup_result.code == 200 then
                                local followup_data = minetest.parse_json(followup_result.data)
                                if followup_data then
                                    local assistant_message = followup_data.result or
                                                            followup_data.answer or
                                                            followup_data.response or
                                                            "Réponse non disponible"
                                    
                                    local formatted_response = edenai.format_single_line(assistant_message)
                                    formatted_response = formatted_response:gsub("[\n\r]", " ")
                                    formatted_response = formatted_response:gsub("  +", " ")
                                    formatted_response = formatted_response:trim()
                                    
                                    history:add_exchange(message, formatted_response, player_name)
                                    edenai.add_public_exchange(message, formatted_response, player_name)
                                    
                                    debug_log("Réponse finale avec outils: " .. formatted_response:sub(1, 100) .. "...")
                                    final_response = formatted_response
                                else
                                    final_response = "Erreur: Réponse invalide après appels d'outils"
                                end
                            else
                                final_response = "Erreur lors de la requête de suivi avec outils"
                            end
                            
-- Ensure callback is called even if there are errors
                            if callback_function then
                                local success, err = pcall(callback_function, final_response)
                                if not success then
                                    minetest.log("error", "[BotKopain] Error calling callback: " .. tostring(err))
                                end
                            end
                        end)
                        
                        return  -- Early return, callback will be called from nested request
                    end
                end
                
                -- Regular response (no tool calls detected in API format)
                local assistant_message = response_data.result or
                                        response_data.answer or
                                        response_data.response or
                                        "Réponse non disponible"
                
                minetest.log("action", "[BotKopain] Original assistant message: " .. tostring(assistant_message))

                -- Simple tool detection for prompt-based approach
                if tools_module then
                    minetest.log("action", "[BotKopain] Checking for tool usage - message: " .. tostring(message) .. ", response: " .. tostring(assistant_message))
                    
                    -- Simple heuristic: if response mentions searching and the original question was about deaths
                    local original_lower = message:lower()
                    local response_lower = assistant_message:lower()
                    
                    -- Check if original question was about death/mort/bones/etc.
                    local is_death_question = original_lower:find("mort") or original_lower:find("mourir") or 
                                            original_lower:find("death") or original_lower:find("die") or
                                            original_lower:find("bones") or original_lower:find("coord")
                    
                    minetest.log("action", "[BotKopain] Death question detected: " .. tostring(is_death_question))
                    
                    -- Check if response indicates it wants to search
                    local wants_to_search = response_lower:find("search") or response_lower:find("find") or
                                          response_lower:find("recherche") or response_lower:find("cherche")
                    
                    minetest.log("action", "[BotKopain] Wants to search: " .. tostring(wants_to_search))
                    
                    if is_death_question then
                        -- Extract player name more carefully from French text
                        local target_player = nil
                        
                        -- Try to find a player name in the original message
                        -- Remove common French words and extract the likely player name
                        local words = {}
                        for word in message:gmatch("[%w_]+") do
                            table.insert(words, word)
                        end
                        
                        -- Look for words that could be player names (not common French words or greetings)
                        local common_words = {
                            ["où"] = true, ["ou"] = true, ["est"] = true, ["mort"] = true, 
                            ["le"] = true, ["la"] = true, ["de"] = true, ["il"] = true,
                            ["salut"] = true, ["bonjour"] = true, ["bonsoir"] = true,
                            ["kopain"] = true, ["botkopain"] = true, ["bk"] = true
                        }
                        
                        -- First, try to find a word that's likely a player name
                        -- (appears after "mort" or is capitalized and not a greeting)
                        local found_death_keyword = false
                        for _, word in ipairs(words) do
                            local lower_word = word:lower()
                            
                            -- Track if we've seen death-related keywords
                            if lower_word == "mort" or lower_word == "morts" or lower_word == "bones" then
                                found_death_keyword = true
                            end
                            
                            -- Skip common words and greetings
                            if not common_words[lower_word] and #word > 1 then
                                -- If we've seen death keywords, the next word is likely the player name
                                if found_death_keyword then
                                    target_player = word
                                    break
                                end
                                
                                -- Otherwise, prefer capitalized words (likely names)
                                if word:sub(1,1):upper() == word:sub(1,1) and word:sub(1,1):match("%a") then
                                    target_player = word
                                    -- Don't break immediately - continue to see if there's a better candidate after "mort"
                                end
                            end
                        end
                        
                        -- Fallback: if no target found and we have words, use the last viable candidate
                        if not target_player then
                            for _, word in ipairs(words) do
                                local lower_word = word:lower()
                                if not common_words[lower_word] and #word > 1 then
                                    target_player = word
                                end
                            end
                        end
                        
                        if target_player then
                            minetest.log("action", "[BotKopain] Attempting tool call for player: " .. target_player)
                            
                            -- Execute tool with error handling
                            local success, tool_result = pcall(tools_module.search_death_coordinates, target_player, nil, nil, nil, 3)
                            
                            minetest.log("action", "[BotKopain] Tool execution result - Success: " .. tostring(success) .. ", Result: " .. tostring(tool_result))
                            
                            if success and tool_result then
                                -- Check if the result is an error message or no results
                                if not tool_result:find("Error:") and tool_result ~= "Aucune coordonnée de mort trouvée." and tool_result ~= "No death coordinates found." and tool_result ~= "No bones locations found." then
                                    -- Enhance the response with tool results in a user-friendly format
                                    local formatted_results = tool_result:gsub("|", ", ")
                                    assistant_message = target_player .. " a laissé des os à : " .. formatted_results
                                    minetest.log("action", "[BotKopain] Appending tool results to response")
                                else
-- Handle no results case more gracefully
                            if tool_result == "No bones locations found." or tool_result == "Aucune coordonnée de mort trouvée." or tool_result == "No death coordinates found." then
                                assistant_message = "Je n'ai trouvé aucune coordonnée de mort pour " .. target_player .. "."
                                minetest.log("action", "[BotKopain] No death coordinates found, setting no-results message")
                            else
                                minetest.log("warning", "[BotKopain] Tool returned error: " .. tostring(tool_result))
                            end
                                end
                            elseif not success then
                                minetest.log("error", "[BotKopain] Tool execution failed: " .. tostring(tool_result))
                            end
end
                    end
                end
                
minetest.log("action", "[BotKopain] Completed tool processing section")
                
-- Format response and ensure NO line breaks
                minetest.log("action", "[BotKopain] Pre-formatting response: " .. tostring(assistant_message))
                local formatted_response = edenai.format_single_line(assistant_message)
                
                -- Double protection : s'assurer qu'il n'y a vraiment aucun retour à la ligne
                formatted_response = formatted_response:gsub("[\n\r]", " ")
                formatted_response = formatted_response:gsub("  +", " ")
                formatted_response = formatted_response:trim()
                
                minetest.log("action", "[BotKopain] Final formatted response: " .. tostring(formatted_response))
                
                -- Add to history
                history:add_exchange(message, formatted_response, player_name)
                
                -- Also add to public history if it's a bk: call
                edenai.add_public_exchange(message, formatted_response, player_name)
                
                debug_log("Réponse reçue d'EdenAI: " .. formatted_response:sub(1, 100) .. "...")
                final_response = formatted_response
            else
                final_response = "Erreur: Réponse invalide d'EdenAI"
            end
        else
            local error_msg = "Erreur de connexion à EdenAI"
            if result.code then
                error_msg = error_msg .. " (code " .. result.code .. ")"
            end
            if result.error then
                error_msg = error_msg .. ": " .. result.error
            end
            if result.data then
                error_msg = error_msg .. " - Response: " .. result.data
            end
            minetest.log("error", "[BotKopain] " .. error_msg)
            debug_log("Full error response: " .. minetest.write_json(result))
            final_response = error_msg
        end

        -- Call the callback function if provided
        if callback_function then
            local success, err = pcall(callback_function, final_response)
            if not success then
                minetest.log("error", "[BotKopain] Error calling callback: " .. tostring(err))
            end
        end
    end)

    -- Return a function to set the callback
    return function(callback)
        callback_function = callback
    end
end

-- Get public conversation history
function edenai.get_public_history()
    if not conversation_histories["public"] then
        local stored_history = load_history_from_storage("public_history")
        local history = ConversationHistory.new()
        history.is_public = true
        history.player_name = "public"
        
        -- Restore stored exchanges if any
        if stored_history and #stored_history > 0 then
            for _, exchange in ipairs(stored_history) do
                -- Add directly without triggering save to avoid recursion
                table.insert(history.exchanges, {
                    question = exchange.question,
                    response = exchange.response,
                    player = exchange.player,
                    timestamp = exchange.timestamp,
                    is_compacted = false
                })
            end
        end
        
        conversation_histories["public"] = history
    end
    return conversation_histories["public"]
end

-- Add exchange to public history (only for bk: calls)
function edenai.add_public_exchange(question, response, player)
    -- Only add if question contains "bk:" (case insensitive)
    if question:lower():find("bk:") then
        local public_history = edenai.get_public_history()
        public_history:add_exchange(question, response, player)
    end
end

-- Clear conversation history for a player
function edenai.clear_conversation_history(player_name)
    conversation_histories[player_name] = nil
    storage:set_string("player_" .. player_name, "")
end

-- Compact all remaining exchanges for a player
function edenai.compact_player_history(player_name)
    local history = conversation_histories[player_name]
    if not history or #history.exchanges == 0 then
        return
    end
    
    -- Compact all remaining exchanges
    history:_create_compacted_summary_with_ai(history.exchanges)
    
    -- Clear original exchanges after compaction
    history.exchanges = {}
    history:save_to_storage()
end

-- Compact public history
function edenai.compact_public_history()
    local history = conversation_histories["public"]
    if not history or #history.exchanges == 0 then
        return
    end
    
    -- Compact all remaining exchanges
    history:_create_compacted_summary_with_ai(history.exchanges)
    
    -- Clear original exchanges after compaction
    history.exchanges = {}
    history:save_to_storage()
end

-- Compact conversation using EdenAI
function edenai.compact_conversation(prompt, callback)
    if not http_api then
        callback("")
        return
    end

    -- Use same API endpoint but with compaction prompt
    local url = string.format(EDENAI_URL_TEMPLATE, EDENAI_PROJECT_ID)
    local extra_headers = {
        "Authorization: Bearer " .. EDENAI_API_KEY,
        "Content-Type: application/json",
        "Accept: application/json"
    }

    -- Build compaction request
    local payload = {
        query = prompt,
        llm_provider = "mistral",
        llm_model = "mistral-small-latest",
        k = 3,
        max_tokens = 200,
        min_score = 0.3,
        temperature = 0.1,
        history = {}
    }
    
    local json_data = minetest.write_json(payload)

    http_api.fetch({
        url = url,
        method = "POST",
        data = json_data,
        extra_headers = extra_headers,
        timeout = 10,
    }, function(result)
        if result.succeeded and result.code == 200 then
            local response_data = minetest.parse_json(result.data)
            if response_data then
                local summary = response_data.result or response_data.answer or response_data.response or ""
                callback(summary)
            else
                callback("")
            end
        else
            callback("")
        end
    end)
end

-- Get all conversation histories (for debugging)
function edenai.get_all_histories()
    return conversation_histories
end

return edenai
