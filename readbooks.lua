-- BotKopain Book Reader - Extract all books from the game and save to XML
-- Supports multiple book formats: default, homedecor, mineclonia, etc.

local readbooks = {}

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
        -- Check if item is a book by groups or name patterns
        local is_book = false
        
        -- Check groups
        if item_def.groups then
            if item_def.groups.book and item_def.groups.book > 0 then
                is_book = true
            end
        end
        
        -- Check name patterns
        if not is_book then
            local lower_name = item_name:lower()
            if lower_name:match("book") or lower_name:match("livre") then
                is_book = true
            end
        end
        
        -- Check description patterns
        if not is_book and item_def.description then
            local desc = item_def.description:lower()
            if desc:match("book") or desc:match("livre") or desc:match("cahier") then
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

-- Get all registered book nodes (for homedecor style books)
local function get_book_nodes()
    local book_nodes = {}
    local registered_nodes = minetest.registered_nodes
    
    for node_name, node_def in pairs(registered_nodes) do
        -- Check if node is a book by name patterns or groups
        local is_book = false
        
        -- Check groups
        if node_def.groups then
            if node_def.groups.book and node_def.groups.book > 0 then
                is_book = true
            end
        end
        
        -- Check name patterns
        if not is_book then
            local lower_name = node_name:lower()
            if lower_name:match("book") or lower_name:match("livre") then
                is_book = true
            end
        end
        
        -- Check description patterns
        if not is_book and node_def.description then
            local desc = node_def.description:lower()
            if desc:match("book") or desc:match("livre") or desc:match("cahier") then
                is_book = true
            end
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
    
    -- Try to determine book type based on item name and properties
    local lower_name = item_name:lower()
    
    -- Default minetest book
    if lower_name:match("default:book_written") or lower_name:match("default:book") then
        content.type = "default"
    -- Mineclonia books
    elseif lower_name:match("mcl_books:book") or lower_name:match("mcl_books:writable_book") then
        content.type = "mineclonia"
    -- Homedecor books
    elseif lower_name:match("homedecor:book") then
        content.type = "homedecor"
    -- Generic book detection
    elseif lower_name:match("book") then
        content.type = "generic"
    end
    
    -- Try to get default content based on type
    if content.type == "default" then
        -- Default books often have sample content
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

-- Extract book content from ACTUAL node metadata (for real books in the world)
local function extract_book_content_from_meta(meta, item_name)
    local content = {
        title = "",
        text = "",
        author = "",
        description = "",
        type = "real_book",
        pages = 0,
        location = "unknown"
    }
    
    if not meta then return content end
    
    -- Get actual book data from metadata
    content.title = meta:get_string("title") or ""
    content.text = meta:get_string("text") or ""
    content.author = meta:get_string("owner") or meta:get_string("author") or ""
    content.description = meta:get_string("description") or ""
    
    -- Handle different book formats
    if content.title == "" and content.text == "" then
        -- Try alternative field names
        content.title = meta:get_string("book_title") or "Untitled Book"
        content.text = meta:get_string("book_text") or meta:get_string("content") or ""
        content.author = meta:get_string("book_author") or meta:get_string("player_name") or "Unknown"
    end
    
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
        
        -- Check if it's a book node
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
    
    for _, player in ipairs(players) do
        local player_name = player:get_player_name()
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
                                    table.insert(inventory_books, book_content)
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

-- Generate XML content for all books (including real instances)
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
    
    -- Add real books from world
    for _, book in ipairs(world_books) do
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(book.node_name) .. '</name>')
        table.insert(xml_parts, '    <type>world_instance</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(book.type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml(book.description) .. '</description>')
        table.insert(xml_parts, '    <text><![CDATA[' .. book.text .. ']]></text>')
        table.insert(xml_parts, '    <pages>' .. book.pages .. '</pages>')
        table.insert(xml_parts, '    <location>' .. escape_xml(book.location) .. '</location>')
        table.insert(xml_parts, '    <source>world</source>')
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
        table.insert(xml_parts, '    <text><![CDATA[' .. book.text .. ']]></text>')
        table.insert(xml_parts, '    <pages>' .. book.pages .. '</pages>')
        table.insert(xml_parts, '    <location>' .. escape_xml(book.location) .. '</location>')
        table.insert(xml_parts, '    <source>inventory</source>')
        table.insert(xml_parts, '  </book>')
    end
    
    -- Also include book definitions for reference
    local book_items = get_book_items()
    local book_nodes = get_book_nodes()
    
    -- Process book item definitions
    for _, item in ipairs(book_items) do
        local content = extract_book_content(item.name, item)
        
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(item.name) .. '</name>')
        table.insert(xml_parts, '    <type>item_definition</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(content.type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml(content.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(content.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml(content.description) .. '</description>')
        table.insert(xml_parts, '    <text><![CDATA[' .. content.text .. ']]></text>')
        table.insert(xml_parts, '    <pages>' .. content.pages .. '</pages>')
        table.insert(xml_parts, '    <source>definition</source>')
        
        -- Add groups information
        if next(item.groups) then
            table.insert(xml_parts, '    <groups>')
            for group_name, group_value in pairs(item.groups) do
                table.insert(xml_parts, '      <group name="' .. escape_xml(group_name) .. '">' .. group_value .. '</group>')
            end
            table.insert(xml_parts, '    </groups>')
        end
        
        table.insert(xml_parts, '  </book>')
    end
    
    -- Process book node definitions
    for _, node in ipairs(book_nodes) do
        local content = extract_book_content(node.name, node)
        
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(node.name) .. '</name>')
        table.insert(xml_parts, '    <type>node_definition</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(content.type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml(content.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(content.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml(content.description) .. '</description>')
        table.insert(xml_parts, '    <text><![CDATA[' .. content.text .. ']]></text>')
        table.insert(xml_parts, '    <pages>' .. content.pages .. '</pages>')
        table.insert(xml_parts, '    <source>definition</source>')
        
        -- Add groups information
        if next(node.groups) then
            table.insert(xml_parts, '    <groups>')
            for group_name, group_value in pairs(node.groups) do
                table.insert(xml_parts, '      <group name="' .. escape_xml(group_name) .. '">' .. group_value .. '</group>')
            end
            table.insert(xml_parts, '    </groups>')
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
    
    local stats = {
        total_definitions = #book_items + #book_nodes,
        total_world_books = #world_books,
        total_inventory_books = #inventory_books,
        total_real_books = #world_books + #inventory_books,
        total_books = #book_items + #book_nodes + #world_books + #inventory_books,
        item_types = {},
        node_types = {},
        world_book_authors = {},
        inventory_book_authors = {}
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
    
    return stats
end

-- Main function to export books to XML file
function readbooks.export_books_to_xml()
    local xml_content = generate_books_xml()
    
    -- Try to write to world directory first
    local file_path = minetest.get_worldpath() .. "/books.xml"
    local file, err = io.open(file_path, "w")
    
    if not file then
        -- If file writing fails (due to security), use mod storage as fallback
        minetest.log("warning", "[BotKopain] File writing blocked by security, using mod storage fallback")
        
        -- Store in mod storage
        local storage = minetest.get_mod_storage()
        storage:set_string("books_xml", xml_content)
        storage:set_string("export_date", os.date("%Y-%m-%d %H:%M:%S"))
        
        -- Count books exported (including real instances)
        local book_items = get_book_items()
        local book_nodes = get_book_nodes()
        local world_books = scan_world_books()
        local inventory_books = scan_player_inventories()
        local total_books = #book_items + #book_nodes + #world_books + #inventory_books
        
        minetest.log("action", "[BotKopain] Stored " .. total_books .. " books in mod storage")
        return true, "Stored " .. total_books .. " books in mod storage (file access blocked by security)"
    end
    
    file:write(xml_content)
    file:close()
    
    -- Count books exported (including real instances)
    local book_items = get_book_items()
    local book_nodes = get_book_nodes()
    local world_books = scan_world_books()
    local inventory_books = scan_player_inventories()
    local total_books = #book_items + #book_nodes + #world_books + #inventory_books
    
    minetest.log("action", "[BotKopain] Exported " .. total_books .. " books to " .. file_path)
    return true, "Exported " .. total_books .. " books to " .. file_path
end

return readbooks