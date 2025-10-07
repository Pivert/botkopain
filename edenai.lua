-- EdenAI API integration for BotKopain
-- Direct connection to EdenAI without Python gateway

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

-- Fonction pour définir l'API HTTP depuis init.lua
function edenai.set_http_api(api)
    http_api = api
end

-- Fonction pour obtenir l'API HTTP (pour les tests)
function edenai.get_http_api()
    return http_api
end

-- Conversation history management (similar to Python version)
local conversation_histories = {}

-- ConversationHistory class equivalent
local ConversationHistory = {}
ConversationHistory.__index = ConversationHistory

function ConversationHistory.new()
    local self = setmetatable({}, ConversationHistory)
    self.exchanges = {}  -- Recent exchanges (max 10)
    self.compacted = {}  -- Compacted exchanges (max 5)
    return self
end

function ConversationHistory:add_exchange(question, response, player)
    local exchange = {
        question = question,
        response = response,
        player = player or "inconnu",
        timestamp = os.time(),
        is_compacted = false
    }

    table.insert(self.exchanges, exchange)

    -- Compact oldest exchanges if we exceed 10
    if #self.exchanges > 10 then
        self:_compact_oldest_exchanges()
    end
end

function ConversationHistory:_compact_oldest_exchanges()
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

    -- Create compacted summary
    local summary = self:_create_compacted_summary(to_compact)
    table.insert(self.compacted, {
        summary = summary,
        timestamp = os.time(),
        is_compacted = true,
        original_count = #to_compact
    })
end

function ConversationHistory:_create_compacted_summary(exchanges)
    if #exchanges == 0 then
        return ""
    end

    -- Extract main themes (Luanti-related keywords)
    local themes = {}
    local keywords = {
        "craft", "miner", "construire", "maison", "ferme", "mobs", "diamant",
        "bois", "pierre", "outil", "armure", "cuisine", "exploration", "cave",
        "village", "fer", "charbon", "redstone", "enchantement", "nether"
    }

    for _, exchange in ipairs(exchanges) do
        local q_words = self:_split_words(exchange.question:lower())
        local r_words = self:_split_words(exchange.response:lower())

        for _, word in ipairs(q_words) do
            for _, keyword in ipairs(keywords) do
                if word == keyword and not self:_contains(themes, keyword) then
                    table.insert(themes, keyword)
                end
            end
        end

        for _, word in ipairs(r_words) do
            for _, keyword in ipairs(keywords) do
                if word == keyword and not self:_contains(themes, keyword) then
                    table.insert(themes, keyword)
                end
            end
        end
    end

    local themes_str = #themes > 0 and table.concat(themes, ", ", 1, math.min(3, #themes)) or "discussion générale"
    return "[Échanges antérieurs: " .. themes_str .. " - " .. #exchanges .. " interactions]"
end

function ConversationHistory:_split_words(text)
    local words = {}
    for word in text:gmatch("%w+") do
        table.insert(words, word)
    end
    return words
end

function ConversationHistory:_contains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

function ConversationHistory:get_history()
    local history = {}

    -- Add recent exchanges (last 5)
    local start_idx = math.max(1, #self.exchanges - 4)
    for i = start_idx, #self.exchanges do
        local exchange = self.exchanges[i]
        table.insert(history, {
            user = exchange.player,
            assistant = exchange.question
        })
        table.insert(history, {
            user = "BotKopain",
            assistant = exchange.response
        })
    end

    -- Add older exchanges (5-10) with limitation
    if #self.exchanges > 5 then
        local older_start = math.max(1, #self.exchanges - 9)
        local older_end = math.max(1, #self.exchanges - 5)

        for i = older_start, older_end do
            local exchange = self.exchanges[i]
            local q_limited = self:_limit_words(exchange.question, 15)
            local r_limited = self:_limit_words(exchange.response, 15)

            table.insert(history, {
                user = exchange.player,
                assistant = q_limited .. "..."
            })
            table.insert(history, {
                user = "BotKopain",
                assistant = r_limited .. "..."
            })
        end
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

-- Get or create conversation history for a player
function edenai.get_conversation_history(player_name)
    if not conversation_histories[player_name] then
        conversation_histories[player_name] = ConversationHistory.new()
    end
    return conversation_histories[player_name]
end

-- Format response to single line, max 4 sentences, sans retours à la ligne
function edenai.format_single_line(text)
    -- Retirer TOUS les retours à la ligne et caractères de nouvelle ligne
    text = text:gsub("[\n\r]", " ")
    text = text:gsub("%s+", " ")
    text = text:trim()

    -- Split into sentences
    local sentences = {}
    for sentence in text:gmatch("[^.!?]+[.!?]") do
        table.insert(sentences, sentence:trim())
    end

    -- Limit to 4 sentences
    if #sentences > 4 then
        for i = 5, #sentences do
            sentences[i] = nil
        end
    end

    -- Forcer une seule ligne en remplaçant les retours à la ligne par des espaces
    local result = table.concat(sentences, " ")

    -- S'assurer qu'il n'y a vraiment aucun retour à la ligne
    result = result:gsub("[\n\r]", " ")
    result = result:gsub("  +", " ")  -- Éliminer les espaces multiples
    result = result:trim()

    return result
end

-- Main function to get chat response from EdenAI
function edenai.get_chat_response(player_name, message, online_players)
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

    -- Use the actual message parameter
    local full_query = message

    -- Build URL
    local url = string.format(EDENAI_URL_TEMPLATE, EDENAI_PROJECT_ID)
    
    -- Prepare headers
    local extra_headers = {
        "Authorization: Bearer " .. EDENAI_API_KEY,
        "Content-Type: application/json",
        "Accept: application/json"
    }

    -- Build JSON payload manually for exact format matching
    local json_parts = {}
    table.insert(json_parts, '"query":"' .. full_query .. '"')
    table.insert(json_parts, '"llm_provider":"mistral"')
    table.insert(json_parts, '"llm_model":"mistral-small-latest"')
    table.insert(json_parts, '"k":5')
    table.insert(json_parts, '"max_tokens":250')
    table.insert(json_parts, '"min_score":0.4')
    table.insert(json_parts, '"temperature":0.2')

    -- Add history if present
    if #history_list > 0 then
        local history_json = minetest.write_json(history_list)
        table.insert(json_parts, '"history":' .. history_json)
    else
        table.insert(json_parts, '"history":[]')
    end

    local json_data = "{" .. table.concat(json_parts, ",") .. "}"

    minetest.log("action", "[BotKopain] Envoi requête EdenAI pour " .. player_name)

    http_api.fetch({
        url = url,
        method = "POST",
        data = json_data,
        extra_headers = extra_headers,  -- Format correct : array de strings
        timeout = 10,
    }, function(result)
        local final_response

        if result.succeeded and result.code == 200 then
            local response_data = minetest.parse_json(result.data)
            if response_data then
                -- Extract response from EdenAI format
                local assistant_message = response_data.result or
                                        response_data.answer or
                                        response_data.response or
                                        "Réponse non disponible"

                -- Format response and ensure NO line breaks
                local formatted_response = edenai.format_single_line(assistant_message)

                -- Double protection : s'assurer qu'il n'y a vraiment aucun retour à la ligne
                formatted_response = formatted_response:gsub("[\n\r]", " ")
                formatted_response = formatted_response:gsub("  +", " ")
                formatted_response = formatted_response:trim()

                -- Add to history
                history:add_exchange(message, formatted_response, player_name)

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
            minetest.log("error", "[BotKopain] " .. error_msg)
            final_response = error_msg
        end

        -- Call the callback function if provided
        if callback_function then
            callback_function(final_response)
        end
    end)

    -- Return a function to set the callback
    return function(callback)
        callback_function = callback
    end
end

-- Clear conversation history for a player
function edenai.clear_conversation_history(player_name)
    conversation_histories[player_name] = nil
end

-- Get all conversation histories (for debugging)
function edenai.get_all_histories()
    return conversation_histories
end

return edenai
