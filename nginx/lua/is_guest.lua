-- =============================================================================
-- nginx/lua/is_guest.lua - COMPLETE GUEST SYSTEM WITH ALL REQUIRED FUNCTIONS
-- =============================================================================

local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 1800  -- 30 minutes
local GUEST_MESSAGE_LIMIT = 10
local GUEST_CHAT_RETENTION = 259200  -- 3 days

local USERNAME_POOLS = {
    adjectives = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Cosmic", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural"},
    animals = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}
}

local function get_guest_accounts()
    return {
        {
            slot_number = 1,
            guest_active_session = false,
            username = "guest_user_1",
            password = "nkcukfulnckfckufnckdgjvjgv",
            token = generate_guest_jwt(nkcukfulnckfckufnckdgjvjgv, 1)
        },
        {
            slot_number = 2,
            guest_active_session = false,
            username = "guest_user_2", 
            password = "ymbkclhfpbdfbsdfwdsbwfdsbp",
            token = generate_guest_jwt(ymbkclhfpbdfbsdfwdsbwfdsbp, 2)
        }
    }
end

local function redis_to_lua(value)
    if value == ngx.null or value == nil then return nil end
    return value
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection failed: " .. (err or "unknown"))
        return nil
    end
    return red
end

local function generate_display_username(slot_number)
    local red = connect_redis()
    if not red then
        local pool = USERNAME_POOLS
        return pool.adjectives[math.random(#pool.adjectives)] ..
               pool.animals[math.random(#pool.animals)] ..
               tostring(math.random(100, 999))
    end

    local pool = USERNAME_POOLS
    local max_attempts, attempts = 3, 0

    while attempts < max_attempts do
        local adjective = pool.adjectives[math.random(#pool.adjectives)]
        local animal = pool.animals[math.random(#pool.animals)]
        local number = math.random(100, 999)
        local candidate = adjective .. animal .. number
        local key = "guest_username_blacklist:" .. candidate

        if not redis_to_lua(red:get(key)) then
            red:set(key, "1")
            red:expire(key, GUEST_CHAT_RETENTION + 3600)
            ngx.log(ngx.INFO, "Generated unique session username: " .. candidate)
            red:close()
            return candidate
        end

        attempts = attempts + 1
    end

    local adjective = pool.adjectives[math.random(#pool.adjectives)]
    local animal = pool.animals[math.random(#pool.animals)]
    local fallback = adjective .. animal .. tostring(ngx.time()):sub(-4)
    local key = "guest_username_blacklist:" .. fallback
    red:set(key, "1")
    red:expire(key, GUEST_CHAT_RETENTION + 3600)
    red:close()
    ngx.log(ngx.WARN, "Used fallback username: " .. fallback)
    return fallback
end

local function find_available_guest_slot()
    local red = connect_redis()
    if not red then return nil, "Service unavailable" end

    local guest_accounts = get_guest_accounts()
    
    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        local data = redis_to_lua(red:get(key))

        if not data then
            red:close()
            return guest_accounts[i], nil
        else
            local ok, session = pcall(cjson.decode, data)
            if ok and session.expires_at and ngx.time() >= session.expires_at then
                red:del(key)
                red:close()
                return guest_accounts[i], nil
            end
        end
    end
    red:close()
    return nil, "All guest slots occupied"
end

local function create_secure_guest_session()
    ngx.log(ngx.INFO, "=== GUEST SESSION CREATION START ===")

    local account, err = find_available_guest_slot()
    if not account then
        ngx.log(ngx.WARN, "Guest session creation failed: " .. (err or "unknown"))
        ngx.status = 429
        return ngx.exec("@custom_429")
    end

    local red = connect_redis()
    if not red then
        ngx.log(ngx.ERR, "Redis unavailable during guest session creation")
        ngx.status = 503
        return ngx.exec("@custom_50x")
    end

    local display_name = generate_display_username(account.slot_number)
    local now = ngx.time()
    local expires_at = now + GUEST_SESSION_DURATION

    local session = {
        username = account.username,
        user_type = "is_guest",
        jwt_token = account.token,
        slot_number = account.slot_number,
        session_id = display_name,
        display_username = display_name,
        created_at = now,
        expires_at = expires_at,
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = ngx.var.remote_addr or "unknown",
        last_activity = now,
        priority = 3,
        chat_storage = "redis",
        chat_retention_until = now + GUEST_CHAT_RETENTION
    }

    local key = "guest_active_session:" .. account.slot_number
    red:set(key, cjson.encode(session))
    red:expire(key, GUEST_SESSION_DURATION)

    local user_session_key = "guest_session:" .. account.username
    red:set(user_session_key, cjson.encode(session))
    red:expire(user_session_key, GUEST_SESSION_DURATION)

    local user_key = "username:" .. account.username

    -- Hash password for user hash
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | awk '{print $2}'",
                                   account.password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hashed = handle:read("*a"):gsub("\n", "")
    handle:close()

    red:hset(user_key, "username:", account.username)
    red:hset(user_key, "password_hash:", hashed)
    red:hset(user_key, "user_type:", "is_guest")
    red:hset(user_key, "created_at:", os.date("!%Y-%m-%dT%H:%M:%SZ"))
    red:hset(user_key, "last_active", os.date("!%Y-%m-%dT%H:%M:%SZ"))

    red:close()

    ngx.header["Set-Cookie"] = "access_token=" .. account.token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION

    ngx.log(ngx.INFO, "=== GUEST SESSION CREATION SUCCESS ===")
    ngx.log(ngx.INFO, "Created session: " .. display_name .. " -> " .. account.username .. " [Slot " .. account.slot_number .. "]")

    return {
        success = true,
        username = display_name,
        internal_username = account.username,
        session_id = display_name,
        token = account.token,
        expires_at = expires_at,
        message_limit = GUEST_MESSAGE_LIMIT,
        session_duration = GUEST_SESSION_DURATION,
        priority = 3,
        slot_number = account.slot_number,
        storage_type = "redis",
        chat_retention_days = math.floor(GUEST_CHAT_RETENTION / 86400)
    }, nil
end

local function validate_guest_session(token)
    if not token then return nil, "No token provided" end

    -- First try to decode the JWT to get username
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then return nil, "JWT verification failed" end

    local payload = jwt_obj.payload
    if payload.user_type ~= "guest" then return nil, "Not a guest token" end

    -- Validate against hardcoded guest accounts
    local guest_accounts = get_guest_accounts()
    local valid_account
    for _, acc in ipairs(guest_accounts) do
        if acc.username == payload.username then
            valid_account = acc
            break
        end
    end
    if not valid_account then return nil, "Invalid guest account" end

    local red = connect_redis()
    if not red then return nil, "Service unavailable" end

    local key = "guest_session:" .. valid_account.username
    local data = redis_to_lua(red:get(key))
    if not data then 
        red:close()
        return nil, "No active session" 
    end

    local ok, session = pcall(cjson.decode, data)
    if not ok then 
        red:close()
        return nil, "Invalid session data" 
    end

    if ngx.time() >= session.expires_at then
        red:del(key)
        red:del("guest_active_session:" .. valid_account.slot_number)
        red:close()
        return nil, "Session expired"
    end

    session.last_activity = ngx.time()
    red:set(key, cjson.encode(session))
    red:expire(key, GUEST_SESSION_DURATION)
    red:close()

    return session, nil
end

local function get_guest_stats()
    local red = connect_redis()
    if not red then 
        return {
            guest_active_session = 0,
            max_sessions = MAX_GUEST_SESSIONS,
            available_slots = MAX_GUEST_SESSIONS
        }
    end

    local active_count = 0
    
    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        local data = redis_to_lua(red:get(key))
        
        if data then
            local ok, session = pcall(cjson.decode, data)
            if ok and session.expires_at and ngx.time() < session.expires_at then
                active_count = active_count + 1
            else
                -- Clean up expired session
                red:del(key)
            end
        end
    end
    
    red:close()
    
    return {
        guest_active_session = active_count,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = MAX_GUEST_SESSIONS - active_count
    }
end

local function cleanup_guest_session(slot_number)
    if not slot_number then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    local key = "guest_active_session:" .. slot_number
    red:del(key)
    
    -- Also clean up user session key
    local guest_accounts = get_guest_accounts()
    for _, acc in ipairs(guest_accounts) do
        if acc.slot_number == slot_number then
            red:del("guest_session:" .. acc.username)
            red:del("username:" .. acc.username)
            break
        end
    end
    
    red:close()
    ngx.log(ngx.INFO, "Cleaned up guest session for slot: " .. slot_number)
    return true
end

local function clear_all_guest_sessions()
    local red = connect_redis()
    if not red then return false, "Redis connection failed" end
    
    local cleared = 0
    
    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        if red:del(key) == 1 then
            cleared = cleared + 1
        end
    end
    
    -- Clean up all guest user sessions
    local guest_accounts = get_guest_accounts()
    for _, acc in ipairs(guest_accounts) do
        red:del("guest_session:" .. acc.username)
        red:del("user:" .. acc.username)
    end
    
    red:close()
    
    ngx.log(ngx.INFO, "Cleared " .. cleared .. " guest sessions")
    return true, "Cleared " .. cleared .. " guest sessions"
end

-- =============================================
-- PAGE HANDLERS
-- =============================================

local function handle_chat_page()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_guest()    
    local context = {
        page_title = "Guest Chat",
        nav = is_who.render_nav("guest", username, nil),
        chat_features = is_who.get_chat_features("guest"),
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 30 minutes)"
    }
    template.render_template("/usr/local/openresty/nginx/html/chat_guest.html", context)
end

-- =============================================
-- API HANDLERS
-- =============================================

local function handle_guest_api()
    local cjson = require "cjson"
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    if uri == "/api/guest/create-session" and method == "POST" then
        -- Create new guest session
        local session_data, err = create_secure_guest_session()
        if session_data then
            send_json(200, session_data)
        else
            send_json(429, { 
                success = false, 
                error = "no_slots_available",
                message = "All guest slots are occupied. Please try again later."
            })
        end
        
    elseif uri == "/api/guest/stats" and method == "GET" then
        -- Get guest statistics
        local stats = get_guest_stats()
        send_json(200, {
            success = true,
            stats = stats
        })
        
    else
        send_json(404, { 
            error = "Guest API endpoint not found",
            requested = method .. " " .. uri
        })
    end
end

local function handle_chat_api()
    local cjson = require "cjson"
    local server = require "server"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    -- Require guest access for chat API
    local is_who = require "is_who"
    local username = is_who.require_guest()
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        -- Guests don't have persistent history
        send_json(200, {
            success = true,
            messages = {},
            user_type = "guest",
            storage_type = "none",
            note = "Guest users don't have persistent chat history"
        })
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        -- Nothing to clear for guests
        send_json(200, { 
            success = true, 
            message = "Guest chat uses localStorage only - clear from browser"
        })
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        handle_chat_stream() -- Guest-specific implementation
        
    else
        send_json(404, { 
            error = "Guest Chat API endpoint not found",
            requested = method .. " " .. uri
        })
    end
end

local function handle_chat_stream()
    local server = require "server"
    local is_who = require "is_who"
    local cjson = require "cjson"
    
    -- Get guest user info
    local username, user_data = is_who.require_guest()
    
    -- Guest rate limiting (strict)
    local function pre_stream_check(message, request_data)
        -- Check message count
        if user_data.message_count >= user_data.max_messages then
            return false, "Guest message limit reached (10 messages). Register for unlimited access."
        end
        
        -- Check session expiry
        if ngx.time() >= user_data.expires_at then
            return false, "Guest session expired. Please start a new session."
        end
        
        return true, nil
    end
    
    -- Guest stream context (minimal features)
    local stream_context = {
        user_type = "is_guest",
        username = username,
        
        -- Guest limitations
        include_history = false,  -- No history for guests
        history_limit = 0,
        
        -- Guest-specific checks
        pre_stream_check = pre_stream_check,
        
        -- Guest AI options (basic)
        default_options = {
            temperature = 0.7,
            max_tokens = 1024,      -- Lower limit for guests
            num_predict = 1024,
            num_ctx = 512,          -- Smaller context
            priority = 3            -- Lowest priority
        }
    }
    
    -- Call common streaming function
    server.handle_chat_stream_common(stream_context)
end

return {
    create_secure_guest_session = create_secure_guest_session,
    validate_guest_session = validate_guest_session,
    generate_display_username = generate_display_username,
    get_guest_stats = get_guest_stats,
    cleanup_guest_session = cleanup_guest_session,
    clear_all_guest_sessions = clear_all_guest_sessions,
    handle_chat_page = handle_chat_page,
    handle_guest_api = handle_guest_api,
    handle_chat_api = handle_chat_api,
    handle_chat_stream = handle_chat_stream
}