-- Book Player Manager for BotKopain
-- Manages a list of players whose books should be extracted

local bookplayer_manager = {}

-- Get mod storage for persistent data
local storage = minetest.get_mod_storage()

-- Get the list of managed players
function bookplayer_manager.get_managed_players()
    local players_json = storage:get_string("managed_players")
    if players_json == "" then
        return {}
    end
    
    local players = minetest.parse_json(players_json)
    if type(players) ~= "table" then
        return {}
    end
    
    return players
end

-- Save the list of managed players
local function save_managed_players(players)
    local players_json = minetest.write_json(players)
    storage:set_string("managed_players", players_json)
end

-- Check if a player is in the managed list
function bookplayer_manager.is_player_managed(player_name)
    local players = bookplayer_manager.get_managed_players()
    for _, name in ipairs(players) do
        if name == player_name then
            return true
        end
    end
    return false
end

-- Add a player to the managed list
function bookplayer_manager.add_player(player_name)
    local players = bookplayer_manager.get_managed_players()
    
    -- Check if player is already in the list
    for _, name in ipairs(players) do
        if name == player_name then
            return false, "Le joueur est déjà dans la liste"
        end
    end
    
    table.insert(players, player_name)
    save_managed_players(players)
    return true, "Joueur ajouté à la liste"
end

-- Remove a player from the managed list
function bookplayer_manager.remove_player(player_name)
    local players = bookplayer_manager.get_managed_players()
    local removed = false
    local new_players = {}
    
    for _, name in ipairs(players) do
        if name == player_name then
            removed = true
        else
            table.insert(new_players, name)
        end
    end
    
    if removed then
        save_managed_players(new_players)
        return true, "Joueur retiré de la liste"
    else
        return false, "Le joueur n'est pas dans la liste"
    end
end

return bookplayer_manager