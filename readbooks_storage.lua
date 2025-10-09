-- Alternative storage method using Luanti's mod storage API
-- This bypasses file system security restrictions

local readbooks_storage = {}

-- Get mod storage
local storage = minetest.get_mod_storage()

-- Save books data to mod storage
function readbooks_storage.save_books_to_storage(books_data)
    local json_data = minetest.write_json(books_data)
    storage:set_string("books_export", json_data)
    storage:set_string("export_date", os.date("%Y-%m-%d %H:%M:%S"))
    return true
end

-- Get books data from storage
function readbooks_storage.get_books_from_storage()
    local json_data = storage:get_string("books_export")
    if json_data == "" then
        return nil
    end
    return minetest.parse_json(json_data)
end

-- Generate XML from stored data
function readbooks_storage.generate_xml_from_storage()
    local books_data = readbooks_storage.get_books_from_storage()
    if not books_data then
        return nil, "No books data found in storage"
    end
    
    local xml_parts = {}
    
    -- XML header
    table.insert(xml_parts, '<?xml version="1.0" encoding="UTF-8"?>')
    table.insert(xml_parts, '<books xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
    table.insert(xml_parts, '  <metadata>')
    table.insert(xml_parts, '    <export_date>' .. (storage:get_string("export_date") or "unknown") .. '</export_date>')
    table.insert(xml_parts, '    <game_version>' .. minetest.get_version().string .. '</game_version>')
    table.insert(xml_parts, '    <mod_name>botkopain</mod_name>')
    table.insert(xml_parts, '  </metadata>')
    
    -- Add books from stored data
    for _, book in ipairs(books_data.books or {}) do
        table.insert(xml_parts, '  <book>')
        table.insert(xml_parts, '    <name>' .. escape_xml(book.name) .. '</name>')
        table.insert(xml_parts, '    <type>' .. escape_xml(book.type) .. '</type>')
        table.insert(xml_parts, '    <book_type>' .. escape_xml(book.book_type) .. '</book_type>')
        table.insert(xml_parts, '    <title>' .. escape_xml(book.title) .. '</title>')
        table.insert(xml_parts, '    <author>' .. escape_xml(book.author) .. '</author>')
        table.insert(xml_parts, '    <description>' .. escape_xml(book.description) .. '</description>')
        table.insert(xml_parts, '    <text><![CDATA[' .. book.text .. ']]></text>')
        table.insert(xml_parts, '    <pages>' .. book.pages .. '</pages>')
        table.insert(xml_parts, '  </book>')
    end
    
    table.insert(xml_parts, '</books>')
    
    return table.concat(xml_parts, "\n")
end

-- Export to chat (alternative to file writing)
function readbooks_storage.export_to_chat(player_name)
    local books_data = readbooks_storage.get_books_from_storage()
    if not books_data then
        return false, "No books data found"
    end
    
    minetest.chat_send_player(player_name, "=== BOOKS EXPORT ===")
    minetest.chat_send_player(player_name, "Total books found: " .. #books_data.books)
    
    for i, book in ipairs(books_data.books) do
        minetest.chat_send_player(player_name, string.format("%d. %s (%s) - %s", 
            i, book.name, book.book_type, book.title))
        if book.text and #book.text > 0 then
            minetest.chat_send_player(player_name, "   Text: " .. book.text:sub(1, 100) .. "...")
        end
    end
    
    return true, "Books data sent to chat"
end

return readbooks_storage