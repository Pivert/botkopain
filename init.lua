-- mods/botkopain/init.lua
-- BotKopain - Direct EdenAI integration without Python gateway

local bot_name = "BotKopain"
local bot_entity = nil
local processed_messages = {}

-- Load EdenAI module
botkopain_edenai = dofile(minetest.get_modpath("botkopain") .. "/edenai.lua")  -- Rendre global pour les tests

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

-- Suivi des salutations envoyées (pour ne pas répéter)
local greeting_sent = {}

-- Salutations françaises reconnues
local FRENCH_GREETINGS = {
    "bonjour", "bonsoir", "'soir", "hello", "bijour", "ola", "salut", "coucou", 
    "hey", "hi", "bonjour!", "salut!", "coucou!", "hello!", "bonsoir!"
}

-- Détection d'une salutation
local function is_greeting(message)
    local lower_msg = message:lower()
    for _, greeting in ipairs(FRENCH_GREETINGS) do
        if lower_msg:match(greeting) then
            return true
        end
    end
    return false
end

-- Générer une salutation personnalisée
local function generate_greeting(player_name, time_of_day)
    local hour = tonumber(os.date("%H")) or 12
    local greeting
    
    if hour < 12 then
        greeting = "Bonjour"
    elseif hour < 18 then
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

        minetest.log("action", "[BotKopain] Added to private history for " .. player_name .. ": Q=" .. question:sub(1,30) .. "... A=" .. answer:sub(1,30) .. "...")
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

-- Fonction pour obtenir la liste des joueurs connectés
local function get_connected_players()
    local players = minetest.get_connected_players()
    local player_names = {}

    for _, player in ipairs(players) do
        local name = player:get_player_name()
        if name ~= bot_name then
            table.insert(player_names, name)
        end
    end

    return player_names
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
minetest.after(1, function() -- Attendre 1 seconde pour s'assurer que tout est chargé
    minetest.log("action", "[BotKopain] Vérification de la configuration...")

    local http_mods = minetest.settings:get("secure.http_mods") or ""
    local api_key = minetest.settings:get("botkopain_edenai_api_key") or ""
    local project_id = minetest.settings:get("botkopain_edenai_project_id") or ""

    minetest.log("action", "[BotKopain] secure.http_mods: '" .. http_mods .. "'")
    minetest.log("action", "[BotKopain] API key configurée: " .. (api_key ~= "" and "OUI" or "NON"))
    minetest.log("action", "[BotKopain] Project ID configuré: " .. (project_id ~= "" and "OUI" or "NON"))
    minetest.log("action", "[BotKopain] HTTP API: " .. (http_api and "DISPONIBLE" or "INDISPONIBLE"))

    if http_mods:find("botkopain") then
        minetest.log("action", "[BotKopain] botkopain trouvé dans secure.http_mods")
    else
        minetest.log("error", "[BotKopain] botkopain NON trouvé dans secure.http_mods")
    end
end)

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
        player_info.players
    )

    -- Set the callback to handle the response when it arrives
    set_callback(function(reply)
        debug_log("Réponse reçue pour " .. player_name .. ": \"" .. reply:sub(1, 100) .. "...\"")

        if is_public then
            add_to_history("public", player_name, clean_message, reply)
            minetest.chat_send_all("<"..bot_name.."> "..reply)
        else
            add_to_history("private", player_name, clean_message, reply)
            minetest.chat_send_player(player_name, "# "..bot_name.." "..reply)
            if publish_count > 0 then
                publish_private_chat(player_name, publish_count)
            end
        end
    end)
end

-- Enregistrement du privilège
minetest.register_privilege("botkopain", {
    description = "Permet d'interagir avec BotKopain",
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

    -- Détection des salutations à la connexion (premier message)
    if not greeting_sent[name] and is_greeting(message) then
        greeting_sent[name] = true
        local greeting = generate_greeting(name, tonumber(os.date("%H")) or 12)
        minetest.chat_send_all("<"..bot_name.."> "..greeting)
        return  -- Ne pas traiter davantage ce message
    end

    -- Répondre si le bot est mentionné
    if is_bot_mentioned(message) then
        respond_to_mention(name, message)
        return  -- Ne pas traiter davantage ce message
    end

    if real_player_count == 1 then
        -- When alone, use private mode so history is saved for the player
        minetest.log("action", "[BotKopain] Single player mode - using private history")
        process_edenai_request(name, message, false)
    else
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
minetest.register_chatcommand("bk_clear", {
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
minetest.register_chatcommand("bk_debug", {
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
            minetest.chat_send_player(name, "Usage: /bk_debug on  ou  /bk_debug off")
            return true
        end
    end,
})

-- Commande de test pour les développeurs (optionnelle)
minetest.register_chatcommand("bk_test", {
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
minetest.register_chatcommand("bk_auth_test", {
    params = "",
    description = "Tester l'authentification EdenAI (debug les tokens)",
    privs = {server = true},
    func = function(name)
        local api_key = minetest.settings:get("botkopain_edenai_api_key") or ""
        local project_id = minetest.settings:get("botkopain_edenai_project_id") or ""

        minetest.chat_send_player(name, "=== TEST AUTH EDENAI ===")
        minetest.chat_send_player(name, "Project ID: " .. (project_id ~= "" and project_id or "❌ MANQUANT"))
        minetest.chat_send_player(name, "API Key length: " .. #api_key .. " characters")
        minetest.chat_send_player(name, "API Key format: " .. (api_key:match("^eyJ") and "JWT ✓" or "❌ NON JWT"))

        -- Vérifier que c'est bien un JWT
        if api_key:match("^eyJ") then
            minetest.chat_send_player(name, "✅ Le token a l'air d'être un JWT valide")
        else
            minetest.chat_send_player(name, "❌ Le token ne ressemble pas à un JWT EdenAI")
        end

        -- Comparer avec la gateway Python
        minetest.chat_send_player(name, "=== COMPARAISON ===")
        minetest.chat_send_player(name, "Gateway Python utilise la même URL et headers")
        minetest.chat_send_player(name, "La différence doit être dans le token ou project ID")

        return true, "Test d'authentification terminé - vérifiez que le token et project ID correspondent"
    end,
})

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

-- Saluer les joueurs à leur connexion
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    if name ~= bot_name then
        greeting_sent[name] = false  -- Réinitialiser pour permettre une nouvelle salutation
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
        player_info.players
    )
    
    set_callback(function(reply)
        minetest.chat_send_all("<"..bot_name.."> "..reply)
    end)
end
