-- nginx/lua/chat_api.lua - Updated with unique guest users and chat limits
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"
local http = require "resty.http"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434"
local OLLAMA_MODEL = os.getenv("OLLAMA_MODEL") or "devstral"

-- Message expiry settings
local GUEST_MESSAGE_EXPIRY = 300 -- 5 minutes for guest messages
-- No expiry for regular user messages

-- Default limits
local DEFAULT_RATE_LIMIT = 60 -- messages per hour for registered users
local DEFAULT_MAX_TOKENS = 2048
local DEFAULT_TEMPERATURE = 0.7
local DEFAULT_TIMEOUT = 300

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function send_sse_chunk(data)
    if data == "[DONE]" then
        ngx.say("data: [DONE]\n")
    else
        ngx.say("data: " .. cjson.encode(data) .. "\n")
    end
    ngx.flush(true)
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        send_json(500, { error = "Internal server error", details = "Redis connection failed" })
    end
    return red
end

local function verify_user_token()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { error = "Authentication required" })
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { error = "Invalid token" })
    end
    
    local username = jwt_obj.payload.username
    local is_guest = jwt_obj.payload.is_guest or false
    local red = connect_redis()
    
    local user_key = is_guest and ("guest:" .. username) or ("user:" .. username)
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        send_json(401, { error = "User not found" })
    end
    
    local user = { is_guest = is_guest }
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user-- nginx/lua/chat_api.lua - Updated with shared guest and auto-expiring messages
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"
local http = require "resty.http"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434"
local OLLAMA_MODEL = os.getenv("OLLAMA_MODEL") or "devstral"

-- Import shared guest username
local unified_auth = require "unified_auth"
local SHARED_GUEST_USERNAME = unified_auth.SHARED_GUEST_USERNAME

-- Message expiry settings
local GUEST_MESSAGE_EXPIRY = 300 -- 5 minutes
local USER_MESSAGE_EXPIRY = 604800 -- 1 week

-- Default limits
local DEFAULT_RATE_LIMIT = 60 -- messages per hour for registered users
local DEFAULT_MAX_TOKENS = 2048
local DEFAULT_TEMPERATURE = 0.7
local DEFAULT_TIMEOUT = 300

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function send_sse_chunk(data)
    if data == "[DONE]" then
        ngx.say("data: [DONE]\n")
    else
        ngx.say("data: " .. cjson.encode(data) .. "\n")
    end
    ngx.flush(true)
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        send_json(500, { error = "Internal server error", details = "Redis connection failed" })
    end
    return red
end

local function verify_user_token()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { error = "Authentication required" })
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { error = "Invalid token" })
    end
    
    local username = jwt_obj.payload.username
    local is_guest = jwt_obj.payload.is_guest or false
    local red = connect_redis()
    
    local user_key = is_guest and ("guest:" .. username) or ("user:" .. username)
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        send_json(401, { error = "User not found" })
    end
    
    local user = { is_guest = is_guest }
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end
    
    -- Check if regular user is approved
    if not is_guest and user.is_approved ~= "true" then
        send_json(403, { error = "User not approved" })
    end
    
    return username, user, red
end

local function check_rate_limit(red, username, user)
    local is_guest = user.is_guest
    local time_window, message_limit
    
    if is_guest then
        -- Guest users: stricter limits
        time_window = tonumber(user.time_window) or 300 -- 5 minutes
        message_limit = tonumber(user.message_limit) or 1
    else
        -- Registered users: hourly limits
        time_window = 3600 -- 1 hour
        message_limit = DEFAULT_RATE_LIMIT
    end
    
    local current_time = ngx.time()
    local window_start = current_time - time_window
    
    -- For shared guest, use shared rate limiting key
    local rate_key = is_guest and ("guest_rate:" .. SHARED_GUEST_USERNAME) or ("user_rate:" .. username)
    
    -- Clean old entries and count current window
    red:zremrangebyscore(rate_key, 0, window_start)
    local current_count = red:zcard(rate_key)
    
    if current_count >= message_limit then
        local wait_time = time_window
        -- Get oldest message time for more accurate wait time
        local oldest = red:zrange(rate_key, 0, 0, "WITHSCORES")
        if oldest and #oldest >= 2 then
            wait_time = math.ceil(oldest[2] + time_window - current_time)
        end
        
        send_json(429, { 
            error = "Rate limit exceeded", 
            wait_time = wait_time,
            is_guest = is_guest,
            limit = message_limit,
            window = time_window,
            shared_chat = is_guest
        })
    end
    
    -- Add current message to rate limit tracking
    red:zadd(rate_key, current_time, current_time .. ":" .. math.random(1000, 9999))
    red:expire(rate_key, time_window + 60)
    
    return current_count + 1
end

local function save_message_to_history(red, username, role, content, is_guest)
    local current_time = ngx.time()
    local message_id = current_time .. ":" .. math.random(1000, 9999)
    
    -- For shared guest, use shared chat key
    local chat_key = is_guest and ("guest_chat:" .. SHARED_GUEST_USERNAME) or ("chat:" .. username)
    
    local message = {
        id = message_id,
        role = role,
        content = content,
        timestamp = os.date("!%Y-%m-%dT%TZ"),
        created_at = current_time
    }
    
    if is_guest then
        -- Guest messages: Use sorted set with timestamp for auto-expiry
        red:zadd(chat_key, current_time, cjson.encode(message))
        
        -- Set expiry for guest chat
        red:expire(chat_key, GUEST_MESSAGE_EXPIRY)
        
        -- Clean up expired guest messages immediately
        local expiry_cutoff = current_time - GUEST_MESSAGE_EXPIRY
        red:zremrangebyscore(chat_key, 0, expiry_cutoff)
        
        -- Limit guest messages (keep most recent 20)
        local total_messages = red:zcard(chat_key)
        if total_messages > 20 then
            red:zremrangebyrank(chat_key, 0, total_messages - 21)
        end
    else
        -- Regular user messages: Use list with NO expiry (permanent until manual clear)
        red:lpush(chat_key, cjson.encode(message))
        
        -- Limit user messages (keep most recent 100, but no time expiry)
        red:ltrim(chat_key, 0, 99)
        
        -- NO expiry for user chats - they persist until manually cleared
    end
end

local function get_chat_history(red, username, limit, is_guest)
    if is_guest then
        -- Guest chat: Use sorted set and clean expired messages
        local chat_key = "guest_chat:" .. SHARED_GUEST_USERNAME
        
        -- Clean expired guest messages first
        local current_time = ngx.time()
        local expiry_cutoff = current_time - GUEST_MESSAGE_EXPIRY
        red:zremrangebyscore(chat_key, 0, expiry_cutoff)
        
        -- Get recent guest messages (most recent first)
        limit = math.min(limit or 10, 10)
        local messages_data = red:zrevrange(chat_key, 0, limit - 1)
        local messages = {}
        
        for _, msg_data in ipairs(messages_data) do
            local message = cjson.decode(msg_data)
            table.insert(messages, {
                role = message.role,
                content = message.content,
                timestamp = message.timestamp
            })
        end
        
        -- Reverse to get chronological order
        local chronological = {}
        for i = #messages, 1, -1 do
            table.insert(chronological, messages[i])
        end
        
        return chronological
    else
        -- Regular user chat: Use list with NO expiry cleaning
        local chat_key = "chat:" .. username
        limit = math.min(limit or 20, 50)
        local history = red:lrange(chat_key, 0, limit - 1)
        local messages = {}
        
        -- Regular user messages stored in reverse chronological order in list
        for i = #history, 1, -1 do
            local message = cjson.decode(history[i])
            table.insert(messages, {
                role = message.role,
                content = message.content,
                timestamp = message.timestamp
            })
        end
        
        return messages
    end
end

local function call_ollama_streaming(messages, options, callback)
    local httpc = http.new()
    httpc:set_timeout((options.timeout or DEFAULT_TIMEOUT) * 1000)

    local payload = {
        model = OLLAMA_MODEL,
        messages = messages,
        stream = true,
        options = {
            temperature = options.temperature or DEFAULT_TEMPERATURE,
            num_predict = options.max_tokens or DEFAULT_MAX_TOKENS,
            num_ctx = tonumber(os.getenv("OLLAMA_CONTEXT_SIZE")) or 1024,
            num_gpu = tonumber(os.getenv("OLLAMA_GPU_LAYERS")) or 8,
            num_thread = tonumber(os.getenv("OLLAMA_NUM_THREAD")) or 6,
            num_batch = tonumber(os.getenv("OLLAMA_BATCH_SIZE")) or 64,
            use_mmap = false,
            use_mlock = true,
            top_p = tonumber(os.getenv("MODEL_TOP_P")) or 0.9,
            top_k = tonumber(os.getenv("MODEL_TOP_K")) or 40,
            repeat_penalty = tonumber(os.getenv("MODEL_REPEAT_PENALTY")) or 1.1
        }
    }

    local res, err = httpc:request({
        url = OLLAMA_URL .. "/api/chat",
        method = "POST",
        body = cjson.encode(payload),
        headers = { ["Content-Type"] = "application/json" }
    })

    if not res then
        return nil, "Failed to connect to AI service: " .. (err or "unknown")
    end

    local reader = res.body_reader
    if not reader then
        return nil, "No body reader available"
    end

    local accumulated = ""
    repeat
        local chunk, err = reader(8192)
        if not chunk then break end

        for line in chunk:gmatch("[^\r\n]+") do
            local ok, data = pcall(cjson.decode, line)
            if ok and data.message and data.message.content then
                accumulated = accumulated .. data.message.content
                callback({
                    content = data.message.content,
                    accumulated = accumulated,
                    done = data.done or false
                })
            end
        end

        if ngx.worker.exiting() or ngx.is_subrequest then
            break
        end
    until false

    httpc:close()
    return accumulated, nil
end

local function handle_chat_stream()
    local username, user, red = verify_user_token()
    
    ngx.req.read_body()
    local data = cjson.decode(ngx.req.get_body_data() or "{}")
    local message = data.message
    local include_history = data.include_history or false
    local options = data.options or {}

    if not message or message:match("^%s*$") then
        send_json(400, { error = "Message cannot be empty" })
    end

    -- Check rate limits (shared for guest users)
    local message_count = check_rate_limit(red, username, user)
    
    -- Update last active
    local user_key = user.is_guest and ("guest:" .. SHARED_GUEST_USERNAME) or ("user:" .. username)
    red:hset(user_key, "last_active", os.date("!%Y-%m-%dT%TZ"))

    -- Set response headers for streaming
    ngx.header.content_type = "text/plain"
    ngx.header.cache_control = "no-cache"
    ngx.header.connection = "keep-alive"
    ngx.header.access-- nginx/lua/chat_api.lua - Updated with guest user support
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"
local http = require "resty.http"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434"
local OLLAMA_MODEL = os.getenv("OLLAMA_MODEL") or "devstral"

-- Default limits
local DEFAULT_RATE_LIMIT = 60 -- messages per hour for registered users
local DEFAULT_MAX_TOKENS = 2048
local DEFAULT_TEMPERATURE = 0.7
local DEFAULT_TIMEOUT = 300

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function send_sse_chunk(data)
    if data == "[DONE]" then
        ngx.say("data: [DONE]\n")
    else
        ngx.say("data: " .. cjson.encode(data) .. "\n")
    end
    ngx.flush(true)
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        send_json(500, { error = "Internal server error", details = "Redis connection failed" })
    end
    return red
end

local function verify_user_token()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { error = "Authentication required" })
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { error = "Invalid token" })
    end
    
    local username = jwt_obj.payload.username
    local is_guest = jwt_obj.payload.is_guest or false
    local red = connect_redis()
    
    local user_key = is_guest and ("guest:" .. username) or ("user:" .. username)
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        send_json(401, { error = "User not found" })
    end
    
    local user = { is_guest = is_guest }
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end
    
    -- Check if regular user is approved
    if not is_guest and user.is_approved ~= "true" then
        send_json(403, { error = "User not approved" })
    end
    
    return username, user, red
end

local function check_rate_limit(red, username, user)
    local is_guest = user.is_guest
    local time_window, message_limit
    
    if is_guest then
        -- Guest users: stricter limits
        time_window = tonumber(user.time_window) or 300 -- 5 minutes
        message_limit = tonumber(user.message_limit) or 1
    else
        -- Registered users: hourly limits
        time_window = 3600 -- 1 hour
        message_limit = DEFAULT_RATE_LIMIT
    end
    
    local current_time = ngx.time()
    local window_start = current_time - time_window
    local count_key = (is_guest and "guest_messages:" or "user_messages:") .. username
    
    -- Clean old entries and count current window
    local messages = red:zrangebyscore(count_key, window_start, current_time)
    local current_count = #messages
    
    if current_count >= message_limit then
        local wait_time = time_window
        if #messages > 0 then
            -- Calculate actual wait time based on oldest message
            local oldest_score = red:zscore(count_key, messages[1])
            if oldest_score then
                wait_time = math.ceil(oldest_score + time_window - current_time)
            end
        end
        
        send_json(429, { 
            error = "Rate limit exceeded", 
            wait_time = wait_time,
            is_guest = is_guest,
            limit = message_limit,
            window = time_window
        })
    end
    
    -- Add current message to rate limit tracking
    red:zadd(count_key, current_time, current_time .. ":" .. math.random(1000, 9999))
    red:expire(count_key, time_window + 60) -- Keep slightly longer than window
    
    -- Clean old entries
    red:zremrangebyscore(count_key, 0, window_start)
    
    return current_count + 1
end

local function save_message_to_history(red, username, role, content, is_guest)
    local chat_key = (is_guest and "guest_chat:" or "chat:") .. username
    local message = {
        role = role,
        content = content,
        timestamp = os.date("!%Y-%m-%dT%TZ")
    }
    
    red:lpush(chat_key, cjson.encode(message))
    
    -- Different history limits for guests vs users
    local history_limit = is_guest and 10 or 50
    local ttl = is_guest and 3600 or 604800 -- 1 hour for guests, 1 week for users
    
    red:ltrim(chat_key, 0, history_limit - 1)
    red:expire(chat_key, ttl)
end

local function get_chat_history(red, username, limit, is_guest)
    limit = math.min(limit or 10, is_guest and 5 or 20) -- Limit guest history more
    local chat_key = (is_guest and "guest_chat:" or "chat:") .. username
    local history = red:lrange(chat_key, 0, limit - 1)
    local messages = {}
    
    for i = #history, 1, -1 do
        local message = cjson.decode(history[i])
        table.insert(messages, message)
    end
    
    return messages
end

local function call_ollama_streaming(messages, options, callback)
    local httpc = http.new()
    httpc:set_timeout((options.timeout or DEFAULT_TIMEOUT) * 1000)

    local payload = {
        model = OLLAMA_MODEL,
        messages = messages,
        stream = true,
        options = {
            temperature = options.temperature or DEFAULT_TEMPERATURE,
            num_predict = options.max_tokens or DEFAULT_MAX_TOKENS,
            num_ctx = tonumber(os.getenv("OLLAMA_CONTEXT_SIZE")) or 1024,
            num_gpu = tonumber(os.getenv("OLLAMA_GPU_LAYERS")) or 8,
            num_thread = tonumber(os.getenv("OLLAMA_NUM_THREAD")) or 6,
            num_batch = tonumber(os.getenv("OLLAMA_BATCH_SIZE")) or 64,
            use_mmap = false,
            use_mlock = true,
            top_p = tonumber(os.getenv("MODEL_TOP_P")) or 0.9,
            top_k = tonumber(os.getenv("MODEL_TOP_K")) or 40,
            repeat_penalty = tonumber(os.getenv("MODEL_REPEAT_PENALTY")) or 1.1
        }
    }

    local res, err = httpc:request({
        url = OLLAMA_URL .. "/api/chat",
        method = "POST",
        body = cjson.encode(payload),
        headers = { ["Content-Type"] = "application/json" }
    })

    if not res then
        return nil, "Failed to connect to AI service: " .. (err or "unknown")
    end

    local reader = res.body_reader
    if not reader then
        return nil, "No body reader available"
    end

    local accumulated = ""
    repeat
        local chunk, err = reader(8192)
        if not chunk then break end

        for line in chunk:gmatch("[^\r\n]+") do
            local ok, data = pcall(cjson.decode, line)
            if ok and data.message and data.message.content then
                accumulated = accumulated .. data.message.content
                callback({
                    content = data.message.content,
                    accumulated = accumulated,
                    done = data.done or false
                })
            end
        end

        if ngx.worker.exiting() or ngx.is_subrequest then
            break
        end
    until false

    httpc:close()
    return accumulated, nil
end

local function handle_chat_stream()
    local username, user, red = verify_user_token()
    
    ngx.req.read_body()
    local data = cjson.decode(ngx.req.get_body_data() or "{}")
    local message = data.message
    local include_history = data.include_history or false
    local options = data.options or {}

    if not message or message:match("^%s*$") then
        send_json(400, { error = "Message cannot be empty" })
    end

    -- Check rate limits (different for guests vs users)
    local message_count = check_rate_limit(red, username, user)
    
    -- Update last active
    local user_key = user.is_guest and ("guest:" .. username) or ("user:" .. username)
    red:hset(user_key, "last_active", os.date("!%Y-%m-%dT%TZ"))

    -- Set response headers for streaming
    ngx.header.content_type = "text/plain"
    ngx.header.cache_control = "no-cache"
    ngx.header.connection = "keep-alive"
    ngx.header.access_control_allow_origin = "*"

    -- Prepare options based on user type
    if user.is_guest then
        options.temperature = tonumber(user.temperature) or 0.3
        options.max_tokens = tonumber(user.max_tokens) or 100
        options.timeout = 60 -- Shorter timeout for guests
    else
        options.temperature = options.temperature or DEFAULT_TEMPERATURE
        options.max_tokens = options.max_tokens or DEFAULT_MAX_TOKENS
        options.timeout = DEFAULT_TIMEOUT
    end

    local messages = {}
    
    -- Add system prompt for guests
    if user.is_guest then
        table.insert(messages, {
            role = "system",
            content = "You are a helpful AI assistant. Keep responses concise and under 100 words. This is a demo conversation."
        })
    end

    -- Include history if requested (limited for guests)
    if include_history then
        local history = get_chat_history(red, username, 10, user.is_guest)
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    
    table.insert(messages, { role = "user", content = message })

    -- Save user message
    save_message_to_history(red, username, "user", message, user.is_guest)

    local accumulated = ""
    local final_response, err = call_ollama_streaming(messages, options, function(chunk)
        accumulated = chunk.accumulated
        send_sse_chunk({ 
            content = chunk.content, 
            done = chunk.done,
            is_guest = user.is_guest,
            remaining_messages = user.is_guest and (tonumber(user.message_limit) - message_count) or nil
        })
    end)

    if err then
        send_sse_chunk({ error = err })
    else
        save_message_to_history(red, username, "assistant", accumulated, user.is_guest)
    end

    send_sse_chunk("[DONE]")
    ngx.exit(200)
end

local function handle_chat_history()
    local username, user, red = verify_user_token()
    local limit = tonumber(ngx.var.arg_limit) or (user.is_guest and 5 or 20)
    local history = get_chat_history(red, username, limit, user.is_guest)
    
    send_json(200, {
        success = true,
        messages = history,
        count = #history,
        is_guest = user.is_guest
    })
end

local function handle_clear_chat()
    local username, user, red = verify_user_token()
    local chat_key = (user.is_guest and "guest_chat:" or "chat:") .. username
    red:del(chat_key)
    
    send_json(200, {
        success = true,
        message = "Chat history cleared",
        is_guest = user.is_guest
    })
end

local function handle_chat_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method

    if uri == "/api/chat/stream" and method == "POST" then
        handle_chat_stream()
    elseif uri == "/api/chat/history" and method == "GET" then
        handle_chat_history()
    elseif uri == "/api/chat/clear" and method == "POST" then
        handle_clear_chat()
    else
        send_json(404, { error = "Chat API endpoint not found" })
    end
end

return {
    handle_chat_api = handle_chat_api,
    handle_chat_stream = handle_chat_stream,
    handle_chat_history = handle_chat_history,
    handle_clear_chat = handle_clear_chat
}