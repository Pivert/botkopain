-- BotKopain Book Reader - Enhanced version with improved book detection and filtering
-- Supports multiple book formats: default, homedecor, mineclonia, etc.

local readbooks = {}

-- Load the book player manager
local bookplayer_manager = dofile(minetest.get_modpath("botkopain") .. "/bookplayer_manager.lua")

-- XML escaping function
local function escape_xml(text)
    if not text or text == "" then return "" end
    return text:gsub("&", "&amp;")
               :gsub("<", "&lt;")
               :gsub(">", "&gt;")
               :gsub("\"", "&quot;")
               :gsub("'", "&apos;")
end

-- XML escaping for text content (preserves decoded HTML entities)
local function escape_xml_text(text)
    if not text or text == "" then return "" end
    -- Only escape structural XML characters, preserve decoded entities
    text = text:gsub("&", "&amp;")  -- Must be first to avoid double-escaping
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    -- Don't escape quotes since we want to preserve decoded entities
    return text
end

-- Extract book content from item definition (for stats only)
local function extract_book_content(item_name, item_def)
    local content = {
        title = "",
        text = "",
        author = "",
        description = item_def.description or "",
        type = "unknown",
        pages = 0
    }
    
    local lower_name = item_name:lower()
    
    if lower_name:match("default:book_written") or lower_name:match("default:book") then
        content.type = "default"
    elseif lower_name:match("mcl_books:book") or lower_name:match("mcl_books:writable_book") then
        content.type = "mineclonia"
    elseif lower_name:match("homedecor:book") then
        content.type = "homedecor"
    elseif lower_name:match("book") then
        content.type = "generic"
    end
    
    return content
end

-- Enhanced HTML entity decoder
local function decode_html_entities(text)
    if not text or text == "" then return "" end
    
    -- Common HTML entities
    local entities = {
        ["&amp;"] = "&",
        ["&lt;"] = "<",
        ["&gt;"] = ">",
        ["&quot;"] = '"',
        ["&apos;"] = "'",
        ["&#39;"] = "'",
        ["&#34;"] = '"',
        ["&#38;"] = "&",
        ["&#60;"] = "<",
        ["&#62;"] = ">",
        ["&#160;"] = " ",
        ["&#161;"] = "¡",
        ["&#162;"] = "¢",
        ["&#163;"] = "£",
        ["&#164;"] = "¤",
        ["&#165;"] = "¥",
        ["&#166;"] = "¦",
        ["&#167;"] = "§",
        ["&#168;"] = "¨",
        ["&#169;"] = "©",
        ["&#170;"] = "ª",
        ["&#171;"] = "«",
        ["&#172;"] = "¬",
        ["&#173;"] = "",
        ["&#174;"] = "®",
        ["&#175;"] = "¯",
        ["&#176;"] = "°",
        ["&#177;"] = "±",
        ["&#178;"] = "²",
        ["&#179;"] = "³",
        ["&#180;"] = "´",
        ["&#181;"] = "µ",
        ["&#182;"] = "¶",
        ["&#183;"] = "·",
        ["&#184;"] = "¸",
        ["&#185;"] = "¹",
        ["&#186;"] = "º",
        ["&#187;"] = "»",
        ["&#188;"] = "¼",
        ["&#189;"] = "½",
        ["&#190;"] = "¾",
        ["&#191;"] = "¿",
        ["&#192;"] = "À",
        ["&#193;"] = "Á",
        ["&#194;"] = "Â",
        ["&#195;"] = "Ã",
        ["&#196;"] = "Ä",
        ["&#197;"] = "Å",
        ["&#198;"] = "Æ",
        ["&#199;"] = "Ç",
        ["&#200;"] = "È",
        ["&#201;"] = "É",
        ["&#202;"] = "Ê",
        ["&#203;"] = "Ë",
        ["&#204;"] = "Ì",
        ["&#205;"] = "Í",
        ["&#206;"] = "Î",
        ["&#207;"] = "Ï",
        ["&#208;"] = "Ð",
        ["&#209;"] = "Ñ",
        ["&#210;"] = "Ò",
        ["&#211;"] = "Ó",
        ["&#212;"] = "Ô",
        ["&#213;"] = "Õ",
        ["&#214;"] = "Ö",
        ["&#215;"] = "×",
        ["&#216;"] = "Ø",
        ["&#217;"] = "Ù",
        ["&#218;"] = "Ú",
        ["&#219;"] = "Û",
        ["&#220;"] = "Ü",
        ["&#221;"] = "Ý",
        ["&#222;"] = "Þ",
        ["&#223;"] = "ß",
        ["&#224;"] = "à",
        ["&#225;"] = "á",
        ["&#226;"] = "â",
        ["&#227;"] = "ã",
        ["&#228;"] = "ä",
        ["&#229;"] = "å",
        ["&#230;"] = "æ",
        ["&#231;"] = "ç",
        ["&#232;"] = "è",
        ["&#233;"] = "é",
        ["&#234;"] = "ê",
        ["&#235;"] = "ë",
        ["&#236;"] = "ì",
        ["&#237;"] = "í",
        ["&#238;"] = "î",
        ["&#239;"] = "ï",
        ["&#240;"] = "ð",
        ["&#241;"] = "ñ",
        ["&#242;"] = "ò",
        ["&#243;"] = "ó",
        ["&#244;"] = "ô",
        ["&#245;"] = "õ",
        ["&#246;"] = "ö",
        ["&#247;"] = "÷",
        ["&#248;"] = "ø",
        ["&#249;"] = "ù",
        ["&#250;"] = "ú",
        ["&#251;"] = "û",
        ["&#252;"] = "ü",
        ["&#253;"] = "ý",
        ["&#254;"] = "þ",
        ["&#255;"] = "ÿ",
        ["&nbsp;"] = " ",
        ["&iexcl;"] = "¡",
        ["&cent;"] = "¢",
        ["&pound;"] = "£",
        ["&curren;"] = "¤",
        ["&yen;"] = "¥",
        ["&brvbar;"] = "¦",
        ["&sect;"] = "§",
        ["&uml;"] = "¨",
        ["&copy;"] = "©",
        ["&ordf;"] = "ª",
        ["&laquo;"] = "«",
        ["&not;"] = "¬",
        ["&shy;"] = "",
        ["&reg;"] = "®",
        ["&macr;"] = "¯",
        ["&deg;"] = "°",
        ["&plusmn;"] = "±",
        ["&sup2;"] = "²",
        ["&sup3;"] = "³",
        ["&acute;"] = "´",
        ["&micro;"] = "µ",
        ["&para;"] = "¶",
        ["&middot;"] = "·",
        ["&cedil;"] = "¸",
        ["&sup1;"] = "¹",
        ["&ordm;"] = "º",
        ["&raquo;"] = "»",
        ["&frac14;"] = "¼",
        ["&frac12;"] = "½",
        ["&frac34;"] = "¾",
        ["&iquest;"] = "¿",
        ["&Agrave;"] = "À",
        ["&Aacute;"] = "Á",
        ["&Acirc;"] = "Â",
        ["&Atilde;"] = "Ã",
        ["&Auml;"] = "Ä",
        ["&Aring;"] = "Å",
        ["&AElig;"] = "Æ",
        ["&Ccedil;"] = "Ç",
        ["&Egrave;"] = "È",
        ["&Eacute;"] = "É",
        ["&Ecirc;"] = "Ê",
        ["&Euml;"] = "Ë",
        ["&Igrave;"] = "Ì",
        ["&Iacute;"] = "Í",
        ["&Icirc;"] = "Î",
        ["&Iuml;"] = "Ï",
        ["&ETH;"] = "Ð",
        ["&Ntilde;"] = "Ñ",
        ["&Ograve;"] = "Ò",
        ["&Oacute;"] = "Ó",
        ["&Ocirc;"] = "Ô",
        ["&Otilde;"] = "Õ",
        ["&Ouml;"] = "Ö",
        ["&times;"] = "×",
        ["&Oslash;"] = "Ø",
        ["&Ugrave;"] = "Ù",
        ["&Uacute;"] = "Ú",
        ["&Ucirc;"] = "Û",
        ["&Uuml;"] = "Ü",
        ["&Yacute;"] = "Ý",
        ["&THORN;"] = "Þ",
        ["&szlig;"] = "ß",
        ["&agrave;"] = "à",
        ["&aacute;"] = "á",
        ["&acirc;"] = "â",
        ["&atilde;"] = "ã",
        ["&auml;"] = "ä",
        ["&aring;"] = "å",
        ["&aelig;"] = "æ",
        ["&ccedil;"] = "ç",
        ["&egrave;"] = "è",
        ["&eacute;"] = "é",
        ["&ecirc;"] = "ê",
        ["&euml;"] = "ë",
        ["&igrave;"] = "ì",
        ["&iacute;"] = "í",
        ["&icirc;"] = "î",
        ["&iuml;"] = "ï",
        ["&eth;"] = "ð",
        ["&ntilde;"] = "ñ",
        ["&ograve;"] = "ò",
        ["&oacute;"] = "ó",
        ["&ocirc;"] = "ô",
        ["&otilde;"] = "õ",
        ["&ouml;"] = "ö",
        ["&divide;"] = "÷",
        ["&oslash;"] = "ø",
        ["&ugrave;"] = "ù",
        ["&uacute;"] = "ú",
        ["&ucirc;"] = "û",
        ["&uuml;"] = "ü",
        ["&yacute;"] = "ý",
        ["&thorn;"] = "þ",
        ["&yuml;"] = "ÿ"
    }
    
    -- Replace named entities
    for entity, char in pairs(entities) do
        text = text:gsub(entity, char)
    end
    
    -- Handle numeric entities (decimal)
    text = text:gsub("&#(%d+);", function(n)
        n = tonumber(n)
        if n and n >= 32 and n <= 126 then
            return string.char(n)
        elseif n and n >= 160 and n <= 255 then
            return string.char(n)
        end
        return "&#" .. n .. ";"
    end)
    
    -- Handle hex entities
    text = text:gsub("&#x([0-9a-fA-F]+);", function(h)
        local n = tonumber(h, 16)
        if n and n >= 32 and n <= 126 then
            return string.char(n)
        elseif n and n >= 160 and n <= 255 then
            return string.char(n)
        end
        return "&#x" .. h .. ";"
    end)
    
    return text
end

-- Clean Luanti formatting codes and special characters
local function clean_luanti_text(text)
    if not text or text == "" then return "" end
    
    -- Remove CDATA markers if present
    text = text:gsub("^<!%[CDATA%[", "")
    text = text:gsub("%]%]>$", "")
    
    -- Replace control characters with spaces
    text = text:gsub("[%z\x01-\x1f\x7f]", " ")
    
    -- Remove Luanti formatting codes
    text = text:gsub("%(T@[^)]+%)", "")  -- Remove (T@default) type codes
    text = text:gsub("^F", "")           -- Remove F at start (formatting)
    text = text:gsub("E$", "")           -- Remove E at end (formatting)
    text = text:gsub(" E ", " ")         -- Remove standalone E
    text = text:gsub(" F ", " ")         -- Remove standalone F
    
    -- Clean up spaces
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s*", "")
    text = text:gsub("%s*$", "")
    
    -- Decode HTML entities
    text = decode_html_entities(text)
    
    return text
end

-- Get all registered items that are books
local function get_book_items()
    local book_items = {}
    local registered_items = minetest.registered_items
    
    for item_name, item_def in pairs(registered_items) do
        local is_book = false
        
        -- Check book group
        if item_def.groups and item_def.groups.book and item_def.groups.book > 0 then
            is_book = true
        else
            -- Check name patterns for various book types
            local lower_name = item_name:lower()
            if lower_name:match("book") or lower_name:match("livre") or 
               lower_name:match("written_book") or lower_name:match("writable_book") or
               lower_name:match("book_written") or lower_name:match("book_empty") or
               lower_name:match("homedecor:book_") or lower_name:match("mcl_books:book") or
               lower_name:match("mcl_books:writable_book") or lower_name:match("mcl_books:written_book") then
                is_book = true
            elseif item_def.description and item_def.description:lower():match("book") then
                is_book = true
            end
        end
        
        if is_book then
            table.insert(book_items, {
                name = item_name,
                description = item_def.description or "No description",
                groups = item_def.groups or {}
            })
        end
    end
    
    return book_items
end

-- Get all registered book nodes
local function get_book_nodes()
    local book_nodes = {}
    local registered_nodes = minetest.registered_nodes
    
    for node_name, node_def in pairs(registered_nodes) do
        local is_book = false
        local lower_name = node_name:lower()
        
        -- Check book group
        if node_def.groups and node_def.groups.book and node_def.groups.book > 0 then
            is_book = true
        elseif lower_name:match("book") or lower_name:match("livre") or
               lower_name:match("homedecor:book_") or lower_name:match("bookshelf") or
               lower_name:match("mcl_bookshelf") or lower_name:match("default:bookshelf") then
            is_book = true
        elseif node_def.description and node_def.description:lower():match("book") then
            is_book = true
        end
        
        if is_book then
            table.insert(book_nodes, {
                name = node_name,
                description = node_def.description or "No description",
                groups = node_def.groups or {}
            })
        end
    end
    
    return book_nodes
end

-- Extract book content from ACTUAL node metadata
local function extract_book_content_from_meta(meta, item_name)
    local content = {
        title = "",
        text = "",
        author = "",
        description = "",
        type = "real_book",
        pages = 0,
        location = "unknown",
        coordinates = nil
    }
    
    if not meta then return content end
    
    -- Get actual book data from metadata - try multiple field names
    content.title = meta:get_string("title") ~= "" and meta:get_string("title") or ""
    content.text = meta:get_string("text") ~= "" and meta:get_string("text") or ""
    content.author = meta:get_string("owner") ~= "" and meta:get_string("owner") or ""
    content.description = meta:get_string("description") ~= "" and meta:get_string("description") or ""
    
    -- Try alternative field names if main ones are empty
    if content.title == "" then
        content.title = meta:get_string("book_title") ~= "" and meta:get_string("book_title") or ""
    end
    if content.title == "" then
        content.title = meta:get_string("name") ~= "" and meta:get_string("name") or "Untitled Book"
    end
    
    if content.text == "" then
        content.text = meta:get_string("book_text") ~= "" and meta:get_string("book_text") or ""
    end
    if content.text == "" then
        content.text = meta:get_string("content") ~= "" and meta:get_string("content") or ""
    end
    if content.text == "" then
        content.text = meta:get_string("pages") ~= "" and meta:get_string("pages") or ""
    end
    
    if content.author == "" then
        content.author = meta:get_string("author") ~= "" and meta:get_string("author") or ""
    end
    if content.author == "" then
        content.author = meta:get_string("book_author") ~= "" and meta:get_string("book_author") or ""
    end
    if content.author == "" then
        content.author = meta:get_string("player_name") ~= "" and meta:get_string("player_name") or ""
    end
    
    if content.description == "" then
        content.description = meta:get_string("infotext") ~= "" and meta:get_string("infotext") or ""
    end
    
    -- Clean up Luanti formatting codes and special characters
    content.title = clean_luanti_text(content.title)
    content.text = clean_luanti_text(content.text)
    content.description = clean_luanti_text(content.description)
    
    -- Count pages (approximation)
    if content.text and content.text ~= "" then
        content.pages = math.ceil(#content.text / 800) -- ~800 chars per page
    end
    
    return content
end

-- Check if a book has valid content and author
local function is_valid_book(book)
    -- Must have a real author (not empty, not "Unknown", not generic)
    if not book.author or book.author == "" or book.author == "Unknown" or 
       book.author:lower() == "unknown" or book.author:lower() == "player" then
        return false
    end
    
    -- Must have either title or text content
    if (not book.title or book.title == "" or book.title == "Untitled Book") and 
       (not book.text or book.text == "") then
        return false
    end
    
    return true
end

-- Scan the world for actual book nodes with metadata
local function scan_world_books()
    local world_books = {}
    local book_nodes_found = {}
    
    -- Get all registered nodes that might be books
    for node_name, node_def in pairs(minetest.registered_nodes) do
        local is_book = false
        local lower_name = node_name:lower()
        
        if node_def.groups and node_def.groups.book and node_def.groups.book > 0 then
            is_book = true
        elseif lower_name:match("book") or lower_name:match("livre") or
               lower_name:match("homedecor:book_") or lower_name:match("bookshelf") or
               lower_name:match("mcl_bookshelf") or lower_name:match("default:bookshelf") then
            is_book = true
        elseif node_def.description and node_def.description:lower():match("book") then
            is_book = true
        end
        
        if is_book then
            book_nodes_found[node_name] = true
        end
    end
    
    -- Scan loaded mapblocks for book nodes
    local players = minetest.get_connected_players()
    local scanned_positions = {}
    
    for _, player in ipairs(players) do
        local pos = player:get_pos()
        local player_name = player:get_player_name()
        
        -- Scan area around each player (16 nodes radius)
        for x = -16, 16 do
            for y = -8, 8 do
                for z = -16, 16 do
                    local scan_pos = {
                        x = math.floor(pos.x + x),
                        y = math.floor(pos.y + y),
                        z = math.floor(pos.z + z)
                    }
                    
                    -- Avoid scanning same position multiple times
                    local pos_key = scan_pos.x .. "," .. scan_pos.y .. "," .. scan_pos.z
                    if not scanned_positions[pos_key] then
                        scanned_positions[pos_key] = true
                        
                        local node = minetest.get_node_or_nil(scan_pos)
                        if node and book_nodes_found[node.name] then
                            -- Get node metadata
                            local meta = minetest.get_meta(scan_pos)
                            if meta then
                                local book_content = extract_book_content_from_meta(meta, node.name)
                                
                                -- Only add valid books with real content and author
                                if is_valid_book(book_content) then
                                    book_content.location = pos_key
                                    book_content.node_name = node.name
                                    book_content.coordinates = {
                                        x = scan_pos.x,
                                        y = scan_pos.y,
                                        z = scan_pos.z
                                    }
                                    table.insert(world_books, book_content)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return world_books
end

-- Scan player inventories for written books
local function scan_player_inventories()
    local inventory_books = {}
    local players = minetest.get_connected_players()
    
    -- Get managed players list
    local managed_players = bookplayer_manager.get_managed_players()
    local filter_enabled = #managed_players > 0
    
    for _, player in ipairs(players) do
        local player_name = player:get_player_name()
        
        -- Skip if filtering is enabled and player is not managed
        if filter_enabled and not bookplayer_manager.is_player_managed(player_name) then
            -- Skip this player
        else
            local inv = player:get_inventory()
            
            if inv then
                -- Scan main inventory
                local main_list = inv:get_list("main")
                if main_list then
                    for i, itemstack in ipairs(main_list) do
                        if not itemstack:is_empty() then
                            local item_name = itemstack:get_name()
                            local lower_name = item_name:lower()
                            
                            -- Check if it's a book item
                            if lower_name:match("book") and not lower_name:match("bookshelf") then
                                local meta = itemstack:get_meta()
                                if meta then
                                    local book_content = extract_book_content_from_meta(meta, item_name)
                                    
                                    -- Only add valid books with real content and author
                                    if is_valid_book(book_content) then
                                        book_content.location = "inventory:" .. player_name .. ":" .. i
                                        book_content.node_name = item_name
                                        book_content.owner = player_name
                                        book_content.coordinates = {
                                            source = "player_inventory",
                                            player = player_name,
                                            slot = i
                                        }
                                        table.insert(inventory_books, book_content)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return inventory_books
end

-- Scan containers (chests, bookshelves, etc.) for books
local function scan_containers()
    local container_books = {}
    local players = minetest.get_connected_players()
    local scanned_positions = {}
    
    for _, player in ipairs(players) do
        local pos = player:get_pos()
        
        -- Scan area around each player for containers
        for x = -16, 16 do
            for y = -8, 8 do
                for z = -16, 16 do
                    local scan_pos = {
                        x = math.floor(pos.x + x),
                        y = math.floor(pos.y + y),
                        z = math.floor(pos.z + z)
                    }
                    
                    -- Avoid scanning same position multiple times
                    local pos_key = scan_pos.x .. "," .. scan_pos.y .. "," .. scan_pos.z
                    if not scanned_positions[pos_key] then
                        scanned_positions[pos_key] = true
                        
                        local node = minetest.get_node_or_nil(scan_pos)
                        if node then
                            local node_name = node.name:lower()
                            
                            -- Check if it's a container (chest, bookshelf, etc.)
                            if node_name:match("chest") or node_name:match("bookshelf") or 
                               node_name:match("container") or node_name:match("box") or
                               (node_name:match("default") and node_name:match("bookshelf")) or
                               node_name:match("homedecor:bookshelf") or node_name:match("mcl_bookshelf") then
                                
                                local meta = minetest.get_meta(scan_pos)
                                if meta then
                                    -- Try to get inventory from metadata
                                    local inv = meta:get_inventory()
                                    if inv then
                                        -- Scan all lists in the inventory
                                        local lists = inv:get_lists()
                                        for list_name, list in pairs(lists) do
                                            for i, itemstack in ipairs(list) do
                                                if not itemstack:is_empty() then
                                                    local item_name = itemstack:get_name()
                                                    local lower_name = item_name:lower()
                                                    
                                                    -- Check if it's a book item
                                                    if lower_name:match("book") and not lower_name:match("bookshelf") then
                                                        local item_meta = itemstack:get_meta()
                                                        if item_meta then
                                                            local book_content = extract_book_content_from_meta(item_meta, item_name)
                                                            
                                                            -- Only add valid books with real content and author
                                                            if is_valid_book(book_content) then
                                                                book_content.location = "container:" .. pos_key .. ":" .. list_name .. ":" .. i
                                                                book_content.node_name = item_name
                                                                book_content.container_type = node.name
                                                                book_content.coordinates = {
                                                                    x = scan_pos.x,
                                                                    y = scan_pos.y,
                                                                    z = scan_pos.z
                                                                }
                                                                table.insert(container_books, book_content)
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return container_books
end

-- Generate XML content for book instances only (real books with content)
local function generate_books_xml()
    local xml_parts = {}
    
    -- XML header
    table.insert(xml_parts, '<?xml version="1.0" encoding="UTF-8"?>')
    table.insert(xml_parts, '<books xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
    table.insert(xml_parts, '  <metadata>')
    table.insert(xml_parts, '    <export_date>' .. os.date("%Y-%m-%d %H:%M:%S") .. '</export_date>')
    table.insert(xml_parts, '    <game_version>' .. minetest.get_version().string .. '</game_version>')
    table.insert(xml_parts, '    <mod_name>botkopain</mod_name>')
    table.insert(xml_parts, '  </metadata>')
    
    -- Scan for real books in the world
    local world_books = scan_world_books()
    local inventory_books = scan_player_inventories()
    local container_books = scan_containers()
    
    -- Add real books from world
    for _, book in ipairs(world_books) do
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(book.node_name) .. '</name>')
        table.insert(xml_parts, '    <type>world_instance</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(book.type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml_text(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml_text(book.description) .. '</description>')
        table.insert(xml_parts, '    <text>' .. escape_xml_text(book.text) .. '</text>')
        table.insert(xml_parts, '    <pages>' .. book.pages .. '</pages>')
        table.insert(xml_parts, '    <location>' .. escape_xml(book.location) .. '</location>')
        table.insert(xml_parts, '    <source>world</source>')
        if book.coordinates then
            table.insert(xml_parts, '    <coordinates>')
            table.insert(xml_parts, '      <x>' .. book.coordinates.x .. '</x>')
            table.insert(xml_parts, '      <y>' .. book.coordinates.y .. '</y>')
            table.insert(xml_parts, '      <z>' .. book.coordinates.z .. '</z>')
            table.insert(xml_parts, '    </coordinates>')
        end
        table.insert(xml_parts, '  </book>')
    end
    
    -- Add real books from inventories
    for _, book in ipairs(inventory_books) do
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(book.node_name) .. '</name>')
        table.insert(xml_parts, '    <type>inventory_instance</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(book.type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml_text(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml_text(book.description) .. '</description>')
        table.insert(xml_parts, '    <text>' .. escape_xml_text(book.text) .. '</text>')
        table.insert(xml_parts, '    <pages>' .. book.pages .. '</pages>')
        table.insert(xml_parts, '    <location>' .. escape_xml(book.location) .. '</location>')
        table.insert(xml_parts, '    <source>inventory</source>')
        if book.coordinates then
            table.insert(xml_parts, '    <coordinates>')
            table.insert(xml_parts, '      <source>' .. book.coordinates.source .. '</source>')
            table.insert(xml_parts, '      <player>' .. book.coordinates.player .. '</player>')
            table.insert(xml_parts, '      <slot>' .. book.coordinates.slot .. '</slot>')
            table.insert(xml_parts, '    </coordinates>')
        end
        table.insert(xml_parts, '  </book>')
    end
    
    -- Add real books from containers
    for _, book in ipairs(container_books) do
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(book.node_name) .. '</name>')
        table.insert(xml_parts, '    <type>container_instance</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(book.type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml_text(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml_text(book.description) .. '</description>')
        table.insert(xml_parts, '    <text>' .. escape_xml_text(book.text) .. '</text>')
        table.insert(xml_parts, '    <pages>' .. book.pages .. '</pages>')
        table.insert(xml_parts, '    <location>' .. escape_xml(book.location) .. '</location>')
        table.insert(xml_parts, '    <source>container</source>')
        table.insert(xml_parts, '    <container_type>' .. escape_xml(book.container_type) .. '</container_type>')
        if book.coordinates then
            table.insert(xml_parts, '    <coordinates>')
            table.insert(xml_parts, '      <x>' .. book.coordinates.x .. '</x>')
            table.insert(xml_parts, '      <y>' .. book.coordinates.y .. '</y>')
            table.insert(xml_parts, '      <z>' .. book.coordinates.z .. '</z>')
            table.insert(xml_parts, '    </coordinates>')
        end
        table.insert(xml_parts, '  </book>')
    end
    
    table.insert(xml_parts, '</books>')
    
    return table.concat(xml_parts, "\n")
end

-- Get book statistics (including real instances)
function readbooks.get_book_stats()
    local book_items = get_book_items()
    local book_nodes = get_book_nodes()
    local world_books = scan_world_books()
    local inventory_books = scan_player_inventories()
    local container_books = scan_containers()
    
    local stats = {
        total_definitions = #book_items + #book_nodes,
        total_world_books = #world_books,
        total_inventory_books = #inventory_books,
        total_container_books = #container_books,
        total_real_books = #world_books + #inventory_books + #container_books,
        total_books = #book_items + #book_nodes + #world_books + #inventory_books + #container_books,
        item_types = {},
        node_types = {},
        world_book_authors = {},
        inventory_book_authors = {},
        container_book_authors = {}
    }
    
    -- Count definition types
    for _, item in ipairs(book_items) do
        local content = extract_book_content(item.name, item)
        stats.item_types[content.type] = (stats.item_types[content.type] or 0) + 1
    end
    
    for _, node in ipairs(book_nodes) do
        local content = extract_book_content(node.name, node)
        stats.node_types[content.type] = (stats.node_types[content.type] or 0) + 1
    end
    
    -- Count real book authors
    for _, book in ipairs(world_books) do
        if book.author and book.author ~= "" then
            stats.world_book_authors[book.author] = (stats.world_book_authors[book.author] or 0) + 1
        end
    end
    
    for _, book in ipairs(inventory_books) do
        if book.author and book.author ~= "" then
            stats.inventory_book_authors[book.author] = (stats.inventory_book_authors[book.author] or 0) + 1
        end
    end
    
    for _, book in ipairs(container_books) do
        if book.author and book.author ~= "" then
            stats.container_book_authors[book.author] = (stats.container_book_authors[book.author] or 0) + 1
        end
    end
    
    return stats
end

-- Export all books to a single XML file
local function export_books_to_single_file()
    -- Scan for all real books
    local world_books = scan_world_books()
    local inventory_books = scan_player_inventories()
    local container_books = scan_containers()
    
    -- Combine all real books
    local all_books = {}
    for _, book in ipairs(world_books) do
        table.insert(all_books, book)
    end
    for _, book in ipairs(inventory_books) do
        table.insert(all_books, book)
    end
    for _, book in ipairs(container_books) do
        table.insert(all_books, book)
    end
    
    if #all_books == 0 then
        return false, "No books with content found to export"
    end
    
    -- Create single XML file with all books
    local xml_parts = {}
    table.insert(xml_parts, '<?xml version="1.0" encoding="UTF-8"?>')
    table.insert(xml_parts, '<books xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
    table.insert(xml_parts, '  <metadata>')
    table.insert(xml_parts, '    <export_date>' .. os.date("%Y-%m-%d %H:%M:%S") .. '</export_date>')
    table.insert(xml_parts, '    <game_version>' .. minetest.get_version().string .. '</game_version>')
    table.insert(xml_parts, '    <mod_name>botkopain</mod_name>')
    table.insert(xml_parts, '    <total_books>' .. #all_books .. '</total_books>')
    table.insert(xml_parts, '  </metadata>')
    
    -- Add all books
    for _, book in ipairs(all_books) do
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(book.node_name) .. '</name>')
        table.insert(xml_parts, '    <type>' .. escape_xml(book.type) .. '</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(book.book_type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml_text(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml_text(book.description) .. '</description>')
        table.insert(xml_parts, '    <text>' .. escape_xml_text(book.text) .. '</text>')
        table.insert(xml_parts, '    <pages>' .. book.pages .. '</pages>')
        table.insert(xml_parts, '    <location>' .. escape_xml(book.location) .. '</location>')
        table.insert(xml_parts, '    <source>' .. escape_xml(book.source) .. '</source>')
        
        if book.container_type then
            table.insert(xml_parts, '    <container_type>' .. escape_xml(book.container_type) .. '</container_type>')
        end
        
        if book.coordinates then
            table.insert(xml_parts, '    <coordinates>')
            if book.coordinates.x then
                table.insert(xml_parts, '      <x>' .. book.coordinates.x .. '</x>')
                table.insert(xml_parts, '      <y>' .. book.coordinates.y .. '</y>')
                table.insert(xml_parts, '      <z>' .. book.coordinates.z .. '</z>')
            else
                for key, value in pairs(book.coordinates) do
                    table.insert(xml_parts, '      <' .. key .. '>' .. escape_xml(tostring(value)) .. '</' .. key .. '>')
                end
            end
            table.insert(xml_parts, '    </coordinates>')
        end
        table.insert(xml_parts, '  </book>')
    end
    
    table.insert(xml_parts, '</books>')
    
    local xml_content = table.concat(xml_parts, "\n")
    
    -- Write to single file
    local world_path = minetest.get_worldpath()
    local file_path = world_path .. "/books.xml"
    
    local file = io.open(file_path, "w")
    if not file then
        return false, "Could not write to books.xml in world directory"
    end
    
    file:write(xml_content)
    file:close()
    
    return true, file_path, #all_books
end

-- Main function to export books to XML file
function readbooks.export_books_to_xml()
    -- Export all books to single file
    local success, file_path, total_books = export_books_to_single_file()
    
    if not success then
        return false, file_path  -- file_path contains error message in this case
    end
    
    local message = "Exported " .. total_books .. " books to: " .. file_path
    minetest.log("action", "[BotKopain] " .. message)
    return true, message
end

return readbooks