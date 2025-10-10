-- BotKopain Book Reader - Final version with simplified cleaning
-- Supports multiple book formats: default, homedecor, mineclonia, etc.

local readbooks = {}

-- Load the book player manager
local bookplayer_manager = dofile(minetest.get_modpath("botkopain") .. "/bookplayer_manager.lua")

-- XML escaping function
local function escape_xml(text)
    if not text then return "" end
    return text:gsub("&", "&amp;")
               :gsub("<", "&lt;")
               :gsub(">", "&gt;")
               :gsub("\"", "&quot;")
               :gsub("'", "&apos;")
end

-- Get all registered items that are books
local function get_book_items()
    local book_items = {}
    local registered_items = minetest.registered_items
    
    for item_name, item_def in pairs(registered_items) do
        local is_book = false
        
        if item_def.groups and item_def.groups.book and item_def.groups.book > 0 then
            is_book = true
        else
            local lower_name = item_name:lower()
            if lower_name:match("book") or lower_name:match("livre") then
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
        
        if node_def.groups and node_def.groups.book and node_def.groups.book > 0 then
            is_book = true
        elseif lower_name:match("book") or lower_name:match("livre") then
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

-- Extract book content from item metadata
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
    
    if content.type == "default" then
        if lower_name:match("written") then
            content.title = "Sample Written Book"
            content.text = "This is a sample written book from the default minetest game."
            content.author = "Unknown Author"
        else
            content.title = "Empty Book"
            content.text = "This is an empty book ready to be written."
        end
    elseif content.type == "mineclonia" then
        content.title = "Mineclonia Book"
        content.text = "This is a book from the Mineclonia game."
        content.author = "Mineclonia"
    elseif content.type == "homedecor" then
        content.title = "Homedecor Book"
        content.text = "This is a decorative book from the homedecor mod."
        content.author = "Homedecor"
    else
        content.title = "Unknown Book"
        content.text = "This book's content could not be determined."
    end
    
    return content
end

-- Clean Luanti formatting codes and special characters - SIMPLIFIED
local function clean_luanti_text(text)
    if not text or text == "" then return "" end
    
    -- Remove CDATA markers if present
    text = text:gsub("^<!%[CDATA%[", "")
    text = text:gsub("%]%]>$", "")
    
    -- Replace control characters with spaces instead of removing them
    text = text:gsub("[%z\x01-\x1f\x7f]", " ")
    
    -- Handle HTML entities - final simplified and robust approach
    
    -- 1. Handle the most common entities (apostrophes and quotes)
    text = text:gsub("&apos;", "'")
    text = text:gsub("&quot;", '"')
    
    -- 2. Handle numeric entities (decimal) - for apostrophes and quotes
    text = text:gsub("&#39;", "'")  -- apostrophe
    text = text:gsub("&#34;", '"')  -- quote
    
    -- 3. Handle other common entities
    text = text:gsub("&amp;", "&")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    
    -- 4. Handle numeric entities for the most common punctuation
    text = text:gsub("&#(%d+);", function(n) 
        n = tonumber(n)
        if n and n < 128 then
            return string.char(n)
        end
        return "&#" .. n .. ";"
    end)
    
    -- 5. Handle hex entities
    text = text:gsub("&#x(%x+);", function(h)
        local n = tonumber(h, 16)
        if n and n < 128 then
            return string.char(n)
        end
        return "&#x" .. h .. ";"
    end)
    
    -- 6. Clean up any remaining isolated & characters
    text = text:gsub("&(%s)", "%1")        -- & followed by space
    text = text:gsub("&([%p])", "%1")       -- & followed by punctuation
    text = text:gsub("^&", "")              -- & at start
    text = text:gsub("&$", "")              -- & at end
    
    -- Simple approach: just clean up spaces and basic formatting
    -- Don't try to be too smart about F/E patterns - they might be legitimate
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s*", "")
    text = text:gsub("%s*$", "")
    
    return text
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
        content.author = meta:get_string("player_name") ~= "" and meta:get_string("player_name") or "Unknown"
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
        elseif lower_name:match("book") or lower_name:match("livre") then
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
                                
                                -- Only add if it has real content
                                if book_content.text ~= "" or book_content.title ~= "" then
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
                                    
                                    -- Only add if it has real content
                                    if book_content.text ~= "" or book_content.title ~= "" then
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
                               (node_name:match("default") and node_name:match("bookshelf")) then
                                
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
                                                            
                                                            -- Only add if it has real content
                                                            if book_content.text ~= "" or book_content.title ~= "" then
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
        table.insert(xml_parts, '    <title>' .. escape_xml(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml(book.description) .. '</description>')
        table.insert(xml_parts, '    <text>' .. escape_xml(book.text) .. '</text>')
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
        table.insert(xml_parts, '    <title>' .. escape_xml(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml(book.description) .. '</description>')
        table.insert(xml_parts, '    <text>' .. escape_xml(book.text) .. '</text>')
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
        table.insert(xml_parts, '    <title>' .. escape_xml(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml(book.description) .. '</description>')
        table.insert(xml_parts, '    <text>' .. escape_xml(book.text) .. '</text>')
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

-- Export books organized by author to separate XML files
local function export_books_by_author()
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
    
    -- Organize books by author
    local books_by_author = {}
    for _, book in ipairs(all_books) do
        local author = book.author or "Unknown"
        if author == "" then author = "Unknown" end
        
        if not books_by_author[author] then
            books_by_author[author] = {}
        end
        table.insert(books_by_author[author], book)
    end
    
    -- Export each author's books to separate file
    local exported_files = {}
    local world_path = minetest.get_worldpath()
    
    for author, books in pairs(books_by_author) do
        -- Create XML for this author
        local xml_parts = {}
        table.insert(xml_parts, '<?xml version="1.0" encoding="UTF-8"?>')
        table.insert(xml_parts, '<books xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
        table.insert(xml_parts, '  <metadata>')
        table.insert(xml_parts, '    <export_date>' .. os.date("%Y-%m-%d %H:%M:%S") .. '</export_date>')
        table.insert(xml_parts, '    <game_version>' .. minetest.get_version().string .. '</game_version>')
        table.insert(xml_parts, '    <mod_name>botkopain</mod_name>')
        table.insert(xml_parts, '    <author>' .. escape_xml(author) .. '</author>')
        table.insert(xml_parts, '    <book_count>' .. #books .. '</book_count>')
        table.insert(xml_parts, '  </metadata>')
        
        -- Add all books by this author
        for _, book in ipairs(books) do
            table.insert(xml_parts, '  <book>')
            table.insert(xml_parts, '    <name>' .. escape_xml(book.node_name) .. '</name>')
            table.insert(xml_parts, '    <type>' .. escape_xml(book.type) .. '</type>')
            table.insert(xml_parts, '    <title>' .. escape_xml(book.title) .. '</title>')
            table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
            table.insert(xml_parts, '    <description>' .. escape_xml(book.description) .. '</description>')
            table.insert(xml_parts, '    <text>' .. escape_xml(book.text) .. '</text>')
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
        
        -- Sanitize author name for filename
        local safe_author = author:gsub("[^%w%-_]", "_")
        local file_path = world_path .. "/books_" .. safe_author .. ".xml"
        
        -- Try to write file
        local file = io.open(file_path, "w")
        if file then
            file:write(xml_content)
            file:close()
            table.insert(exported_files, {author = author, file = file_path, count = #books})
        else
            minetest.log("warning", "[BotKopain] Could not write file for author: " .. author)
        end
    end
    
    return exported_files
end

-- Main function to export books to XML file
function readbooks.export_books_to_xml()
    -- First, export by author to separate files
    local exported_files = export_books_by_author()
    
    if #exported_files == 0 then
        return false, "No books with content found to export"
    end
    
    -- Create summary
    local total_books = 0
    for _, file_info in ipairs(exported_files) do
        total_books = total_books + file_info.count
    end
    
    local message = "Exported " .. total_books .. " books by " .. #exported_files .. " authors:"
    for _, file_info in ipairs(exported_files) do
        message = message .. "\n  " .. file_info.author .. " (" .. file_info.count .. " books) -> " .. file_info.file
    end
    
    minetest.log("action", "[BotKopain] " .. message)
    return true, message
end

return readbooks