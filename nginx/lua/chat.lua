-- nginx/lua/chat.lua - Single chat per user implementation with fixed Redis save
local cjson = require "cjson"

-- Auth verification function
local function verify_auth()
    local auth_header = ngx.var.http_authorization
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        ngx.log(ngx.ERR, "Chat: No Bearer token in Authorization header")
        return false, "No token provided"
    end

    local token = string.sub(auth_header, 8)
    local ok, payload = pcall(function()
        return cjson.decode(ngx.decode_base64(token))
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "Chat: Failed to decode token: " .. tostring(payload))
        return false, "Invalid token format"
    end
    
    if not payload.exp or payload.exp < ngx.time() then
        ngx.log(ngx.ERR, "Chat: Token expired. Exp: " .. tostring(payload.exp) .. ", Now: " .. ngx.time())
        return false, "Token expired"
    end

    -- Ensure user_id is set
    if not payload.user_id and payload.id then
        payload.user_id = payload.id
    end

    ngx.log(ngx.INFO, "Chat: Auth successful for user: " .. tostring(payload.username) .. ", user_id: " .. tostring(payload.user_id))
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
    ngx.log(ngx.ERR, "Chat error " .. status .. ": " .. tostring(message))
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

-- Get or create user's single chat
local function get_user_chat_id(user_id)
    -- Use a fixed chat ID pattern for single chat per user
    return "chat_" .. user_id
end

-- FIXED: Save chat to Redis without URL encoding for messages
local function handle_save_chat()
    ngx.log(ngx.INFO, "Chat: Handling save request")
    
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

    ngx.log(ngx.INFO, "Chat: Request body received, length: " .. #body)

    local ok, chat_data = pcall(cjson.decode, body)
    if not ok then
        ngx.log(ngx.ERR, "Chat: JSON decode failed: " .. tostring(chat_data))
        send_error_response(400, "Invalid JSON: " .. tostring(chat_data))
        return
    end

    -- Validate chat data
    if not chat_data.messages then
        send_error_response(400, "Missing messages")
        return
    end

    -- Use the user's single chat ID
    local user_chat_id = get_user_chat_id(payload.user_id)
    local chat_key = "chat:" .. user_chat_id
    
    -- FIXED: Prepare chat data for Redis without URL encoding messages
    local messages_json = cjson.encode(chat_data.messages)
    local title = chat_data.title or "My Chat"
    local timestamp = ngx.utctime()
    
    ngx.log(ngx.INFO, "Chat: Saving to Redis key: " .. chat_key)
    ngx.log(ngx.INFO, "Chat: Messages JSON length: " .. #messages_json)
    
    -- FIXED: Store messages directly without URL encoding
    -- Use Redis HSET multiple times instead of HMSET to avoid command line length issues
    local chat_id_result = ngx.location.capture("/redis-internal/hset/" .. chat_key .. "/id/" .. user_chat_id)
    local user_id_result = ngx.location.capture("/redis-internal/hset/" .. chat_key .. "/user_id/" .. payload.user_id)
    local title_result = ngx.location.capture("/redis-internal/hset/" .. chat_key .. "/title/" .. ngx.escape_uri(title))
    local created_result = ngx.location.capture("/redis-internal/hset/" .. chat_key .. "/created_at/" .. timestamp)
    local updated_result = ngx.location.capture("/redis-internal/hset/" .. chat_key .. "/updated_at/" .. timestamp)
    
    -- Save messages separately using a different approach to handle large JSON
    local messages_result = ngx.location.capture("/redis-internal/hset/" .. chat_key .. "/messages/" .. messages_json)

    ngx.log(ngx.INFO, "Chat: Redis HSET results - id:" .. chat_id_result.status .. " user_id:" .. user_id_result.status .. " messages:" .. messages_result.status)
    
    if chat_id_result.status ~= 200 or user_id_result.status ~= 200 or messages_result.status ~= 200 then
        ngx.log(ngx.ERR, "Chat: Redis HSET failed")
        if messages_result.status ~= 200 then
            ngx.log(ngx.ERR, "Chat: Messages save failed with status: " .. messages_result.status)
            ngx.log(ngx.ERR, "Chat: Messages response: " .. tostring(messages_result.body))
        end
        send_error_response(500, "Failed to save chat to Redis")
        return
    end

    ngx.log(ngx.INFO, "Chat: Successfully saved chat " .. user_chat_id)
    send_success_response({
        message = "Chat saved successfully",
        chat_id = user_chat_id
    })
end

-- FIXED: Load user's single chat from Redis without URL decoding messages
local function handle_load_chat()
    ngx.log(ngx.INFO, "Chat: Handling load request")
    
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "GET" then
        send_error_response(405, "Method not allowed")
        return
    end

    -- Get user's single chat ID
    local user_chat_id = get_user_chat_id(payload.user_id)
    local chat_key = "chat:" .. user_chat_id
    
    ngx.log(ngx.INFO, "Chat: Loading user's chat: " .. user_chat_id)

    -- Get chat data from Redis
    local result = ngx.location.capture("/redis-internal/hgetall/" .. chat_key)
    
    ngx.log(ngx.INFO, "Chat: Redis HGETALL status: " .. result.status)
    
    if result.status ~= 200 then
        send_error_response(500, "Failed to load chat from Redis")
        return
    end

    -- Parse Redis response
    local chat_data = parse_redis_hgetall(result.body)

    -- Check if chat exists
    if not chat_data.id then
        send_error_response(404, "Chat not found")
        return
    end

    -- FIXED: Parse messages JSON without URL decoding
    local messages = {}
    if chat_data.messages then
        local ok, parsed_messages = pcall(cjson.decode, chat_data.messages)
        if ok then
            messages = parsed_messages
        else
            ngx.log(ngx.ERR, "Chat: Failed to parse messages JSON")
            messages = {}
        end
    end

    -- Return chat data
    local response_data = {
        id = chat_data.id,
        user_id = chat_data.user_id,
        title = ngx.unescape_uri(chat_data.title or "My Chat"),  -- Title still uses URL encoding
        messages = messages,
        created_at = chat_data.created_at,
        updated_at = chat_data.updated_at
    }

    ngx.log(ngx.INFO, "Chat: Successfully loaded chat " .. user_chat_id .. " with " .. #messages .. " messages")
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(response_data))
end

-- Get current chat info (returns chat ID for frontend)
local function handle_get_current_chat()
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "GET" then
        send_error_response(405, "Method not allowed")
        return
    end

    -- Return user's single chat ID
    local user_chat_id = get_user_chat_id(payload.user_id)
    
    send_success_response({
        chat_id = user_chat_id,
        message = "Current chat ID"
    })
end

-- Clear chat (reset to empty)
local function handle_clear_chat()
    local ok, payload = verify_auth()
    if not ok then
        send_error_response(401, payload)
        return
    end

    if ngx.var.request_method ~= "POST" then
        send_error_response(405, "Method not allowed")
        return
    end

    -- Clear user's single chat
    local user_chat_id = get_user_chat_id(payload.user_id)
    local chat_key = "chat:" .. user_chat_id
    
    -- Delete the chat
    local delete_result = ngx.location.capture("/redis-internal/del/" .. chat_key)
    
    if delete_result.status == 200 then
        ngx.log(ngx.INFO, "Chat: Successfully cleared chat " .. user_chat_id)
        send_success_response({
            message = "Chat cleared successfully",
            chat_id = user_chat_id
        })
    else
        send_error_response(500, "Failed to clear chat")
    end
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

    -- Test Redis connectivity
    local redis_ok = false
    local redis_res = ngx.location.capture("/redis-internal/ping")
    if redis_res.status == 200 and redis_res.body:match("PONG") then
        redis_ok = true
    end
    
    -- Test Ollama connectivity
    local ollama_ok = false
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
        ngx.log(ngx.ERR, "Chat API: Authentication failed from " .. ngx.var.remote_addr)
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

ngx.log(ngx.INFO, "Chat: Processing " .. method .. " " .. uri)

-- Handle different endpoints
if uri == "/api/chat/save" and method == "POST" then
    handle_save_chat()
elseif uri == "/api/chat/load" and method == "GET" then
    handle_load_chat()
elseif uri == "/api/chat/current" and method == "GET" then
    handle_get_current_chat()
elseif uri == "/api/chat/clear" and method == "POST" then
    handle_clear_chat()
elseif uri == "/api/chat/test" and method == "GET" then
    handle_test()
elseif uri == "/api/chat" and method == "POST" then
    -- This is handled by the proxy configuration, not here
    handle_chat_proxy()
else
    -- For any other /api/chat/* endpoints, return 404
    ngx.log(ngx.WARN, "Chat: Unknown endpoint: " .. method .. " " .. uri)
    send_error_response(404, "Chat endpoint not found")
end