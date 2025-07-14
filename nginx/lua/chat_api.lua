-- nginx/lua/chat_api_unified.lua - Chat API with unified session management
local cjson = require "cjson"
local redis = require "resty.redis"
local http = require "resty.http"
local session_manager = require "unified_session_manager"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
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
    
    -- Update session activity during streaming
    local session_id = ngx.var.sse_session_id
    if session_id then
        session_manager.update_session_activity(session_id)
    end
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.log(ngx.WARN, "Redis connection failed: " .. (err or "unknown"))
        return nil, err
    end
    return red, nil
end

local function check_rate_limit_user(red, username)
    local time_window = 3600 -- 1 hour
    local message_limit = DEFAULT_RATE_LIMIT
    local current_time = ngx.time()
    local window_start = current_time - time_window
    local count_key = "user_messages:" .. username
    
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

local function check_rate_limit_guest(username)
    local success, message = session_manager.use_guest_message(username)
    if not success then
        local limits = session_manager.get_guest_limits(username)
        if not limits then
            send_json(401, { error = "Guest session expired" })
        else
            send_json(429, { 
                error = "Guest message limit exceeded",
                limit = limits.max_messages,
                used = limits.used_messages,
                session_remaining = limits.session_remaining
            })
        end
    end
    return true
end

local function save_message_to_redis(red, username, role, content)
    if not red then
        ngx.log(ngx.WARN, "Cannot save message - Redis unavailable")
        return false
    end
    
    local chat_key = "chat:" .. username
    local message = {
        role = role,
        content = content,
        timestamp = os.date("!%Y-%m-%dT%TZ")
    }
    
    red:lpush(chat_key, cjson.encode(message))
    red:ltrim(chat_key, 0, 49) -- Keep last 50 messages
    red:expire(chat_key, 604800) -- 1 week
    return true
end

local function get_chat_history_from_redis(red, username, limit)
    if not red then
        return {} -- Return empty history if Redis unavailable
    end
    
    limit = math.min(limit or 20, 50)
    local chat_key = "chat:" .. username
    local history = red:lrange(chat_key, 0, limit - 1)
    local messages = {}
    
    for i = #history, 1, -1 do
        local ok, message = pcall(cjson.decode, history[i])
        if ok then
            table.insert(messages, message)
        end
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

    local url = OLLAMA_URL .. "/api/chat"
    local res, err = httpc:request_uri(url, {
        method = "POST",
        body = cjson.encode(payload),
        headers = { 
            ["Content-Type"] = "application/json",
            ["Accept"] = "text/event-stream"
        }
    })

    if not res then
        return nil, "Failed to connect to AI service: " .. (err or "unknown error")
    end

    if res.status ~= 200 then
        return nil, "AI service error: HTTP " .. res.status
    end

    local accumulated = ""
    
    -- Process the response body line by line
    for line in res.body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            local ok, data = pcall(cjson.decode, line)
            if ok and data.message and data.message.content then
                accumulated = accumulated .. data.message.content
                callback({
                    content = data.message.content,
                    accumulated = accumulated,
                    done = data.done or false
                })
                
                if data.done then
                    break
                end
            end
        end
    end

    httpc:close()
    return accumulated, nil
end

local function handle_chat_stream()
    local user_type = ngx.var.auth_user_type
    local username = ngx.var.auth_username
    local is_admin = ngx.var.auth_is_admin == "true"
    local session_id = ngx.var.sse_session_id
    
    -- Validate SSE session if present
    if session_id then
        local is_valid, session_info = session_manager.is_session_valid(session_id)
        if not is_valid then
            send_json(410, { 
                error = "SSE session invalid", 
                message = session_info,
                code = "SSE_SESSION_EXPIRED"
            })
        end
    end
    
    ngx.req.read_body()
    local data = cjson.decode(ngx.req.get_body_data() or "{}")
    local message = data.message
    local include_history = data.include_history or false
    local options = data.options or {}

    if not message or message:match("^%s*$") then
        send_json(400, { error = "Message cannot be empty" })
    end

    -- Check rate limits based on user type
    local red, err = connect_redis()
    
    if user_type == "guest" then
        -- Guest users: use session-based limits (no Redis needed)
        check_rate_limit_guest(username)
    elseif user_type == "user" or user_type == "admin" then
        -- Regular users: use Redis-based rate limiting
        if not red then
            send_json(500, { error = "Service temporarily unavailable" })
        end
        check_rate_limit_user(red, username)
        
        -- Update last active for regular users
        red:hset("user:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))
    end

    -- Set response headers for streaming
    ngx.header.content_type = "text/plain"
    ngx.header.cache_control = "no-cache"
    ngx.header.connection = "keep-alive"
    ngx.header.access_control_allow_origin = "*"
    
    -- Add headers for frontend to know storage strategy
    if user_type == "guest" then
        ngx.header["X-Chat-Storage"] = "localStorage"
        ngx.header["X-Session-Type"] = "guest"
    else
        ngx.header["X-Chat-Storage"] = "redis"
        ngx.header["X-Session-Type"] = user_type
    end
    
    if session_id then
        ngx.header["X-SSE-Session-ID"] = session_id
    end

    local messages = {}
    
    -- Include history if requested (only for regular users with Redis)
    if include_history and (user_type == "user" or user_type == "admin") and red then
        local history = get_chat_history_from_redis(red, username, 10)
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    
    table.insert(messages, { role = "user", content = message })

    -- Save user message (only for regular users with Redis)
    if (user_type == "user" or user_type == "admin") and red then
        save_message_to_redis(red, username, "user", message)
    end

    -- Track streaming start
    ngx.log(ngx.INFO, "Starting SSE stream for user: " .. username .. 
            " (type: " .. user_type .. ", session: " .. (session_id or "none") .. ")")

    local accumulated = ""
    local chunk_count = 0
    local final_response, err = call_ollama_streaming(messages, options, function(chunk)
        accumulated = chunk.accumulated
        chunk_count = chunk_count + 1
        
        -- Send chunk and update session activity
        send_sse_chunk({ 
            content = chunk.content, 
            done = chunk.done,
            chunk_id = chunk_count,
            storage_type = user_type == "guest" and "localStorage" or "redis"
        })
        
        -- Log progress every 10 chunks for debugging
        if chunk_count % 10 == 0 then
            ngx.log(ngx.INFO, "SSE chunk " .. chunk_count .. " sent for session: " .. (session_id or "none"))
        end
    end)

    if err then
        ngx.log(ngx.ERR, "SSE streaming error for session " .. (session_id or "none") .. ": " .. err)
        send_sse_chunk({ error = err })
    else
        -- Save AI response (only for regular users with Redis)
        if (user_type == "user" or user_type == "admin") and red then
            save_message_to_redis(red, username, "assistant", accumulated)
        end
        
        ngx.log(ngx.INFO, "SSE stream completed for session: " .. (session_id or "none") .. 
                " (chunks: " .. chunk_count .. ", length: " .. #accumulated .. ")")
    end

    -- Send final chunk with storage instructions for guests
    if user_type == "guest" then
        send_sse_chunk({
            type = "storage_instruction",
            message = "Chat history stored in browser localStorage only",
            storage_type = "localStorage"
        })
    end

    send_sse_chunk("[DONE]")
    ngx.exit(200)
end

local function handle_chat_history()
    local user_type = ngx.var.auth_user_type
    local username = ngx.var.auth_username
    
    -- Only regular users can access Redis history
    if user_type == "guest" then
        send_json(200, {
            success = true,
            messages = {},
            count = 0,
            storage_type = "localStorage",
            note = "Guest sessions use browser localStorage - history not available on server"
        })
    end
    
    local red, err = connect_redis()
    if not red then
        send_json(500, { error = "Service temporarily unavailable" })
    end
    
    local limit = tonumber(ngx.var.arg_limit) or 20
    local history = get_chat_history_from_redis(red, username, limit)
    
    send_json(200, {
        success = true,
        messages = history,
        count = #history,
        storage_type = "redis",
        user_type = user_type
    })
end

local function handle_clear_chat()
    local user_type = ngx.var.auth_user_type
    local username = ngx.var.auth_username
    
    -- Only regular users can clear Redis history
    if user_type == "guest" then
        send_json(200, {
            success = true,
            message = "Guest sessions use browser localStorage - clear history in your browser",
            storage_type = "localStorage"
        })
    end
    
    local red, err = connect_redis()
    if not red then
        send_json(500, { error = "Service temporarily unavailable" })
    end
    
    local chat_key = "chat:" .. username
    red:del(chat_key)
    
    send_json(200, {
        success = true,
        message = "Redis chat history cleared",
        storage_type = "redis"
    })
end

-- Get current SSE session info
local function handle_session_info()
    local session_id = ngx.var.sse_session_id
    local user_type = ngx.var.auth_user_type
    local username = ngx.var.auth_username
    local is_admin = ngx.var.auth_is_admin == "true"
    
    local session_data = {
        success = true,
        user_type = user_type,
        username = username,
        is_admin = is_admin,
        storage_type = user_type == "guest" and "localStorage" or "redis",
        max_sse_sessions = session_manager.MAX_SSE_SESSIONS
    }
    
    if not session_id then
        session_data.has_sse_session = false
        session_data.message = "No active SSE session"
    else
        local is_valid, session_info = session_manager.is_session_valid(session_id)
        
        if not is_valid then
            session_data.has_sse_session = false
            session_data.message = "SSE session expired"
            session_data.session_error = session_info
        else
            session_data.has_sse_session = true
            session_data.session_info = session_info
        end
    end
    
    -- Add guest-specific info
    if user_type == "guest" then
        local limits = session_manager.get_guest_limits(username)
        if limits then
            session_data.guest_limits = limits
        end
    end
    
    send_json(200, session_data)
end

-- Create guest session endpoint
local function handle_create_guest_session()
    -- Check capacity first
    local stats = session_manager.get_session_stats()
    if stats.total_sessions >= session_manager.MAX_SSE_SESSIONS and stats.by_priority.guest_sessions == 0 then
        send_json(503, {
            error = "Server at capacity",
            message = "All " .. session_manager.MAX_SSE_SESSIONS .. " sessions are occupied by higher priority users",
            capacity = stats
        })
    end
    
    local session_data, error_msg = session_manager.create_guest_session()
    
    if not session_data then
        send_json(500, {
            error = "Failed to create guest session",
            message = error_msg
        })
    end
    
    send_json(200, {
        success = true,
        session = session_data,
        message = "Guest session created - chat history will be stored in browser localStorage only",
        storage_type = "localStorage",
        limits = {
            max_messages = session_manager.GUEST_MESSAGE_LIMIT,
            session_duration = session_manager.GUEST_SESSION_DURATION
        }
    })
end

-- Get SSE capacity info
local function handle_sse_capacity()
    local stats = session_manager.get_session_stats()
    
    send_json(200, {
        success = true,
        capacity = {
            current_sessions = stats.total_sessions,
            max_sessions = session_manager.MAX_SSE_SESSIONS,
            available_slots = stats.available_slots,
            utilization_percent = stats.utilization_percent,
            is_full = stats.available_slots == 0
        },
        breakdown = stats.by_priority,
        priority_info = {
            {priority = 1, name = "admin", description = "Administrators (cannot be kicked)"},
            {priority = 2, name = "user", description = "Approved users (can kick guests)"},
            {priority = 3, name = "guest", description = "Guest users (can be kicked)"}
        }
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
    elseif uri == "/api/chat/session-info" and method == "GET" then
        handle_session_info()
    elseif uri == "/api/chat/create-guest" and method == "POST" then
        handle_create_guest_session()
    elseif uri == "/api/chat/sse-capacity" and method == "GET" then
        handle_sse_capacity()
    else
        send_json(404, { error = "Chat API endpoint not found" })
    end
end

return {
    handle_chat_api = handle_chat_api,
    handle_chat_stream = handle_chat_stream,
    handle_chat_history = handle_chat_history,
    handle_clear_chat = handle_clear_chat,
    handle_session_info = handle_session_info,
    handle_create_guest_session = handle_create_guest_session,
    handle_sse_capacity = handle_sse_capacity
}