-- nginx/lua/chat_api.lua - Fixed and complete
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
    local red = connect_redis()
    local user_key = "user:" .. username
    local is_approved = red:hget(user_key, "is_approved")
    
    if is_approved ~= "true" then
        send_json(403, { error = "User not approved" })
    end
    
    return username, red
end

local function check_rate_limit(red, username)
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

local function save_message_to_history(red, username, role, content)
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
    limit = math.min(limit or 20, 50)
    local chat_key = "chat:" .. username
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
    local username, red = verify_user_token()
    
    ngx.req.read_body()
    local data = cjson.decode(ngx.req.get_body_data() or "{}")
    local message = data.message
    local include_history = data.include_history or false
    local options = data.options or {}

    if not message or message:match("^%s*$") then
        send_json(400, { error = "Message cannot be empty" })
    end

    -- Check rate limits
    local message_count = check_rate_limit(red, username)
    
    -- Update last active
    red:hset("user:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))

    -- Set response headers for streaming
    ngx.header.content_type = "text/plain"
    ngx.header.cache_control = "no-cache"
    ngx.header.connection = "keep-alive"
    ngx.header.access_control_allow_origin = "*"

    local messages = {}
    
    -- Include history if requested
    if include_history then
        local history = get_chat_history(red, username, 10)
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    
    table.insert(messages, { role = "user", content = message })

    -- Save user message
    save_message_to_history(red, username, "user", message)

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
        save_message_to_history(red, username, "assistant", accumulated)
    end

    send_sse_chunk("[DONE]")
    ngx.exit(200)
end

local function handle_chat_history()
    local username, red = verify_user_token()
    local limit = tonumber(ngx.var.arg_limit) or 20
    local history = get_chat_history(red, username, limit)
    
    send_json(200, {
        success = true,
        messages = history,
        count = #history
    })
end

local function handle_clear_chat()
    local username, red = verify_user_token()
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