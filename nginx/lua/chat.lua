-- nginx/lua/chat.lua - Complete chat functionality including persistence and proxying
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

-- Parse Redis HGETALL response
local function parse_redis_hgetall(body)
    if not body or body == "" or body == "$-1" then
        return {}
    end
    
    local lines = {}
    for line in body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end
    
    local result = {}
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
                        result[key] = value
                    end
                end
            end
        end
        i = i + 1
    end
    
    return result
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
    local messages_json = cjson.encode(chat_data.messages)
    local title = chat_data.title or "New Chat"
    local timestamp = ngx.utctime()
    
    -- Save chat data to Redis
    local save_result = ngx.location.capture("/redis-internal/hmset/" .. chat_key .. 
        "/id/" .. chat_data.id ..
        "/user_id/" .. chat_data.user_id ..
        "/title/" .. ngx.escape_uri(title) ..
        "/messages/" .. ngx.escape_uri(messages_json) ..
        "/created_at/" .. (chat_data.created_at or timestamp) ..
        "/updated_at/" .. timestamp)

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
        send_error_response(500, "Failed to load chat")
        return
    end

    -- Parse Redis response
    local chat_data = parse_redis_hgetall(result.body)

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
        title = ngx.unescape_uri(chat_data.title or "New Chat"),
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
            local chat_info = parse_redis_hgetall(chat_result.body)
            if chat_info.id then
                table.insert(chats, {
                    id = chat_info.id,
                    title = ngx.unescape_uri(chat_info.title or "New Chat"),
                    created_at = chat_info.created_at,
                    updated_at = chat_info.updated_at
                })
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
    local result = ngx.location.capture("/redis-internal/hgetall/" .. chat_key)
    
    if result.status ~= 200 then
        send_error_response(404, "Chat not found")
        return
    end

    local chat_data = parse_redis_hgetall(result.body)
    if not chat_data.id or chat_data.user_id ~= payload.user_id then
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

-- Test endpoint
local function handle_test()
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "GET" then
        send_error_response(405, "Method not allowed")
        return
    end

    -- Test both Redis and Ollama connectivity
    local redis_ok = false
    local ollama_ok = false
    
    -- Test Redis
    local redis_res = ngx.location.capture("/redis-internal/ping")
    if redis_res.status == 200 and redis_res.body:match("PONG") then
        redis_ok = true
    end
    
    -- Test Ollama
    local ollama_res = ngx.location.capture("/proxy-ollama-tags")
    if ollama_res.status == 200 then
        ollama_ok = true
    end
    
    local status = "ok"
    local message = "Chat services are operational"
    
    if not redis_ok then
        status = "error"
        message = "Redis connection failed"
    elseif not ollama_ok then
        status = "warning"
        message = "AI service may be unavailable"
    end
    
    ngx.header.content_type = "application/json"
    ngx.say('{"message": {"content": "' .. message .. '"}, "status": "' .. status .. '", "redis": ' .. (redis_ok and "true" or "false") .. ', "ollama": ' .. (ollama_ok and "true" or "false") .. ', "timestamp": "' .. ngx.utctime() .. '"}')
end

-- Main chat proxy handler (for /api/chat requests that go to Ollama)
local function handle_chat_proxy()
    local ok, payload = verify_auth()
    if not ok then
        ngx.log(ngx.ERR, "Chat API: No valid authorization from " .. ngx.var.remote_addr)
        ngx.status = 401
        ngx.header.content_type = "application/json"
        ngx.say('{"error": "Authentication required"}')
        return
    end

    ngx.log(ngx.INFO, "Chat API: Authentication successful for " .. (payload.username or "unknown"))
    
    -- This function is called from access_by_lua_block, so we just return success
    -- The actual proxying is handled by nginx proxy_pass
    return
end

-- Route based on URI and method
local uri = ngx.var.uri
local method = ngx.var.request_method

-- Handle different endpoints
if uri == "/api/chat/save" and method == "POST" then
    handle_save_chat()
elseif string.match(uri, "^/api/chat/load/") and method == "GET" then
    handle_load_chat()
elseif uri == "/api/chat/list" and method == "GET" then
    handle_list_chats()
elseif string.match(uri, "^/api/chat/delete/") and method == "DELETE" then
    handle_delete_chat()
elseif uri == "/api/chat/test" and method == "GET" then
    handle_test()
elseif uri == "/api/chat" and method == "POST" then
    -- This is handled by the proxy configuration, not here
    handle_chat_proxy()
else
    -- For any other /api/chat/* endpoints, return 404
    send_error_response(404, "Chat endpoint not found")
end