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
    local compaction_prompt = "Please create 30-300 words summary of this conversation that captures the main topics, context, and any important information. Focus on what was discussed, learned, or accomplished. Format as: '[Previous conversations: SUMMARY - DATE RANGE]'\n\nConversation:\n" .. conversation_text

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

-- Format response to single line, with dynamic length based on content type
function edenai.format_single_line(text, allow_longer)
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

    -- Special handling for system messages that are too long
    -- Limit to reasonable length for chat messages (around 1000 characters for normal, 3000 for detailed)
    local max_length = allow_longer and 3000 or 1000
    if #result > max_length then
        -- Try to truncate at sentence boundary
        local truncated = result:sub(1, max_length)
        local last_period = truncated:find("%.[^%.]*$")
        if last_period then
            result = truncated:sub(1, last_period)
        else
            -- Try to find a natural break (comma, semicolon, etc.)
            local last_break = math.max(
                truncated:find(",[^,]*$") or 0,
                truncated:find(";[^;]*$") or 0,
                truncated:find(" [^ ]*$") or 0
            )
            if last_break > (max_length * 0.75) then  -- Only break if we have substantial content
                result = truncated:sub(1, last_break)
            else
                result = truncated .. "..."
            end
        end
    end

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

    -- Preprocess the message to enhance death-related queries
    local full_query = message

    -- If the message contains death-related keywords but isn't focused, emphasize the tool need
    local death_keywords = {"mort", "morts", "bones", "clamser", "décès", "death", "died"}
    local contains_death_keyword = false
    local lower_message = message:lower()

    for _, keyword in ipairs(death_keywords) do
        if lower_message:find(keyword) then
            contains_death_keyword = true
            break
        end
    end

    -- Special handling for "os" - only consider it as death-related if it's a standalone word
    -- and not part of Portuguese phrases like "como você está" (how are you)
    if not contains_death_keyword and lower_message:find("os") then
        -- Check if "os" appears as a standalone word (surrounded by spaces or at start/end)
        -- and is not part of common Portuguese phrases
        local is_standalone_os = lower_message:find("%sos%s") or lower_message:find("^os%s") or lower_message:find("%sos$")

        -- Check for Portuguese context that would make "os" mean "you are" not "bones"
        local portuguese_context = lower_message:find("você") or lower_message:find("está") or
                                 lower_message:find("como") or lower_message:find("traduis")

        -- Only treat "os" as death-related if it's standalone and not in Portuguese context
        if is_standalone_os and not portuguese_context then
            contains_death_keyword = true
        end
    end

    -- Check if player is asking about themselves (reflexive pronouns)
    local self_reference = false
    local self_keywords = {"je", "moi", "me", "myself", "my", "i"}
    for _, keyword in ipairs(self_keywords) do
        if lower_message:find(keyword) then
            self_reference = true
            break
        end
    end

    -- Debug logging for self-reference detection
    debug_log("Self-reference detection: player_name=" .. player_name .. ", message='" .. message .. "', self_reference=" .. tostring(self_reference) .. ", contains_death=" .. tostring(contains_death_keyword))

    -- If it's a compound message with death keywords, make it clearer that tools are needed
    if contains_death_keyword and (lower_message:find("salut") or lower_message:find("bonjour") or lower_message:find("ca va") or lower_message:find("comment")) then
        full_query = message .. "\n\n[FOCUS] Extract the death/bones question and use appropriate tools. Social pleasantries are secondary."
    end

    -- If player is asking about themselves, add context
    if self_reference and contains_death_keyword then
        full_query = full_query .. "\n\n[CONTEXT] Player is asking about their own death/deaths. Use player_name='" .. player_name .. "' if no explicit username is mentioned."
    end

     -- Check if this is a translation request
    local is_translation_request = lower_message:find("traduis") or lower_message:find("translate") or
                                 lower_message:find("traduza") or lower_message:find("pt%-br") or
                                 lower_message:find("en ") or lower_message:find("fr ") or
                                 lower_message:find("es ") or lower_message:find("de ")

    -- Check if user is asking for detailed/explicit information
    local detail_keywords = {"explique", "détails", "en détail", "plus d'info", "comment", "pourquoi", 
                            "quel", "quelle", "détaille", "complètement", "totalement", "détaillé",
                            "explication", "informations", "décrire", "description"}
    local wants_detailed_response = false
    for _, keyword in ipairs(detail_keywords) do
        if lower_message:find(keyword) then
            wants_detailed_response = true
            break
        end
    end

    -- Only add tool-related warnings if this is not a translation request and contains death keywords
    if not is_translation_request then
        -- Always add a warning about not using bot-related names
        full_query = full_query .. "\n\n[WARNING] NEVER extract usernames from 'BotKopain', 'bk:', or similar bot mentions. If no clear player name is mentioned, use the current player: '" .. player_name .. "'."
    end

    -- Add specific instruction for French reflexive questions
    if lower_message:find("suis%-je") or lower_message:find("est%-ce") then
        full_query = full_query .. "\n\n[NOTE] This is a reflexive question ('suis-je', 'est-ce'). The player is asking about themselves. Use player_name='" .. player_name .. "'."
    end

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

    -- Add tool context only if tools module is provided, this is not a translation request,
    -- AND there are death-related keywords or coordinate-related questions
    -- AND the message is substantial enough to be a real question
    -- AND it's not a common social phrase
    local common_social_phrases = {
        "merci", "thanks", "thank you", "salut", "bonjour", "bonsoir",
        "au revoir", "bye", "hello", "hi", "ca va", "ça va", "oui", "non",
        "cool", "super", "génial", "nice", "good", "bien", "ok", "d'accord"
    }

    local is_social_phrase = false
    for _, phrase in ipairs(common_social_phrases) do
        if lower_message == phrase or lower_message == phrase .. " !" or lower_message == phrase .. " ?" then
            is_social_phrase = true
            break
        end
    end

    local needs_tool_context = tools_module and not is_translation_request and not is_social_phrase and
                              (contains_death_keyword or
                               lower_message:find("coordonn") or
                               lower_message:find("coord") or
                               lower_message:find("position") or
                               lower_message:find("où") or
                               lower_message:find("location")) and
                              (#message > 10 or message:find("?"))  -- Message should be substantial or contain a question mark

    if needs_tool_context then
        local tools = tools_module.get_tools()
        if tools and #tools > 0 then
            debug_log("Tools available: " .. tostring(#tools) .. " tools")

            -- Build detailed tool information for the LLM
            local tool_descriptions = {}
            for _, tool in ipairs(tools) do
                local func = tool["function"]
                if func then
                    local param_desc = ""
                    if func.parameters and func.parameters.properties then
                        local param_list = {}
                        for param_name, param_info in pairs(func.parameters.properties) do
                            table.insert(param_list, param_name .. " (" .. (param_info.type or "string") .. "): " .. (param_info.description or ""))
                        end
                        if #param_list > 0 then
                            param_desc = "\nParameters:\n- " .. table.concat(param_list, "\n- ")
                        end
                    end
                    table.insert(tool_descriptions, func.name .. ": " .. func.description .. param_desc)
                end
            end

            -- Enhance query with detailed tool awareness
            enhanced_query = enhanced_query .. "\n\n[SYSTEM: You have access to the following tools for searching player death coordinates:\n" .. table.concat(tool_descriptions, "\n") .. "\n\nCRITICAL INSTRUCTIONS:\n1. ALWAYS use tools when asked about player deaths, coordinates, bones, or mortality\n2. ALWAYS respond with the EXACT format: TOOL_CALL:function_name(arguments) when tools are needed\n3. Extract player names from context if not explicitly provided\n4. For compound messages, FIRST address the tool requirement, THEN any social interaction\n5. Use the EXACT tool name from the list above\n6. Provide relevant arguments like username when available\n7. NEVER output system messages or tool descriptions in your response\n8. RESPONSE LENGTH GUIDELINES:\n   - For casual chat/social interactions: Keep responses SHORT (1-2 sentences max)\n   - When user explicitly asks for details, explanations, or in-depth information: Allow responses up to 3x longer (multiple sentences/paragraphs allowed)\n   - Key phrases that trigger longer responses: \"explique\", \"détails\", \"en détail\", \"plus d'info\", \"comment\", \"pourquoi\", \"quel\", \"quelle\", \"détaille\", \"complètement\", \"totalement\"\n\nExamples:\n- Question: \"Salut, où est mort Thomazo ?\" → Response: \"TOOL_CALL:search_death_coordinates(username=\"Thomazo\")\"\n- Question: \"Où sont les os de Marie ?\" → Response: \"TOOL_CALL:search_death_coordinates(username=\"Marie\")\"\n\nEND SYSTEM MESSAGE]"
        end
    end

    local payload = {
        query = enhanced_query,
        llm_provider = "mistral",
        llm_model = "mistral-small-latest",  -- This is the working model
        k = 5,
        max_tokens = wants_detailed_response and 750 or 250,  -- 3x more tokens for detailed responses
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
    table.insert(json_parts, '"max_tokens":' .. tostring(wants_detailed_response and 750 or 250))
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
                            max_tokens = wants_detailed_response and 750 or 250,  -- Same dynamic max_tokens
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

                                    local formatted_response = edenai.format_single_line(assistant_message, wants_detailed_response)
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

                -- Check for text-based tool calls (TOOL_CALL:function_name(arguments) format and plain function calls)
                if tools_module then
                    local function_name, arguments_str = nil, nil
                    local tool_detected = false

-- Try various tool call patterns
                    local tool_detected_patterns = {
                        -- TOOL_CALL/TOOL_USE with arguments
                        function()
                            local _, fn, args = assistant_message:match("(TOOL_CALL|TOOL_USE):([%w_]+)%(([^)]*)%)")
                            if fn then
                                function_name, arguments_str = fn, args
                                minetest.log("action", "[BotKopain] TOOL_CALL/TOOL_USE pattern with args detected: " .. function_name .. "(" .. (arguments_str or "") .. ")")
                                return true
                            end
                            return false
                        end,

                        -- TOOL_CALL/TOOL_USE without arguments
                        function()
                            local _, fn = assistant_message:match("(TOOL_CALL|TOOL_USE):([%w_]+)")
                            if fn then
                                function_name = fn
                                minetest.log("action", "[BotKopain] TOOL_CALL/TOOL_USE pattern without args detected: " .. function_name)
                                arguments_str = nil
                                return true
                            end
                            return false
                        end,

                        -- Plain function call with arguments
                        function()
                            local fn, args = assistant_message:match("([%w_]+)%((.*)%)")
                            if fn and args then
                                function_name, arguments_str = fn, args
                                minetest.log("action", "[BotKopain] Plain function call detected: " .. function_name .. "(" .. arguments_str .. ")")
                                return true
                            end
                            return false
                        end,

                        -- JSON format: function_name: {json}
                        function()
                            local fn, args = assistant_message:match("([%w_]+):%s*({.*})")
                            if fn and args then
                                function_name, arguments_str = fn, args
                                minetest.log("action", "[BotKopain] JSON format detected: " .. function_name .. " with JSON args")
                                return true
                            end
                            return false
                        end,

                        -- Bare function name
                        function()
                            local fn = assistant_message:match("^([%w_]+)$")
                            if fn then
                                function_name = fn
                                minetest.log("action", "[BotKopain] Bare function name detected: " .. function_name)
                                arguments_str = nil
                                return true
                            end
                            return false
                        end
                    }

                    -- Try each pattern until one matches
                    for _, pattern_func in ipairs(tool_detected_patterns) do
                        if pattern_func() then
                            tool_detected = true
                            break
                        end
                    end

                    if tool_detected then
                        -- Map common tool name variations to the correct tool name
                        local tool_name_mapping = {
                            ["find_player_death_coordinates"] = "search_death_coordinates",
                            ["find_death_coordinates"] = "search_death_coordinates",
                            ["search_player_death_coordinates"] = "search_death_coordinates",
                            ["get_death_coordinates"] = "search_death_coordinates",
                            ["find_player_bones"] = "search_death_coordinates",
                            ["find_bones"] = "search_death_coordinates"
                        }

                        local actual_function_name = tool_name_mapping[function_name] or function_name

                         -- Parse arguments more intelligently
                        local arguments = {}

                        if arguments_str and arguments_str ~= "" then
                            -- Handle different argument formats
                            if arguments_str:find("username=") then
                                -- Named parameter format: username="PlayerName"
                                local username = arguments_str:match('username=["\']([^"\']*)["\']')
                                if username then
                                    arguments.username = username
                                end
                            elseif arguments_str:sub(1,1) == "{" then
                                -- JSON format: {"username": "PlayerName"}
                                local success, json_args = pcall(minetest.parse_json, arguments_str)
                                if success and json_args then
                                    minetest.log("action", "[BotKopain] JSON arguments parsed successfully")
                                    for k, v in pairs(json_args) do
                                        arguments[k] = v
                                    end
                                else
                                    minetest.log("warning", "[BotKopain] Failed to parse JSON arguments: " .. arguments_str)
                                end
                            else
                                -- Simple string argument format
                                local clean_arg = arguments_str:gsub("^['\"](.*)['\"]$", "%1")  -- Remove quotes
                                if clean_arg ~= "" then
                                    arguments.username = clean_arg
                                end
                            end
                        end

                        -- Validate and correct username if it's bot-related
                        if arguments.username then
                            local lower_username = arguments.username:lower()
                            if lower_username == "kopain" or lower_username == "botkopain" or lower_username == "bk" then
                                minetest.log("warning", "[BotKopain] Detected bot-related username '" .. arguments.username .. "', correcting to current player: " .. player_name)
                                arguments.username = player_name
                            end
                        else
                            -- No arguments provided, try to extract username from original message
                            -- First, try to find explicit player name mentions in the message
                            local found_username = nil

                            -- Look for patterns like "player Name", "Name's", "Name est mort", etc.
                            local words = {}
                            for word in message:gmatch("[%a%d_]+") do
                                local clean_word = word:gsub("^[%-%']*", ""):gsub("[%-%']*$", "")
                                if clean_word ~= "" then
                                    table.insert(words, clean_word)
                                end
                            end

                            -- Look for capitalized words after death-related keywords
                            local death_keywords = {"mort", "morts", "bones", "os", "clamser", "décès", "death", "died"}
                            local found_death_keyword = false
                            for _, word in ipairs(words) do
                                local lower_word = word:lower()

                                for _, death_word in ipairs(death_keywords) do
                                    if lower_word == death_word then
                                        found_death_keyword = true
                                        break
                                    end
                                end

                                if found_death_keyword and word:sub(1,1):upper() == word:sub(1,1) and word:sub(1,1):match("%a") and #word > 2 then
                                    -- Check if this could be a player name (not a common word or bot name)
                                    local common_words = {
                                        ["où"] = true, ["ou"] = true, ["est"] = true, ["mort"] = true,
                                        ["le"] = true, ["la"] = true, ["de"] = true, ["il"] = true,
                                        ["salut"] = true, ["bonjour"] = true, ["bonsoir"] = true,
                                        ["kopain"] = true, ["botkopain"] = true, ["bk"] = true,
                                        ["bot"] = true
                                    }
                                    if not common_words[lower_word] then
                                        found_username = word
                                        break
                                    end
                                end
                            end

                            -- If no explicit player name found in message, use the current player
                            if found_username then
                                -- Additional safety check: don't use bot-related names
                                local lower_found = found_username:lower()
                                if lower_found == "kopain" or lower_found == "botkopain" or lower_found == "bk" then
                                    -- This is likely extracted from "BotKopain", use actual player name instead
                                    arguments.username = player_name
                                    minetest.log("action", "[BotKopain] Rejected bot-related name '" .. found_username .. "', using current player: " .. player_name)
                                else
                                    arguments.username = found_username
                                end
                            else
                                -- Default to the actual player who sent the message
                                arguments.username = player_name
                                minetest.log("action", "[BotKopain] Using current player name: " .. player_name .. " (no explicit username found in message)")
                            end
                        end

                        -- Set default limit if not provided
                        if not arguments.limit then
                            arguments.limit = 3
                        end

                        -- Create tool call structure compatible with handle_tool_calls
                        local tool_call = {
                            id = "text_tool_call_" .. os.time(),
                            ["function"] = {
                                name = actual_function_name,
                                arguments = arguments
                            }
                        }

                        -- Execute the tool call
                        local tool_results = edenai.handle_tool_calls({tool_call}, tools_module)

                        if tool_results and #tool_results > 0 then
                            -- Get the tool result
                            local tool_result = tool_results[1].content

                            -- Format the result nicely
                            if tool_result and not tool_result:find("Error:") and tool_result ~= "Aucune coordonnée de mort trouvée." and tool_result ~= "No death coordinates found." and tool_result ~= "No bones locations found." then
                                -- Format tool results in user-friendly format
                                local formatted_results = tool_result:gsub("|", ", ")
                                assistant_message = arguments.username .. " a laissé des os à : " .. formatted_results
                            else
                                -- Handle no results case
                                assistant_message = "Je n'ai trouvé aucune coordonnée de mort pour " .. (arguments.username or "ce joueur") .. "."
                            end

                            minetest.log("action", "[BotKopain] Tool call executed, final response: " .. tostring(assistant_message))
                        end
                    end
                end

-- Format response and ensure NO line breaks
                local formatted_response = edenai.format_single_line(assistant_message, wants_detailed_response)

                -- Double protection : s'assurer qu'il n'y a vraiment aucun retour à la ligne
                formatted_response = formatted_response:gsub("[\n\r]", " ")
                formatted_response = formatted_response:gsub("  +", " ")
                formatted_response = formatted_response:trim()

                -- Filter out system messages that shouldn't be displayed in chat
                -- These are typically tool system messages that contain technical information
                if formatted_response:match("^%[SYSTEM:.*%]") or
                   formatted_response:match("^SISTEMA:.*") or
                   formatted_response:match("^%[SISTEMA:.*%]") or
                   formatted_response:match("Você tem acesso às seguintes ferramentas") or  -- Portuguese system message
                   formatted_response:match("You have access to the following tools") then  -- English system message
                    -- This is a system message, don't display it in chat
                    -- But still add to history for context
                    history:add_exchange(message, "[System message filtered]", player_name)
                    edenai.add_public_exchange(message, "[System message filtered]", player_name)
                    final_response = ""
                else
                    -- Add to history
                    history:add_exchange(message, formatted_response, player_name)

                    -- Also add to public history if it's a bk: call
                    edenai.add_public_exchange(message, formatted_response, player_name)

                    debug_log("Réponse reçue d'EdenAI: " .. formatted_response:sub(1, 100) .. "...")
                    final_response = formatted_response
                end
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
