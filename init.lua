-- mods/botkopain/init.lua

local bot_name = "BotKopain"
local bot_entity = nil
local processed_messages = {}
local system_prompt = ""

-- Configuration du serveur externe (modifiable via minetest.conf)
local external_host = minetest.settings:get("botkopain_host") or "localhost"
local external_port = minetest.settings:get("botkopain_port") or "5000"
local external_url = "http://" .. external_host .. ":" .. external_port

-- Structure pour stocker l'historique des conversations
local chat_history = {
    public_sessions = {},
    private = {}
}

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

        -- Limiter à 50 messages par joueur
        if #chat_history.private[player_name] > 50 then
            table.remove(chat_history.private[player_name], 1)
        end
    end
end

-- Fonction pour publier des conversations privées
local function publish_private_chat(player_name, count)
    count = math.min(count, 5)
    if not chat_history.private[player_name] or #chat_history.private[player_name] < count then
        minetest.chat_send_player(player_name, "Pas assez de conversations à publier")
        return
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

-- Vérification de l'API HTTP
local http_api = minetest.request_http_api and minetest.request_http_api()
if not http_api then
    minetest.log("error", "[BotKopain] API HTTP désactivée. Ajoutez 'secure.http_mods = botkopain' dans minetest.conf")
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

-- Construction du message système complet avec historique
local function get_full_system_prompt(player_name, user_message, is_public)
    local session_history = ""
    local private_history = ""

    -- Historique public
    if is_public and current_public_session and chat_history.public_sessions[current_public_session] then
        local session = chat_history.public_sessions[current_public_session]
        if #session > 0 then
            session_history = "\n\nHISTORIQUE PUBLIC:\n"
            for i = 1, #session do
                local entry = session[i]
                session_history = session_history .. "<" .. entry.player .. "> " .. entry.question .. "\n"
                if entry.answer then
                    session_history = session_history .. "<" .. bot_name .. "> " .. entry.answer .. "\n"
                end
            end
        end
    end

    -- Historique privé
    if chat_history.private[player_name] and #chat_history.private[player_name] > 0 then
        private_history = "\n\nHISTORIQUE PRIVE:\n"
        local player_history = chat_history.private[player_name]
        for i = math.max(1, #player_history - 5 + 1), #player_history do
            private_history = private_history .. "Utilisateur: " .. player_history[i].question .. "\n"
            private_history = private_history .. "BotKopain: " .. player_history[i].answer .. "\n\n"
        end
    end

    return system_prompt ..
           "\n\nCONTEXTE HISTORIQUE:\n" ..
           session_history ..
           private_history ..
           "\n\nJOUEUR: " .. player_name ..
           "\n\nQUESTION: " .. user_message
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

-- Fonction de parsing sécurisée pour l'API REST
local function safe_parse_response(result)
    if not result.succeeded then
        minetest.log("error", "[BotKopain] Échec requête: "..(result.error or "unknown"))
        return nil
    end

    if result.code ~= 200 then
        minetest.log("error", "[BotKopain] Erreur HTTP "..tostring(result.code))
        return nil
    end

    local response = minetest.parse_json(result.data)
    return response and response.response
end

-- Fonction pour traiter une requête à l'API REST externe
local function process_external_api_request(player_name, message, is_public)
    if not http_api then
        local error_msg = "API HTTP non disponible"
        if is_public then
            minetest.chat_send_all("<"..bot_name.."> " .. error_msg)
        else
            minetest.chat_send_player(player_name, "# "..bot_name.." " .. error_msg)
        end
        return
    end

    -- Vérifier si le message contient !public
    local publish_count = 0
    local clean_message = message
    local public_cmd = message:match("!public(%d*)")
    if public_cmd then
        clean_message = message:gsub("!public%d*", ""):gsub("%s+$", "")
        publish_count = tonumber(public_cmd:match("%d+") or "1") or 1
    end

    -- Obtenir les informations du joueur
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

    -- Construction de la payload similaire au client.py (nouveau format)
    local payload = {
        author = player_name,
        online_players = player_info.players,
        xyz = player_info.position,
        privileges = player_info.privileges,
        message = clean_message  -- Message utilisateur uniquement (le gateway construit le prompt)
    }

    local api_url = external_url .. "/chat"

    minetest.log("action", "[BotKopain] Envoi requête à " .. api_url .. " pour " .. player_name)

    http_api.fetch({
        url = api_url,
        method = "POST",
        data = minetest.write_json(payload),
        extra_headers = {
            "Content-Type: application/json"
        },
        timeout = 60,
    }, function(result)
        local reply = safe_parse_response(result)

        if reply then
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
        else
            local error_msg = "Erreur de communication avec le serveur externe"
            if is_public then
                minetest.chat_send_all("<"..bot_name.."> " .. error_msg)
            else
                minetest.chat_send_player(player_name, "# "..bot_name.." " .. error_msg)
            end
            minetest.log("error", "[BotKopain] " .. error_msg)
        end
    end)
end

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

    if real_player_count == 1 then
        process_external_api_request(name, message, true)
    else
        add_to_history("public", name, message, nil)
    end

    minetest.after(0.1, function()
        processed_messages[message] = nil
    end)
end)

-- Commande /bk pour les messages privés
minetest.register_chatcommand("bk", {
    params = "<message>",
    description = "Envoyer un message privé à " .. bot_name,
    privs = {botkopain = true},
    func = function(name, param)
        if not param or param == "" then
            return false, "Message vide. Usage: /bk <message>"
        end

        process_external_api_request(name, param, false)
        return true
    end
})

---- Commande /status
--minetest.register_chatcommand("status", {
--    description = "Affiche les joueurs connectés et teste la connexion API",
--    func = function(name)
--        local players = minetest.get_connected_players()
--        local player_list = {}
--        for _, player in ipairs(players) do
--            table.insert(player_list, player:get_player_name())
--        end
--        table.insert(player_list, bot_name)

--        minetest.chat_send_player(name, "Joueurs en ligne ("..#player_list.."):")
--        minetest.chat_send_player(name, table.concat(player_list, ", "))
--        minetest.chat_send_player(name, "API externe: " .. external_url)

--        -- Test de connexion à l'API externe
--        if http_api then
--            http_api.fetch({
--                url = external_url .. "/status",
--                method = "GET",
--                timeout = 15,
--            }, function(result)
--                if result.succeeded and result.code == 200 then
--                    minetest.chat_send_player(name, "✅ Connexion API: OK")
--                else
--                    minetest.chat_send_player(name, "❌ Connexion API: Échec")
--                end
--            end)
--        else
--            minetest.chat_send_player(name, "❌ API HTTP non disponible")
--        end

--        return true
--    end
--})

minetest.log("action", "[BotKopain] Module chargé avec API externe: " .. external_url)

