-- nginx/lua/chat.lua - Chat persistence with Redis
local cjson = require "cjson"

-- Auth verification function
local function verify_auth()
    local auth_header = ngx.var.http_authorization
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        return false, "No token provided"
    end

    local token = string.sub(auth_header, 8)
    local ok, payload = pcall(function()
        return cjson.decode(ngx.decode_base64(token))
    end)
    
    if not ok or not payload.exp or payload.exp < ngx.time() then
        return false, "Invalid or expired token"
    end

    return true, payload
end

-- Error response
local function send_error_response(status, message)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.header["X-Content-Type-Options"] = "nosniff"
    
    local response = {
        error = tostring(message),
        timestamp = ngx.utctime()
    }
    
    ngx.say(cjson.encode(response))
    ngx.log(ngx.WARN, "Chat error: " .. tostring(message))
end

-- Success response
local function send_success_response(data)
    ngx.header.content_type = "application/json"
    ngx.header["X-Content-Type-Options"] = "nosniff"
    
    local response = {
        success = true,
        timestamp = ngx.utctime()
    }
    
    for k, v in pairs(data) do
        response[k] = v
    end
    
    ngx.say(cjson.encode(response))
end

-- Generate chat ID
local function generate_chat_id(user_id)
    return "chat_" .. user_id .. "_" .. ngx.time() .. "_" .. tostring(math.random(100000, 999999))
end

-- Save chat to Redis
local function handle_save_chat()
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "POST" then
        send_error_response(405, "Method not allowed")
        return
    end

    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        send_error_response(400, "Request body required")
        return
    end

    local ok, chat_data = pcall(cjson.decode, body)
    if not ok then
        send_error_response(400, "Invalid JSON")
        return
    end

    -- Validate chat data
    if not chat_data.id or not chat_data.user_id or not chat_data.messages then
        send_error_response(400, "Missing required fields: id, user_id, messages")
        return
    end

    -- Verify user owns this chat
    if chat_data.user_id ~= payload.user_id then
        send_error_response(403, "Cannot save chat for different user")
        return
    end

    -- Generate chat key
    local chat_key = "chat:" .. chat_data.id
    local user_chats_key = "user_chats:" .. payload.user_id
    
    -- Prepare chat data for Redis
    local redis_data = {
        id = chat_data.id,
        user_id = chat_data.user_id,
        title = chat_data.title or "New Chat",
        messages = cjson.encode(chat_data.messages),
        created_at = chat_data.created_at or ngx.utctime(),
        updated_at = ngx.utctime()
    }

    -- Save chat data to Redis
    local save_result = ngx.location.capture("/redis-internal/hmset/" .. chat_key .. 
        "/id/" .. redis_data.id ..
        "/user_id/" .. redis_data.user_id ..
        "/title/" .. redis_data.title ..
        "/messages/" .. ngx.escape_uri(redis_data.messages) ..
        "/created_at/" .. redis_data.created_at ..
        "/updated_at/" .. redis_data.updated_at)

    if save_result.status ~= 200 then
        send_error_response(500, "Failed to save chat")
        return
    end

    -- Add chat to user's chat list
    local list_result = ngx.location.capture("/redis-internal/sadd/" .. user_chats_key .. "/" .. chat_data.id)
    
    if list_result.status == 200 then
        send_success_response({
            message = "Chat saved successfully",
            chat_id = chat_data.id
        })
    else
        send_error_response(500, "Chat saved but failed to update user chat list")
    end
end

-- Load chat from Redis
local function handle_load_chat()
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "GET" then
        send_error_response(405, "Method not allowed")
        return
    end

    -- Extract chat ID from URL
    local chat_id = ngx.var.uri:match("/api/chat/load/(.+)")
    if not chat_id then
        send_error_response(400, "Chat ID required")
        return
    end

    -- Get chat data from Redis
    local chat_key = "chat:" .. chat_id
    local result = ngx.location.capture("/redis-internal/hgetall/" .. chat_key)
    
    if result.status ~= 200 then
        send_error_response(404, "Chat not found")
        return
    end

    -- Parse user_id from Redis response
    local user_id = result.body:match("%$%d+\r?\n(.+)")
    if not user_id or user_id ~= payload.user_id then
        send_error_response(403, "Cannot delete chat belonging to different user")
        return
    end

    -- Delete chat from Redis
    local delete_result = ngx.location.capture("/redis-internal/del/" .. chat_key)
    
    if delete_result.status ~= 200 then
        send_error_response(500, "Failed to delete chat")
        return
    end

    -- Remove from user's chat list
    local user_chats_key = "user_chats:" .. payload.user_id
    local list_result = ngx.location.capture("/redis-internal/srem/" .. user_chats_key .. "/" .. chat_id)
    
    send_success_response({
        message = "Chat deleted successfully",
        chat_id = chat_id
    })
end

-- Route based on URI and method
local uri = ngx.var.uri
local method = ngx.var.request_method

if uri == "/api/chat/save" and method == "POST" then
    handle_save_chat()
elseif string.match(uri, "^/api/chat/load/") and method == "GET" then
    handle_load_chat()
elseif uri == "/api/chat/list" and method == "GET" then
    handle_list_chats()
elseif string.match(uri, "^/api/chat/delete/") and method == "DELETE" then
    handle_delete_chat()
else
    send_error_response(404, "Chat endpoint not found")
end500, "Failed to load chat")
        return
    end

    -- Parse Redis response
    local chat_data = {}
    local lines = {}
    for line in result.body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end

    local i = 1
    -- Skip array count
    if lines[i] and string.match(lines[i], "^%*%d+$") then
        i = i + 1
    end

    -- Parse key-value pairs
    while i <= #lines do
        if lines[i] and string.match(lines[i], "^%$%d+$") then
            i = i + 1
            if lines[i] then
                local key = lines[i]
                i = i + 1
                
                if lines[i] and string.match(lines[i], "^%$%d+$") then
                    i = i + 1
                    if lines[i] then
                        local value = lines[i]
                        chat_data[key] = value
                    end
                end
            end
        end
        i = i + 1
    end

    -- Check if chat exists
    if not chat_data.id then
        send_error_response(404, "Chat not found")
        return
    end

    -- Verify user owns this chat
    if chat_data.user_id ~= payload.user_id then
        send_error_response(403, "Cannot access chat belonging to different user")
        return
    end

    -- Parse messages JSON
    local messages = {}
    if chat_data.messages then
        local ok, parsed_messages = pcall(cjson.decode, ngx.unescape_uri(chat_data.messages))
        if ok then
            messages = parsed_messages
        end
    end

    -- Return chat data
    local response_data = {
        id = chat_data.id,
        user_id = chat_data.user_id,
        title = chat_data.title,
        messages = messages,
        created_at = chat_data.created_at,
        updated_at = chat_data.updated_at
    }

    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(response_data))
end

-- List user's chats
local function handle_list_chats()
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "GET" then
        send_error_response(405, "Method not allowed")
        return
    end

    -- Get user's chat list
    local user_chats_key = "user_chats:" .. payload.user_id
    local result = ngx.location.capture("/redis-internal/smembers/" .. user_chats_key)
    
    if result.status ~= 200 then
        send_error_response(500, "Failed to load chat list")
        return
    end

    -- Parse Redis response to get chat IDs
    local chat_ids = {}
    local lines = {}
    for line in result.body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end

    local i = 1
    -- Skip array count
    if lines[i] and string.match(lines[i], "^%*%d+$") then
        i = i + 1
    end

    -- Parse chat IDs
    while i <= #lines do
        if lines[i] and string.match(lines[i], "^%$%d+$") then
            i = i + 1
            if lines[i] then
                table.insert(chat_ids, lines[i])
            end
        end
        i = i + 1
    end

    -- Get chat details for each ID
    local chats = {}
    for _, chat_id in ipairs(chat_ids) do
        local chat_key = "chat:" .. chat_id
        local chat_result = ngx.location.capture("/redis-internal/hgetall/" .. chat_key)
        
        if chat_result.status == 200 then
            -- Parse chat data (simplified)
            local chat_info = {}
            local chat_lines = {}
            for line in chat_result.body:gmatch("[^\r\n]+") do
                if line and line ~= "" then
                    table.insert(chat_lines, line)
                end
            end

            -- Extract basic info
            for j = 1, #chat_lines do
                if chat_lines[j] == "id" and chat_lines[j + 2] then
                    chat_info.id = chat_lines[j + 2]
                elseif chat_lines[j] == "title" and chat_lines[j + 2] then
                    chat_info.title = chat_lines[j + 2]
                elseif chat_lines[j] == "created_at" and chat_lines[j + 2] then
                    chat_info.created_at = chat_lines[j + 2]
                elseif chat_lines[j] == "updated_at" and chat_lines[j + 2] then
                    chat_info.updated_at = chat_lines[j + 2]
                end
            end

            if chat_info.id then
                table.insert(chats, chat_info)
            end
        end
    end

    -- Sort chats by updated_at (most recent first)
    table.sort(chats, function(a, b)
        return (a.updated_at or "") > (b.updated_at or "")
    end)

    send_success_response({
        chats = chats,
        total = #chats
    })
end

-- Delete chat
local function handle_delete_chat()
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "DELETE" then
        send_error_response(405, "Method not allowed")
        return
    end

    -- Extract chat ID from URL
    local chat_id = ngx.var.uri:match("/api/chat/delete/(.+)")
    if not chat_id then
        send_error_response(400, "Chat ID required")
        return
    end

    -- Verify user owns this chat
    local chat_key = "chat:" .. chat_id
    local result = ngx.location.capture("/redis-internal/hget/" .. chat_key .. "/user_id")
    
    if result.status ~= 200 then
        send_error_response(