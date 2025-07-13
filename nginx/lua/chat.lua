local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"
local http = require "resty.http"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434"
local RATE_LIMIT_MESSAGES_PER_MINUTE = tonumber(os.getenv("RATE_LIMIT_MESSAGES_PER_MINUTE")) or 6
local MODEL_TEMPERATURE = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.6
local MODEL_MAX_TOKENS = tonumber(os.getenv("MODEL_MAX_TOKENS")) or 2048
local MODEL_TIMEOUT = tonumber(os.getenv("MODEL_TIMEOUT")) or 300
local OLLAMA_MODEL = os.getenv("OLLAMA_MODEL") or "devstral"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
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
    
    -- Get user info from Redis
    local red = connect_redis()
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        send_json(401, { error = "User not found" })
    end

    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    if user.is_approved ~= "true" then
        send_json(403, { error = "User not approved" })
    end

    return username, red, user
end

local function check_rate_limit(red, username)
    local today = os.date("%Y-%m-%d")
    local count_key = "user_messages:" .. username .. ":" .. today
    local current_count = red:get(count_key) or 0
    current_count = tonumber(current_count)
    
    if current_count >= RATE_LIMIT_MESSAGES_PER_MINUTE * 60 then -- Daily limit approximation
        send_json(429, { 
            error = "Rate limit exceeded", 
            details = "Too many messages today. Please try again tomorrow." 
        })
    end
    
    -- Increment counter
    red:incr(count_key)
    red:expire(count_key, 86400) -- Expire after 24 hours
    
    return current_count + 1
end

local function save_message_to_history(red, username, role, content)
    local chat_key = "chat:" .. username
    local message = {
        role = role,
        content = content,
        timestamp = os.date("!%Y-%m-%dT%TZ")
    }
    
    -- Add to chat history (use LPUSH to add to beginning)
    red:lpush(chat_key, cjson.encode(message))
    
    -- Keep only last 50 messages
    red:ltrim(chat_key, 0, 49)
    
    -- Set expiry for 7 days
    red:expire(chat_key, 604800)
end

local function get_chat_history(red, username, limit)
    limit = limit or 10
    local chat_key = "chat:" .. username
    local history = red:lrange(chat_key, 0, limit - 1)
    
    local messages = {}
    for i = #history, 1, -1 do -- Reverse to get chronological order
        local message = cjson.decode(history[i])
        table.insert(messages, message)
    end
    
    return messages
end

local function call_ollama_api(messages, options)
    local httpc = http:new()
    httpc:set_timeout(MODEL_TIMEOUT * 1000)
    
    -- Determine which model to use (prefer hybrid if available)
    local model_to_use = OLLAMA_MODEL
    
    -- Check if hybrid model exists by trying to get model info
    local model_check_res, model_check_err = httpc:request_uri(OLLAMA_URL .. "/api/show", {
        method = "POST",
        body = cjson.encode({model = OLLAMA_MODEL .. "-hybrid"}),
        headers = { ["Content-Type"] = "application/json" }
    })
    
    if model_check_res and model_check_res.status == 200 then
        model_to_use = OLLAMA_MODEL .. "-hybrid"
        ngx.log(ngx.ERR, "Using hybrid model: " .. model_to_use)
    else
        ngx.log(ngx.ERR, "Using base model: " .. model_to_use)
    end
    
    local payload = {
        model = model_to_use,
        messages = messages,
        stream = false,
        options = {
            temperature = options.temperature or MODEL_TEMPERATURE,
            num_predict = options.max_tokens or MODEL_MAX_TOKENS,
            num_ctx = tonumber(os.getenv("OLLAMA_CONTEXT_SIZE")) or 1024,
            num_gpu = tonumber(os.getenv("OLLAMA_GPU_LAYERS")) or 8,
            num_thread = tonumber(os.getenv("OLLAMA_NUM_THREAD")) or 6,
            num_batch = tonumber(os.getenv("OLLAMA_BATCH_SIZE")) or 64,
            use_mmap = false,
            use_mlock = true,
            top_p = tonumber(os.getenv("MODEL_TOP_P")) or 0.9,
            top_k = tonumber(os.getenv("MODEL_TOP_K")) or 40,
            repeat_penalty = tonumber(os.getenv("MODEL_REPEAT_PENALTY")) or 1.1
        },
        keep_alive = -1 -- Keep model loaded
    }
    
    ngx.log(ngx.ERR, "Calling Ollama with payload: ", cjson.encode(payload))
    
    local res, err = httpc:request_uri(OLLAMA_URL .. "/api/chat", {
        method = "POST",
        body = cjson.encode(payload),
        headers = {
            ["Content-Type"] = "application/json"
        }
    })
    
    httpc:close()
    
    if not res then
        ngx.log(ngx.ERR, "Ollama request failed: ", err)
        return nil, "Failed to connect to AI service"
    end
    
    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Ollama returned status: ", res.status, " body: ", res.body)
        return nil, "AI service returned error: " .. res.status
    end
    
    local response_data = cjson.decode(res.body)
    if not response_data or not response_data.message or not response_data.message.content then
        ngx.log(ngx.ERR, "Invalid Ollama response: ", res.body)
        return nil, "Invalid response from AI service"
    end
    
    return response_data.message.content, nil
end

local function handle_chat_message()
    local username, red, user = verify_user_token()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local message = data.message
    local include_history = data.include_history or false
    local options = data.options or {}

    if not message or message:match("^%s*$") then
        send_json(400, { error = "Message cannot be empty" })
    end

    -- Check rate limiting
    local message_count = check_rate_limit(red, username)
    
    -- Update user's last active timestamp
    red:hset("user:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))

    -- Prepare messages for Ollama
    local messages = {}
    
    if include_history then
        -- Get recent chat history
        local history = get_chat_history(red, username, 10)
        
        -- Convert history to Ollama format
        for _, msg in ipairs(history) do
            table.insert(messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end
    
    -- Add current user message
    table.insert(messages, {
        role = "user",
        content = message
    })
    
    -- Save user message to history
    save_message_to_history(red, username, "user", message)
    
    -- Call Ollama API
    local ai_response, ai_error = call_ollama_api(messages, options)
    
    if ai_error then
        ngx.log(ngx.ERR, "AI response error for user " .. username .. ": " .. ai_error)
        send_json(500, { 
            error = "AI service error", 
            details = ai_error,
            success = false
        })
    end
    
    -- Save AI response to history
    save_message_to_history(red, username, "assistant", ai_response)
    
    ngx.log(ngx.ERR, "Successful chat response for user: " .. username)
    
    send_json(200, {
        success = true,
        message = ai_response,
        message_count = message_count,
        model = OLLAMA_MODEL
    })
end

local function handle_chat_history()
    local username, red, user = verify_user_token()
    
    local limit = tonumber(ngx.var.arg_limit) or 20
    limit = math.min(limit, 50) -- Cap at 50 messages
    
    local history = get_chat_history(red, username, limit)
    
    send_json(200, {
        success = true,
        messages = history,
        count = #history
    })
end

local function handle_clear_chat()
    local username, red, user = verify_user_token()
    
    local chat_key = "chat:" .. username
    red:del(chat_key)
    
    ngx.log(ngx.ERR, "Chat history cleared for user: " .. username)
    
    send_json(200, {
        success = true,
        message = "Chat history cleared"
    })
end

-- Main route handler
local function handle_chat_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.ERR, "Chat API called - URI: " .. uri .. " Method: " .. method)
    
    if uri == "/api/chat/message" and method == "POST" then
        handle_chat_message()
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
    handle_chat_message = handle_chat_message,
    handle_chat_history = handle_chat_history,
    handle_clear_chat = handle_clear_chat
}