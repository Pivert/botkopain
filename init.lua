-- mods/botkopain/init.lua
-- BotKopain - Direct EdenAI integration without Python gateway

local bot_name = "BotKopain"
local bot_entity = nil
local processed_messages = {}

-- Load EdenAI module
botkopain_edenai = dofile(minetest.get_modpath("botkopain") .. "/edenai.lua")  -- Rendre global pour les tests

-- Request HTTP API for BotKopain mod
local http_api = minetest.request_http_api()

-- Log HTTP API availability (remove detailed debug for production)
if http_api then
    minetest.log("action", "[BotKopain] HTTP API successfully requested")
else
    minetest.log("warning", "[BotKopain] HTTP API not available - bones search functionality will be limited")
end

-- Load tools module (HTTP version) - pass HTTP API if available
local tools
if http_api then
    tools = dofile(minetest.get_modpath("botkopain") .. "/tools_http_fixed.lua")
    -- Initialize tools with HTTP API
    if tools and tools.init then
        tools.init(http_api)
    end
else
    -- Load tools but they'll handle the lack of HTTP API gracefully
    minetest.log("warning", "[BotKopain] HTTP API not available - bones search functionality will be limited")
    tools = dofile(minetest.get_modpath("botkopain") .. "/tools_http.lua")
end

-- Mode debug
local debug_mode = false

-- Fonction pour log en mode debug
local function debug_log(message)
    if debug_mode then
        minetest.log("action", "[BotKopain DEBUG] " .. message)
    end
end

-- Structure pour stocker l'historique des conversations
local chat_history = {
    public_sessions = {},
    private = {}
}

-- Suivi des salutations par joueur avec limite temporelle (24 heures)
local greeting_tracker = {}

-- Fonction pour obtenir la liste des joueurs connectés (nécessaire pour les fonctions suivantes)
local function get_connected_players()
    local players = minetest.get_connected_players()
    local player_names = {}

    for _, player in ipairs(players) do
        local name = player:get_player_name()
        if name ~= bot_name then
            table.insert(player_names, name)
        end
    end

    return {
        count = #player_names,
        players = player_names
    }
end

-- Détection si le bot est mentionné dans un message
local function is_bot_mentioned(message)
    local lower_msg = message:lower()
    return lower_msg:match("bk:") or
           lower_msg:match("botkopain:") or
           lower_msg:match("kopain:")
end

-- Répondre quand le bot est mentionné
local function respond_to_mention(player_name, message)
    -- Extraire le message après la mention
    local clean_message = message:gsub("[Bb][Kk]:%s*", "")
    clean_message = clean_message:gsub("[Bb]ot[Kk]opain:%s*", "")
    clean_message = clean_message:gsub("[Kk]opain:%s*", "")
    clean_message = clean_message:trim()

    if clean_message == "" then
        -- Pas de message après la mention
        minetest.chat_send_all("<"..bot_name.."> Oui ? Je suis là ! 😊")
        return
    end

    -- Traiter comme une question normale
    local player_info = get_connected_players()

    local set_callback = botkopain_edenai.get_chat_response(
        player_name,
        clean_message,
        player_info.players,
        tools
    )

    set_callback(function(reply)
        minetest.chat_send_all("<"..bot_name.."> "..reply)
    end)
end

-- Salutations françaises reconnues
local FRENCH_GREETINGS = {
    "bonjour", "bonsoir", "'soir", "hello", "bijour", "ola", "salut", "coucou",
    "hey", "hi", "bonjour!", "salut!", "coucou!", "hello!", "bonsoir!"
}

-- Détection d'une salutation (générale ou adressée au bot)
local function is_greeting(message)
    local lower_msg = message:lower()

    -- Vérifier si c'est une salutation
    local is_greeting_word = false
    for _, greeting in ipairs(FRENCH_GREETINGS) do
        if lower_msg:match(greeting) then
            is_greeting_word = true
            break
        end
    end

    if not is_greeting_word then
        return false
    end

    -- Si c'est adressé au bot, c'est pour le bot
    if lower_msg:match("botkopain") or lower_msg:match("bk") or lower_msg:match("kopain") then
        return true
    end

    -- Si c'est adressé à quelqu'un d'autre (nom entre < >), ce n'est pas pour le bot
    if lower_msg:match("<[^>]+>") then
        return false
    end

    -- Si c'est juste "bonjour" ou "salut", c'est général
    return true
end

-- Générer une salutation personnalisée
local function generate_greeting(player_name, time_of_day)
    local hour = tonumber(os.date("%H")) or 12
    local greeting

    if hour >= 2 and hour < 12 then
        greeting = "Bonjour"
    elseif hour >= 12 and hour < 18 then
        greeting = "Bon après-midi"
    else
        greeting = "Bonsoir"
    end

    return greeting .. " " .. player_name .. " ! 😊"
end

-- Session publique active
local current_public_session = nil

-- Génération d'ID de session
local function generate_session_id()
    return tostring(math.random(10000, 99999)) .. "_" .. os.time()
end

-- Initialisation sécurisée des sessions publiques
local function init_public_session()
    if not current_public_session then
        current_public_session = generate_session_id()
        chat_history.public_sessions[current_public_session] = {}
    end
end

-- Fonction pour ajouter un message à l'historique
local function add_to_history(history_type, player_name, question, answer)
    if history_type == "public" then
        -- Initialisation sécurisée
        if not chat_history.public_sessions then
            chat_history.public_sessions = {}
        end
        if not current_public_session then return end
        if not chat_history.public_sessions[current_public_session] then
            chat_history.public_sessions[current_public_session] = {}
        end

        table.insert(chat_history.public_sessions[current_public_session], {
            player = player_name,
            question = question,
            answer = answer,
            timestamp = os.time()
        })

        -- Limiter à 50 messages par session
        if #chat_history.public_sessions[current_public_session] > 50 then
            table.remove(chat_history.public_sessions[current_public_session], 1)
        end
    else
        if not chat_history.private[player_name] then
            chat_history.private[player_name] = {}
        end

        table.insert(chat_history.private[player_name], {
            question = question,
            answer = answer,
            timestamp = os.time()
        })

        minetest.log("action", "[BotKopain] Added to PRIVATE history for " .. player_name .. ": Q=" .. question:sub(1,30) .. "... A=" .. answer:sub(1,30) .. "...")
        minetest.log("action", "[BotKopain] Private history count for " .. player_name .. ": " .. #chat_history.private[player_name])

        -- Limiter à 50 messages par joueur
        if #chat_history.private[player_name] > 50 then
            table.remove(chat_history.private[player_name], 1)
        end
    end
end

-- Fonction pour publier des conversations privées
local function publish_private_chat(player_name, count)
    count = math.min(count, 5)

    -- Vérifier si le joueur a un historique
    minetest.log("action", "[BotKopain] Publishing for " .. player_name .. " - checking history")
    minetest.log("action", "[BotKopain] History exists: " .. tostring(chat_history.private[player_name] ~= nil))
    if chat_history.private[player_name] then
        minetest.log("action", "[BotKopain] History count: " .. #chat_history.private[player_name])
    end

    if not chat_history.private[player_name] or #chat_history.private[player_name] == 0 then
        minetest.chat_send_player(player_name, "# "..bot_name.." Aucune conversation à publier")
        return
    end

    local available_count = #chat_history.private[player_name]

    -- Si demande plus que disponible, ajuster et informer
    if available_count < count then
        count = available_count
        if count == 1 then
            minetest.chat_send_player(player_name, "# "..bot_name.." Une seule conversation disponible")
        else
            minetest.chat_send_player(player_name, "# "..bot_name.." Seulement " .. count .. " conversations disponibles")
        end
    end

    local history = chat_history.private[player_name]
    local start_idx = #history - count + 1

    minetest.chat_send_all("--- " .. player_name .. " partage " .. count .. " conversation(s) avec " .. bot_name .. " ---")

    for i = start_idx, #history do
        minetest.chat_send_all("<" .. player_name .. "> " .. history[i].question)
        minetest.chat_send_all("<" .. bot_name .. "> " .. history[i].answer)
    end

    minetest.chat_send_all("--- Fin du partage ---")
end

-- Vérification de l'API HTTP - IMPORTANT: do this at mod load time
local http_api = minetest.request_http_api and minetest.request_http_api()
if not http_api then
    minetest.log("error", "[BotKopain] API HTTP désactivée. Ajoutez 'secure.http_mods = botkopain' dans minetest.conf")
    minetest.log("error", "[BotKopain] Assurez-vous que la ligne est dans la section [general] du minetest.conf")
else
    minetest.log("action", "[BotKopain] API HTTP disponible")
    -- Passer l'API HTTP au module edenai
    botkopain_edenai.set_http_api(http_api)

    -- Scripts de test supprimés - garder uniquement le mod fonctionnel

    minetest.log("action", "[BotKopain] Scripts de test chargés")
end



-- Fonction pour obtenir les informations complètes d'un joueur
local function get_player_info(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then
        return nil
    end

    -- Position du joueur
    local pos = player:get_pos()
    local position = {
        math.floor(pos.x),
        math.floor(pos.y),
        math.floor(pos.z)
    }

    -- Privilèges du joueur
    local privs = minetest.get_player_privs(player_name)
    local privileges = {}
    for priv_name, _ in pairs(privs) do
        table.insert(privileges, priv_name)
    end

    -- Liste des autres joueurs
    local all_players = get_connected_players()

    return {
        position = position,
        privileges = privileges,
        players = all_players
    }
end

-- No local prompt needed - EdenAI handles prompts remotely

-- Vérifier la configuration au démarrage
-- initialize_botkopain() -- Function not defined, removing call

-- Process message with EdenAI
local function process_edenai_request(player_name, message, is_public)
    minetest.log("action", "[BotKopain] Traitement demandé pour " .. player_name .. ", http_api: " .. (http_api and "disponible" or "INDISPONIBLE"))

    if not http_api then
        local error_msg = "API HTTP non disponible - voir /bkstatus"
        minetest.log("error", "[BotKopain] API HTTP non disponible - ajoutez 'secure.http_mods = botkopain' dans minetest.conf")
        if is_public then
            minetest.chat_send_all("<"..bot_name.."> " .. error_msg)
        else
            minetest.chat_send_player(player_name, "# "..bot_name.." " .. error_msg)
        end
        return
    end

    -- Check for !public command
    local publish_count = 0
    local clean_message = message
    local public_cmd = message:match("!public(%d*)")
    if public_cmd then
        clean_message = message:gsub("!public%d*", ""):gsub("%s+$", "")
        publish_count = tonumber(public_cmd:match("%d+") or "1") or 1
    end

    -- Handle special case: only !public command without text
    if clean_message == "" and publish_count > 0 then
        -- Just republish the last conversations without contacting EdenAI
        if not is_public then
            publish_private_chat(player_name, publish_count)
        else
            minetest.chat_send_player(player_name, "# "..bot_name.." La commande !public fonctionne uniquement en chat privé")
        end
        return
    end

    -- Get player info
    local player_info = get_player_info(player_name)
    if not player_info then
        local error_msg = "Impossible d'obtenir les informations du joueur"
        if is_public then
            minetest.chat_send_all("<"..bot_name.."> " .. error_msg)
        else
            minetest.chat_send_player(player_name, "# "..bot_name.." " .. error_msg)
        end
        return
    end

    -- Get response from EdenAI with proper callback handling
    debug_log("Demande de réponse EdenAI pour " .. player_name .. ": \"" .. clean_message .. "\"")

    local set_callback = botkopain_edenai.get_chat_response(
        player_name,
        clean_message,
        player_info.players,
        tools
    )

    -- Set the callback to handle the response when it arrives
    set_callback(function(reply)
        debug_log("Réponse reçue pour " .. player_name .. ": \"" .. reply:sub(1, 100) .. "...\"")

        if is_public then
            -- Mode PUBLIC : historique partagé de la session
            add_to_history("public", player_name, clean_message, reply)
        -- S'assurer qu'il n'y a aucun retour à la ligne dans la réponse
        reply = reply:gsub("[\n\r]", " ")
        reply = reply:gsub("  +", " ")
        reply = reply:trim()
        minetest.chat_send_all("<"..bot_name.."> "..reply)
            minetest.log("action", "[BotKopain] Added to PUBLIC history: " .. player_name)
        else
            -- Mode PRIVÉ : historique personnel du joueur
            add_to_history("private", player_name, clean_message, reply)
            minetest.chat_send_player(player_name, "<"..bot_name.."> "..reply)
            if publish_count > 0 then
                publish_private_chat(player_name, publish_count)
            end
            minetest.log("action", "[BotKopain] Added to PRIVATE history for " .. player_name)
        end
    end)
end

-- Enregistrement des privilèges
minetest.register_privilege("botkopain", {
    description = "Permet d'interagir avec BotKopain",
    give_to_singleplayer = true,
})

minetest.register_privilege("botkopain_admin", {
    description = "Permet d'utiliser les commandes administratives de BotKopain",
    give_to_singleplayer = true,
})

-- Entité du bot
minetest.register_entity("botkopain:entity", {
    initial_properties = {
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"character.png"},
        visual_size = {x=1, y=1},
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
        stepheight = 0.6,
        eye_height = 1.47,
    },
    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
        self.object:set_properties({nametag = bot_name, nametag_color = "#FF0000"})
    end,
})

-- Spawn du bot
minetest.after(0, function()
    local pos = {x=0, y=10, z=0}
    bot_entity = minetest.add_entity(pos, "botkopain:entity")
end)

-- Gestion du chat public
minetest.register_on_chat_message(function(name, message)
    if not http_api then return end
    if processed_messages[message] or name == bot_name then return end

    if not minetest.check_player_privs(name, {botkopain=true}) then
        return
    end

    processed_messages[message] = true

    -- Compter les vrais joueurs (excluant le bot)
    local players = minetest.get_connected_players()
    local real_player_count = 0
    for _, player in ipairs(players) do
        if player:get_player_name() ~= bot_name then
            real_player_count = real_player_count + 1
        end
    end

    -- Initialiser la session si nécessaire
    init_public_session()

    -- Répondre uniquement aux salutations explicites (pas à la connexion) avec délai et limite temporelle
    -- Mais permettre le traitement des messages composés qui contiennent à la fois une salutation et une question
    if is_greeting(message) then
        local current_time = os.time()
        local player_tracker = greeting_tracker[name] or {last_greeting = 0, count = 0}

        -- Vérifier si assez de temps s'est écoulé (24 heures = 86400 secondes)
        local time_since_last = current_time - player_tracker.last_greeting

        -- Si le message contient aussi une question de mort/os/bones, on traite quand même le message
        local contains_death_question = message:lower():find("mort") or message:lower():find("os") or message:lower():find("bones")

        if time_since_last >= 86400 or contains_death_question then  -- 24 heures en secondes OU question de mort
            -- Mettre à jour le tracker seulement si c'est vraiment une salutation pure
            if not contains_death_question then
                greeting_tracker[name] = {
                    last_greeting = current_time,
                    count = player_tracker.count + 1
                }

                minetest.log("action", "[BotKopain] Salutation pour " .. name .. " (dernière: " .. time_since_last .. "s ago, total: " .. greeting_tracker[name].count .. ")")

                local greeting = generate_greeting(name, tonumber(os.date("%H")) or 12)
                -- Attendre 3 secondes pour une réponse plus naturelle
                minetest.after(3, function()
                    minetest.chat_send_all("<"..bot_name.."> "..greeting)
                end)

                -- Si c'est seulement une salutation, ne pas traiter davantage ce message
                if not contains_death_question then
                    return
                end
                -- Si c'est une salutation + question, continuer le traitement
            end
        else
            minetest.log("action", "[BotKopain] Salutation ignorée pour " .. name .. " (trop récente: " .. time_since_last .. "s < 14400s)")
        end
    end

    -- Gestion intelligente des transitions entre modes
    local current_mode = "public"  -- Par défaut, mode public quand plusieurs joueurs
    if real_player_count == 1 then
        current_mode = "private"
    end

    minetest.log("action", "[BotKopain] Mode " .. current_mode .. " pour " .. name .. " (joueurs: " .. real_player_count .. ")")

    -- Message explicatif pour les transitions
    if real_player_count == 1 then
        minetest.log("action", "[BotKopain] Historique privé de " .. name .. " sera utilisé")
    else
        minetest.log("action", "[BotKopain] Historique public de la session sera utilisé")
    end

    -- Répondre si le bot est mentionné
    if is_bot_mentioned(message) then
        respond_to_mention(name, message)
        return  -- Ne pas traiter davantage ce message
    end

    -- Traiter les messages normaux selon le nombre de joueurs
    if real_player_count == 1 then
        -- Mode PRIVÉ : historique personnel du joueur
        minetest.log("action", "[BotKopain] Single player mode - using private history for " .. name)
        process_edenai_request(name, message, false)
    else
        -- Mode PUBLIC : historique partagé de la session
        minetest.log("action", "[BotKopain] Multiple players - using public history")
        add_to_history("public", name, message, nil)
    end

    minetest.after(0.1, function()
        processed_messages[message] = nil
    end)
end)

-- Commande /bk pour les messages privés
minetest.register_chatcommand("bk", {
    params = "<message>",
    description = "Envoyer un message privé à " .. bot_name .. " (utilisez !public pour partager des conversations)",
    privs = {botkopain = true},
    func = function(name, param)
        if not param or param == "" then
            return false, "Message vide. Usage: /bk <message> ou /bk !public pour partager la dernière conversation"
        end

        -- Vérifier si c'est juste une commande !public sans texte
        local public_cmd = param:match("^!public(%d*)$")
        if public_cmd then
            local publish_count = tonumber(public_cmd:match("%d+") or "1") or 1
            -- Publier directement sans passer par EdenAI
            publish_private_chat(name, publish_count)
            return true, "Conversations partagées avec succès"
        end

        process_edenai_request(name, param, false)
        return true
    end,
})

-- Commande /bkstatus pour vérifier la configuration EdenAI
minetest.register_chatcommand("bkstatus", {
    description = "Affiche les joueurs connectés et teste la connexion EdenAI",
    func = function(name)
        local players = minetest.get_connected_players()
        local player_list = {}
        for _, player in ipairs(players) do
            table.insert(player_list, player:get_player_name())
        end
        table.insert(player_list, bot_name)

        minetest.chat_send_player(name, "Joueurs en ligne ("..#player_list.."):")
        minetest.chat_send_player(name, table.concat(player_list, ", "))

        -- Diagnostic détaillé de la configuration
        minetest.chat_send_player(name, "=== DIAGNOSTIC BotKopain ===")

        -- Check EdenAI configuration
        local api_key = minetest.settings:get("botkopain_edenai_api_key") or ""
        local project_id = minetest.settings:get("botkopain_edenai_project_id") or ""

        if api_key ~= "" and project_id ~= "" then
            minetest.chat_send_player(name, "✅ Configuration EdenAI: OK")
            minetest.chat_send_player(name, "📁 Projet: " .. project_id)
        else
            minetest.chat_send_player(name, "❌ Configuration EdenAI manquante")
            if api_key == "" then
                minetest.chat_send_player(name, "➡️  Ajoutez: botkopain_edenai_api_key = votre_cle_api")
            end
            if project_id == "" then
                minetest.chat_send_player(name, "➡️  Ajoutez: botkopain_edenai_project_id = votre_project_id")
            end
            minetest.chat_send_player(name, "💡 Obtenez vos clés sur: https://app.edenai.run")
        end

        -- Diagnostic HTTP API
        minetest.chat_send_player(name, "=== API HTTP ===")
        if http_api then
            minetest.chat_send_player(name, "✅ API HTTP: Disponible")
            minetest.chat_send_player(name, "ℹ️  L'API HTTP a été correctement initialisée")
        else
            minetest.chat_send_player(name, "❌ API HTTP: Non disponible")
            minetest.chat_send_player(name, "🔧 Solutions:")
            minetest.chat_send_player(name, "1. Ajoutez 'secure.http_mods = botkopain' dans minetest.conf")
            minetest.chat_send_player(name, "2. Redémarrez complètement Luanti")
            minetest.chat_send_player(name, "3. Vérifiez que c'est dans la section [general]")
            minetest.chat_send_player(name, "4. Pas dans world.mt ou autre fichier")
        end

        -- Info sur la configuration actuelle
        minetest.chat_send_player(name, "=== FICHIERS DE CONFIG ===")
        minetest.chat_send_player(name, "📁 Vérifiez: " .. minetest.get_worldpath() .. "/minetest.conf")
        minetest.chat_send_player(name, "📁 Ou: ~/.minetest/minetest.conf (Linux)")
        minetest.chat_send_player(name, "📁 Ou: APPDATA/minetest/minetest.conf (Windows)")

        return true
    end,
})

-- Commande pour effacer l'historique d'un joueur
minetest.register_chatcommand("bkclear", {
    params = "[player_name]",
    description = "Effacer l'historique de conversation (son propre historique ou celui d'un autre si admin)",
    privs = {botkopain = true},
    func = function(name, param)
        local target_player = param ~= "" and param or name

        -- Check if player can clear other's history
        if target_player ~= name and not minetest.check_player_privs(name, {server=true}) then
            return false, "Vous n'avez pas la permission d'effacer l'historique d'un autre joueur"
        end

        -- Clear history
        botkopain_edenai.clear_conversation_history(target_player)

        if target_player == name then
            return true, "Votre historique de conversation a été effacé"
        else
            minetest.log("action", "[BotKopain] " .. name .. " a effacé l'historique de " .. target_player)
            return true, "Historique de " .. target_player .. " effacé"
        end
    end,
})

-- Commande pour activer/désactiver le mode debug
minetest.register_chatcommand("bkdebug", {
    params = "[on|off]",
    description = "Activer/désactiver le mode debug pour BotKopain",
    privs = {server = true},
    func = function(name, param)
        if param == "on" then
            botkopain_edenai.set_debug_mode(true)
            minetest.chat_send_player(name, "✅ Mode debug BotKopain ACTIVÉ")
            minetest.chat_send_player(name, "📋 Les logs détaillés apparaîtront dans les logs serveur")
            return true
        elseif param == "off" then
            botkopain_edenai.set_debug_mode(false)
            minetest.chat_send_player(name, "✅ Mode debug BotKopain DÉSACTIVÉ")
            return true
        else
            local status = debug_mode and "ACTIVÉ" or "DÉSACTIVÉ"
            minetest.chat_send_player(name, "ℹ️ Mode debug actuellement: " .. status)
            minetest.chat_send_player(name, "Usage: /bkdebug on  ou  /bkdebug off")
            return true
        end
    end,
})

-- Commande de diagnostic pour les outils
minetest.register_chatcommand("bkdiag", {
    params = "",
    description = "Diagnostiquer les outils BotKopain",
    privs = {server = true},
    func = function(name)
        minetest.chat_send_player(name, "🔍 Diagnostic des outils BotKopain...")

        -- Vérifier l'API HTTP
        if not http_api then
            minetest.chat_send_player(name, "❌ API HTTP non disponible")
            minetest.chat_send_player(name, "🔧 Ajoutez 'secure.http_mods = botkopain' dans minetest.conf")
            return true
        end

        minetest.chat_send_player(name, "✅ API HTTP disponible")

        -- Vérifier les outils
        if tools and tools.diagnose then
            local diag = tools.diagnose()
            minetest.chat_send_player(name, "🔧 Diagnostic des outils:")
            minetest.chat_send_player(name, "  • Initialisé: " .. (diag.initialized and "OUI" or "NON"))
            minetest.chat_send_player(name, "  • Dernière erreur: " .. (diag.last_error or "AUCUNE"))
            minetest.chat_send_player(name, "  • Service URL: " .. diag.service_url)

            -- Tester la connexion au service
            if tools.check_python_service then
                local healthy = tools.check_python_service()
                minetest.chat_send_player(name, "  • Service Bones: " .. (healthy and "✅ EN LIGNE" or "❌ HORS LIGNE"))
            end
        else
            minetest.chat_send_player(name, "⚠️  Module d'outils non disponible")
        end

        return true
    end,
})

-- Commande de test pour les outils
minetest.register_chatcommand("bktesttools", {
    params = "[player_name]",
    description = "Tester les outils BotKopain",
    privs = {server = true},
    func = function(name, param)
        minetest.chat_send_player(name, "🧪 Test des outils BotKopain...")

        if not http_api then
            minetest.chat_send_player(name, "❌ API HTTP non disponible")
            return true
        end

        local player_name = param ~= "" and param or "player"

        -- Test direct tool call
        if tools and tools.search_death_coordinates then
            minetest.chat_send_player(name, "🔍 Test de recherche de coordonnées de mort pour: " .. player_name)

            local result = tools.search_death_coordinates(player_name, nil, nil, nil, 3)
            minetest.chat_send_player(name, "📋 Résultat: " .. tostring(result))
        else
            minetest.chat_send_player(name, "❌ Fonction de recherche non disponible")
        end

        return true
    end,
})

-- Commande de test pour l'extraction de mots
minetest.register_chatcommand("bktestextract", {
    params = "<message>",
    description = "Tester l'extraction de mots pour les outils",
    privs = {server = true},
    func = function(name, param)
        if param == "" then
            minetest.chat_send_player(name, "Usage: /bktestextract <message>")
            return true
        end

        minetest.chat_send_player(name, "🔍 Test d'extraction de mots pour: " .. param)

        -- Extract player name more carefully from French text
        local target_player = nil

        -- Try to find a player name in the original message
        -- Remove common French words and extract the likely player name
        local words = {}
        for word in param:gmatch("[%w_]+") do
            table.insert(words, word)
        end

        minetest.chat_send_player(name, "📝 Mots trouvés: " .. table.concat(words, ", "))

        -- Look for words that could be player names (not common French words)
        local common_words = {["où"] = true, ["ou"] = true, ["est"] = true, ["mort"] = true, ["le"] = true, ["la"] = true, ["de"] = true, ["il"] = true}

        for _, word in ipairs(words) do
            local lower_word = word:lower()
            if not common_words[lower_word] and #word > 1 then
                target_player = word
                break
            end
        end

        if target_player then
            minetest.chat_send_player(name, "🎯 Joueur extrait: " .. target_player)
        else
            minetest.chat_send_player(name, "❌ Aucun joueur trouvé")
        end

        return true
    end,
})

-- Commande de test pour les développeurs (optionnelle)
minetest.register_chatcommand("bktest", {
    params = "",
    description = "Tester la connexion EdenAI (développement uniquement)",
    privs = {server = true},
    func = function(name)
        -- Vérifier la configuration
        local api_key = minetest.settings:get("botkopain_edenai_api_key") or ""
        local project_id = minetest.settings:get("botkopain_edenai_project_id") or ""

        if api_key == "" or project_id == "" then
            minetest.chat_send_player(name, "❌ Configuration EdenAI incomplète")
            minetest.chat_send_player(name, "Utilisez /bkstatus pour vérifier")
            return true
        end

        minetest.chat_send_player(name, "✅ Configuration EdenAI OK")
        minetest.chat_send_player(name, "🧪 Test de connexion en cours...")

        -- Test simple avec un message court
        local test_message = "Bonjour, test de connexion"
        minetest.chat_send_player(name, "📤 Envoi: \"" .. test_message .. "\"")

        -- Lancer le test
        process_edenai_request(name, test_message, false)

        return true, "Test lancé - la réponse devrait arriver dans 1-3 secondes (debug: " .. (debug_mode and "ON" or "OFF") .. ")"
    end,
})

-- Commande pour tester spécifiquement l'authentification


-- Charger les scripts de test
local test_files = {
    "test_edenai_lua.lua",
    "test_exact_curl.lua",
    "debug_comparison.lua"
}

for _, test_file in ipairs(test_files) do
    local test_path = minetest.get_modpath("botkopain") .. "/" .. test_file
    local file = io.open(test_path, "r")
    if file then
        file:close()
        dofile(test_path)
        minetest.log("action", "[BotKopain] Script de test chargé: " .. test_file)
    else
        minetest.log("warning", "[BotKopain] Script de test non trouvé: " .. test_file)
    end
end

minetest.log("action", "[BotKopain] Module chargé avec connexion directe EdenAI")

-- Load the readbooks module
local readbooks = dofile(minetest.get_modpath("botkopain") .. "/readbooks.lua")

-- Load the book player manager
local bookplayer_manager = dofile(minetest.get_modpath("botkopain") .. "/bookplayer_manager.lua")

-- Load tools module (HTTP version) - reuse the already loaded tools
-- (they should already be initialized with HTTP API if available)
-- Note: Don't reload tools_http.lua as it schedules initialization callbacks
local tools = tools

-- Commande /readbooks pour exporter tous les livres du jeu en XML
minetest.register_chatcommand("readbooks", {
    description = "Exporter tous les livres du jeu dans books.xml (dossier du monde)",
    privs = {botkopain_admin = true},
    func = function(name)
        minetest.chat_send_player(name, "📚 Extraction de tous les livres du jeu...")

        -- Get book stats first
        local stats = readbooks.get_book_stats()
        minetest.chat_send_player(name, "📊 Statistiques des livres trouvés:")
        minetest.chat_send_player(name, "  • Définitions de livres: " .. stats.total_definitions)
        minetest.chat_send_player(name, "  • Livres réels dans le monde: " .. stats.total_world_books)
        minetest.chat_send_player(name, "  • Livres dans les inventaires: " .. stats.total_inventory_books)
        minetest.chat_send_player(name, "  • Livres dans les conteneurs: " .. stats.total_container_books)
        minetest.chat_send_player(name, "  • Total livres réels: " .. stats.total_real_books)

        -- Show book types
        if next(stats.item_types) then
            minetest.chat_send_player(name, "  • Types d'items:")
            for book_type, count in pairs(stats.item_types) do
                minetest.chat_send_player(name, "    - " .. book_type .. ": " .. count)
            end
        end

        if next(stats.node_types) then
            minetest.chat_send_player(name, "  • Types de nodes:")
            for book_type, count in pairs(stats.node_types) do
                minetest.chat_send_player(name, "    - " .. book_type .. ": " .. count)
            end
        end

        -- Export books
        minetest.chat_send_player(name, "💾 Export vers books.xml dans le dossier du monde...")
        local success, message = readbooks.export_books_to_xml()

        if success then
            minetest.chat_send_player(name, "✅ Export réussi:")
            for line in message:gmatch("[^\n]+") do
                minetest.chat_send_player(name, line)
            end
        else
            minetest.chat_send_player(name, "❌ Erreur: " .. message)
        end

        return true
    end,
})

-- Commande /readbooks_stats pour voir les statistiques des livres sans export
minetest.register_chatcommand("readbooks_stats", {
    description = "Afficher les statistiques des livres dans le jeu",
    privs = {botkopain_admin = true},
    func = function(name)
        local stats = readbooks.get_book_stats()

        minetest.chat_send_player(name, "=== 📚 STATISTIQUES DES LIVRES ===")
        minetest.chat_send_player(name, "Définitions de livres: " .. stats.total_definitions)
        minetest.chat_send_player(name, "Livres réels dans le monde: " .. stats.total_world_books)
        minetest.chat_send_player(name, "Livres dans les inventaires: " .. stats.total_inventory_books)
        minetest.chat_send_player(name, "Livres dans les conteneurs: " .. stats.total_container_books)
        minetest.chat_send_player(name, "Total livres réels: " .. stats.total_real_books)

        if next(stats.item_types) then
            minetest.chat_send_player(name, "Types d'items:")
            for book_type, count in pairs(stats.item_types) do
                minetest.chat_send_player(name, "  • " .. book_type .. ": " .. count)
            end
        end

        if next(stats.node_types) then
            minetest.chat_send_player(name, "Types de nodes:")
            for book_type, count in pairs(stats.node_types) do
                minetest.chat_send_player(name, "  • " .. book_type .. ": " .. count)
            end
        end

        if next(stats.world_book_authors) then
            minetest.chat_send_player(name, "Auteurs dans le monde:")
            for author, count in pairs(stats.world_book_authors) do
                minetest.chat_send_player(name, "  • " .. author .. ": " .. count .. " livre(s)")
            end
        end

        if next(stats.inventory_book_authors) then
            minetest.chat_send_player(name, "Auteurs dans les inventaires:")
            for author, count in pairs(stats.inventory_book_authors) do
                minetest.chat_send_player(name, "  • " .. author .. ": " .. count .. " livre(s)")
            end
        end

        if next(stats.container_book_authors) then
            minetest.chat_send_player(name, "Auteurs dans les conteneurs:")
            for author, count in pairs(stats.container_book_authors) do
                minetest.chat_send_player(name, "  • " .. author .. ": " .. count .. " livre(s)")
            end
        end

        minetest.chat_send_player(name, "ℹ️ Utilisez /readbooks pour exporter vers XML")

        return true
    end,
})

-- Commande /bookplayerlist pour lister les joueurs gérés
minetest.register_chatcommand("bookplayerlist", {
    description = "Lister les joueurs dont les livres sont extraits",
    privs = {botkopain_admin = true},
    func = function(name)
        local players = bookplayer_manager.get_managed_players()

        if #players == 0 then
            minetest.chat_send_player(name, "ℹ️ Aucun joueur dans la liste - tous les livres seront extraits")
            return true
        end

        minetest.chat_send_player(name, "=== 📚 JOUEURS GÉRÉS ===")
        for i, player_name in ipairs(players) do
            minetest.chat_send_player(name, i .. ". " .. player_name)
        end

        return true
    end,
})

-- Commande /bookplayeradd pour ajouter un joueur à la liste
minetest.register_chatcommand("bookplayeradd", {
    params = "<player_name>",
    description = "Ajouter un joueur à la liste des joueurs gérés",
    privs = {botkopain_admin = true},
    func = function(name, param)
        if param == "" then
            return false, "Usage: /bookplayeradd <nom_du_joueur>"
        end

        local success, message = bookplayer_manager.add_player(param)
        minetest.chat_send_player(name, message)

        return success
    end,
})

-- Commande /bookplayerrm pour retirer un joueur de la liste
minetest.register_chatcommand("bookplayerrm", {
    params = "<player_name>",
    description = "Retirer un joueur de la liste des joueurs gérés",
    privs = {botkopain_admin = true},
    func = function(name, param)
        if param == "" then
            return false, "Usage: /bookplayerrm <nom_du_joueur>"
        end

        local success, message = bookplayer_manager.remove_player(param)
        minetest.chat_send_player(name, message)

        return success
    end,
})

-- Commande /deaths pour rechercher les coordonnées de mort
minetest.register_chatcommand("deaths", {
    params = "[player_name] [limit]",
    description = "Rechercher les coordonnées de mort d'un joueur (défaut: 3 résultats)",
    privs = {botkopain = true},
    func = function(name, param)
        local parts = {}
        for part in param:gmatch("%S+") do
            table.insert(parts, part)
        end

        local username = parts[1]
        local limit = tonumber(parts[2]) or 3

        if not username then
            return false, "Usage: /deaths <player_name> [limit]"
        end

        minetest.chat_send_player(name, "🔍 Recherche des morts de " .. username .. "...")

        local result = tools.search_death_coordinates(username, nil, nil, nil, limit)

        if result and result ~= "No death coordinates found." then
            minetest.chat_send_player(name, "💀 Coordonnées de mort pour " .. username .. ":")
            -- Split results by | and send each one
            for death_info in result:gmatch("[^|]+") do
                minetest.chat_send_player(name, "  • " .. death_info:trim())
            end
        else
            minetest.chat_send_player(name, "ℹ️ Aucune mort trouvée pour " .. username)
        end

        return true
    end,
})

-- Commande /deaths_time pour rechercher les morts dans une période
minetest.register_chatcommand("deaths_time", {
    params = "<start_date> [end_date] [limit]",
    description = "Rechercher les morts dans une période (format: YYYY-MM-DD)",
    privs = {botkopain_admin = true},
    func = function(name, param)
        local parts = {}
        for part in param:gmatch("%S+") do
            table.insert(parts, part)
        end

        local start_date = parts[1]
        local end_date = parts[2]
        local limit = tonumber(parts[3]) or 5

        if not start_date then
            return false, "Usage: /deaths_time <start_date> [end_date] [limit]"
        end

        minetest.chat_send_player(name, "🔍 Recherche des morts du " .. start_date .. (end_date and " au " .. end_date or "") .. "...")

        local result = tools.search_death_coordinates(nil, start_date, end_date, nil, limit)

        if result and result ~= "No death coordinates found." then
            minetest.chat_send_player(name, "💀 Morts trouvées:")
            -- Split results by | and send each one
            for death_info in result:gmatch("[^|]+") do
                minetest.chat_send_player(name, "  • " .. death_info:trim())
            end
        else
            minetest.chat_send_player(name, "ℹ️ Aucune mort trouvée dans cette période")
        end

        return true
    end,
})

-- Commande /time pour obtenir l'heure actuelle
minetest.register_chatcommand("time", {
    description = "Obtenir l'heure actuelle (fuseau horaire de Paris)",
    privs = {botkopain = true},
    func = function(name)
        local current_time = tools.get_current_time()
        minetest.chat_send_player(name, "🕐 " .. current_time)
        return true
    end,
})

-- Pas de salutation automatique à la connexion - le bot répond seulement aux salutations explicites
-- avec une limite de 24 heures entre chaque salutation par joueur

-- Gestion des changements de nombre de joueurs pour transitionner entre modes
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if name ~= bot_name then
        -- Compact player history on disconnect
        minetest.log("action", "[BotKopain] Compacting history for player " .. name)
        if botkopain_edenai and botkopain_edenai.compact_player_history then
            botkopain_edenai.compact_player_history(name)
        end

        -- Quand un joueur part, vérifier s'il faut changer de mode
        minetest.after(1, function()  -- Attendre 1 seconde pour la mise à jour
            local players = minetest.get_connected_players()
            local count = 0
            for _, p in ipairs(players) do
                if p:get_player_name() ~= bot_name then
                    count = count + 1
                end
            end

            if count == 1 then
                minetest.log("action", "[BotKopain] Transition vers mode privé (1 joueur restant)")
            elseif count == 0 then
                minetest.log("action", "[BotKopain] Plus aucun joueur - compacting public history")
                -- Compact public history when all players disconnect
                if botkopain_edenai and botkopain_edenai.compact_public_history then
                    botkopain_edenai.compact_public_history()
                end
            else
                minetest.log("action", "[BotKopain] Mode public maintenu (" .. count .. " joueurs)")
            end
        end)
    end
end)

-- Détection si le bot est mentionné dans un message
local function is_bot_mentioned(message)
    local lower_msg = message:lower()
    return lower_msg:match("bk:") or
           lower_msg:match("botkopain:") or
           lower_msg:match("kopain:")
end

-- Répondre quand le bot est mentionné
local function respond_to_mention(player_name, message)
    -- Extraire le message après la mention
    local clean_message = message:gsub("[Bb][Kk]:%s*", "")
    clean_message = clean_message:gsub("[Bb]ot[Kk]opain:%s*", "")
    clean_message = clean_message:gsub("[Kk]opain:%s*", "")
    clean_message = clean_message:trim()

    if clean_message == "" then
        -- Pas de message après la mention
        minetest.chat_send_all("<"..bot_name.."> Oui ? Je suis là ! 😊")
        return
    end

    -- Traiter comme une question normale
    local player_info = get_connected_players()

    local set_callback = botkopain_edenai.get_chat_response(
        player_name,
        clean_message,
        player_info.players,
        tools
    )

    set_callback(function(reply)
        minetest.chat_send_all("<"..bot_name.."> "..reply)
    end)
end
