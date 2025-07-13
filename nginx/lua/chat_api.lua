-- nginx/lua/chat_api_enhanced.lua - Enhanced with guest token support
local cjson = require "cjson"
local redis = require "resty.redis"
local http = require "resty.http"
local unified_auth = require "unified_auth"

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

local function check_rate_limit_guest(slot_num)
    -- For guests, we use the built-in message limit system
    local success = unified_auth.use_guest_message(slot_num)
    if not success then
        local limits = unified_auth.get_guest_limits(slot_num)
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

local function save_message_to_history(red, username, role, content)
    if not red then
        ngx.log(ngx.WARN, "Cannot save message - Redis unavailable")
        return
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
end

local function get_chat_history(red, username, limit)
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
    local slot_num = tonumber(ngx.var.auth_slot_num)
    
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
        -- Guest users: use slot-based limits (no Redis needed)
        check_rate_limit_guest(slot_num)
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

    local messages = {}
    
    -- Include history if requested (only for regular users)
    if include_history and (user_type == "user" or user_type == "admin") then
        local history = get_chat_history(red, username, 10)
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    
    table.insert(messages, { role = "user", content = message })

    -- Save user message (only for regular users)
    if user_type == "user" or user_type == "admin" then
        save_message_to_history(red, username, "user", message)
    end

    local accumulated = ""
    local final_response, err = call_ollama_streaming(messages, options, function(chunk)
        accumulated = chunk.accumulated
        send_sse_chunk({ 
            content = chunk.content, 
            done = chunk.done
        })
    end)

    if err then
        send_sse_chunk({ error = err })
    else
        -- Save AI response (only for regular users)
        if user_type == "user" or user_type == "admin" then
            save_message_to_history(red, username, "assistant", accumulated)
        end
    end

    send_sse_chunk("[DONE]")
    ngx.exit(200)
end

local function handle_chat_history()
    local user_type = ngx.var.auth_user_type
    local username = ngx.var.auth_username
    
    -- Only regular users can access history
    if user_type == "guest" then
        send_json(200, {
            success = true,
            messages = {},
            count = 0,
            note = "Guest sessions do not save history"
        })
    end
    
    local red, err = connect_redis()
    if not red then
        send_json(500, { error = "Service temporarily unavailable" })
    end
    
    local limit = tonumber(ngx.var.arg_limit) or 20
    local history = get_chat_history(red, username, limit)
    
    send_json(200, {
        success = true,
        messages = history,
        count = #history
    })
end

local function handle_clear_chat()
    local user_type = ngx.var.auth_user_type
    local username = ngx.var.auth_username
    
    -- Only regular users can clear history
    if user_type == "guest" then
        send_json(200, {
            success = true,
            message = "Guest sessions do not save history"
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
        message = "Chat history cleared"
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