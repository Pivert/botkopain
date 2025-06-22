-- mods/botkopain/init.lua

local bot_name = "BotKopain"
local bot_entity = nil
local processed_messages = {}
local system_prompt = ""
local resources_content = ""

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

-- Récupération de la clé API
local api_key = minetest.settings:get("botkopain_perplexity_api_key")

if not api_key or api_key == "" then
    minetest.log("error", "[BotKopain] ERREUR: Clé API absente dans minetest.conf")
    minetest.chat_send_all("<"..bot_name.."> ERREUR: Clé API non configurée. Voir logs.")
    api_key = nil
else
    minetest.log("action", "[BotKopain] Clé API détectée")
end

local http_api = minetest.request_http_api and minetest.request_http_api()

if not http_api then
    minetest.log("error", "[BotKopain] API HTTP désactivée. Ajoutez 'secure.http_mods = botkopain' dans minetest.conf")
end

-- Fonction de lecture de fichier
local function read_file(file_path)
    local file = io.open(file_path, "r")
    if not file then
        minetest.log("error", "[BotKopain] Fichier non trouvé: "..file_path)
        return nil
    end
    local content = file:read("*all")
    file:close()
    return content
end

-- Chargement des prompts et ressources
local function load_prompt_and_resources()
    local mod_path = minetest.get_modpath("botkopain")
    system_prompt = read_file(mod_path.."/prompt.txt") or
        "Tu es BotKopain, assistant spécialisé dans Luanti/Minetest. Réponds de manière technique et précise."
    resources_content = read_file(mod_path.."/resources.txt") or
        "Documentation: https://docs.luanti.org/\nCode source: https://github.com/luanti-org/luanti"
    minetest.log("action", "[BotKopain] Prompt et ressources chargés")
end

load_prompt_and_resources()

-- Construction du message système complet
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
           "\n\nCONTEXTE ET RESSOURCES:\n" .. resources_content ..
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

-- Fonction de parsing sécurisée
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
    return response and response.choices and response.choices[1] and response.choices[1].message and response.choices[1].message.content
end

-- Fonction pour traiter une requête à l'API Perplexity
local function process_perplexity_request(player_name, message, is_public)
    if not http_api then return end
    if not api_key then
        local response = "ERREUR: Clé API non configurée"
        if is_public then
            minetest.chat_send_all("<"..bot_name.."> " .. response)
        else
            minetest.chat_send_player(player_name, "# "..bot_name.." " .. response)
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

    local api_url = "https://api.perplexity.ai/chat/completions"
    local cleaned_key = api_key:gsub("%s+", "")
    local extra_headers = {
        "Authorization: Bearer " .. cleaned_key,
        "Content-Type: application/json",
        "Accept: application/json",
        "User-Agent: BotKopain/1.0"
    }

    local data = {
        model = "sonar",
        messages = {
            {role = "user", content = get_full_system_prompt(player_name, clean_message, is_public)}
        }
    }

    minetest.log("action", "[BotKopain] Envoi requête à Perplexity pour " .. player_name)

    http_api.fetch({
        url = api_url,
        method = "POST",
        data = minetest.write_json(data),
        extra_headers = extra_headers,
        timeout = 15,
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
            local error_msg = "Erreur de traitement de la réponse"
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
        process_perplexity_request(name, message, true)
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
        process_perplexity_request(name, param, false)
        return true
    end
})

-- Commande /status
minetest.register_chatcommand("status", {
    description = "Affiche les joueurs connectés",
    func = function(name)
        local players = minetest.get_connected_players()
        local player_list = {}

        for _, player in ipairs(players) do
            table.insert(player_list, player:get_player_name())
        end

        table.insert(player_list, bot_name)

        minetest.chat_send_player(name, "Joueurs en ligne ("..#player_list.."):")
        minetest.chat_send_player(name, table.concat(player_list, ", "))

        return true
    end
})

