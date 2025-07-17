-- =============================================================================
-- nginx/lua/is_guest.lua - COMPLETE GUEST CHALLENGE SYSTEM
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
local CHALLENGE_TIMEOUT = 20  -- 20 seconds for challenge response
local CHALLENGE_COOLDOWN = 30  -- 30 seconds between challenges
local INACTIVE_THRESHOLD = 300  -- 5 minutes to be considered inactive

local USERNAME_POOLS = {
    adjectives = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Cosmic", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural"},
    animals = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}
}

-- Helper functions
local function get_guest_accounts()
    return {
        {
            guest_slot_number = 1,
            guest_active_session = false,
            username = "guest_user_1",
            password = "nkcukfulnckfckufnckdgjvjgv",
            token = jwt:sign(JWT_SECRET, {
                header = { typ = "JWT", alg = "HS256" },
                payload = {
                    username = "guest_user_1",
                    user_type = "guest",
                    guest_slot_number = 1,
                    iat = ngx.time(),
                    exp = ngx.time() + GUEST_SESSION_DURATION
                }
            })
        },
        {
            guest_slot_number = 2,
            guest_active_session = false,
            username = "guest_user_2", 
            password = "ymbkclhfpbdfbsdfwdsbwfdsbp",
            token = jwt:sign(JWT_SECRET, {
                header = { typ = "JWT", alg = "HS256" },
                payload = {
                    username = "guest_user_2",
                    user_type = "guest",
                    guest_slot_number = 2,
                    iat = ngx.time(),
                    exp = ngx.time() + GUEST_SESSION_DURATION
                }
            })
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

local function generate_display_username()
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
    return fallback
end

-- =============================================================================
-- GUEST CHALLENGE SYSTEM
-- =============================================================================

local function create_guest_challenge(slot_number, challenger_ip)
    local red = connect_redis()
    if not red then return false, "Redis unavailable" end
    
    local challenge_id = "challenge_" .. slot_number .. "_" .. ngx.time() .. "_" .. math.random(1000, 9999)
    local challenge_key = "guest_challenge:" .. slot_number
    
    -- Check if there's already an active challenge for this slot
    local existing_challenge = redis_to_lua(red:get(challenge_key))
    if existing_challenge then
        local ok, challenge_data = pcall(cjson.decode, existing_challenge)
        if ok and challenge_data.expires_at > ngx.time() then
            red:close()
            return false, "Challenge already active for this slot"
        end
    end
    
    local challenge = {
        challenge_id = challenge_id,
        slot_number = slot_number,
        challenger_ip = challenger_ip,
        created_at = ngx.time(),
        expires_at = ngx.time() + CHALLENGE_TIMEOUT,
        status = "pending"
    }
    
    red:set(challenge_key, cjson.encode(challenge))
    red:expire(challenge_key, CHALLENGE_TIMEOUT + 5)
    red:close()
    
    ngx.log(ngx.INFO, "🚨 Guest challenge created for slot " .. slot_number .. " by " .. challenger_ip)
    return true, challenge_id
end

local function get_guest_challenge(slot_number)
    local red = connect_redis()
    if not red then return nil end
    
    local challenge_key = "guest_challenge:" .. slot_number
    local challenge_data = redis_to_lua(red:get(challenge_key))
    
    if not challenge_data then
        red:close()
        return nil
    end
    
    local ok, challenge = pcall(cjson.decode, challenge_data)
    if not ok then
        red:del(challenge_key)
        red:close()
        return nil
    end
    
    -- Check if challenge expired
    if challenge.expires_at <= ngx.time() then
        red:del(challenge_key)
        red:close()
        return nil
    end
    
    red:close()
    return challenge
end

local function respond_to_challenge(slot_number, response, responder_ip)
    local red = connect_redis()
    if not red then return false, "Redis unavailable" end
    
    local challenge_key = "guest_challenge:" .. slot_number
    local challenge_data = redis_to_lua(red:get(challenge_key))
    
    if not challenge_data then
        red:close()
        return false, "No active challenge"
    end
    
    local ok, challenge = pcall(cjson.decode, challenge_data)
    if not ok then
        red:del(challenge_key)
        red:close()
        return false, "Invalid challenge data"
    end
    
    -- Check if challenge expired
    if challenge.expires_at <= ngx.time() then
        red:del(challenge_key)
        red:close()
        return false, "Challenge expired"
    end
    
    -- Update challenge with response
    challenge.response = response
    challenge.responder_ip = responder_ip
    challenge.responded_at = ngx.time()
    challenge.status = response == "accept" and "accepted" or "rejected"
    
    red:set(challenge_key, cjson.encode(challenge))
    red:expire(challenge_key, 60)  -- Keep for 1 minute for logging
    red:close()
    
    ngx.log(ngx.INFO, "✅ Challenge response for slot " .. slot_number .. ": " .. response .. " by " .. responder_ip)
    return true, challenge.status
end

local function force_kick_guest_session(slot_number, reason)
    local red = connect_redis()
    if not red then return false, "Redis unavailable" end
    
    local session_key = "guest_active_session:" .. slot_number
    local session_data = redis_to_lua(red:get(session_key))
    
    if not session_data then
        red:close()
        return false, "No active session"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        red:close()
        return false, "Invalid session data"
    end
    
    -- Clean up all session data
    red:del(session_key)
    red:del("guest_session:" .. session.username)
    red:del("username:" .. session.username)
    red:del("guest_challenge:" .. slot_number)
    
    red:close()
    
    ngx.log(ngx.WARN, "👢 Force kicked guest session " .. slot_number .. " (" .. (session.display_username or session.username) .. ") - " .. reason)
    return true, session.display_username or session.username
end

local function cleanup_expired_challenge(slot_number)
    local red = connect_redis()
    if not red then return false end
    
    local challenge_key = "guest_challenge:" .. slot_number
    local challenge_data = redis_to_lua(red:get(challenge_key))
    
    if challenge_data then
        local ok, challenge = pcall(cjson.decode, challenge_data)
        if ok and challenge.expires_at <= ngx.time() then
            red:del(challenge_key)
            ngx.log(ngx.INFO, "🕐 Expired challenge cleaned up for slot " .. slot_number)
        end
    end
    
    red:close()
    return true
end

-- =============================================================================
-- ENHANCED SESSION MANAGEMENT
-- =============================================================================

local function cleanup_inactive_sessions_on_demand()
    local red = connect_redis()
    if not red then return 0 end
    
    local current_time = ngx.time()
    local cleaned = 0
    
    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        local data = redis_to_lua(red:get(key))
        
        if data then
            local ok, session = pcall(cjson.decode, data)
            if ok and session.expires_at then
                if current_time >= session.expires_at then
                    red:del(key)
                    red:del("guest_session:" .. session.username)
                    red:del("username:" .. session.username)
                    cleaned = cleaned + 1
                end
            end
        end
        
        cleanup_expired_challenge(i)
    end
    
    red:close()
    return cleaned
end

local function find_available_guest_slot_with_challenge()
    local red = connect_redis()
    if not red then return nil, "Service unavailable" end

    cleanup_inactive_sessions_on_demand()
    local guest_accounts = get_guest_accounts()
    
    -- First pass: Check for truly available slots
    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        local data = redis_to_lua(red:get(key))

        if not data then
            red:close()
            return guest_accounts[i], nil
        end
    end
    
    -- Second pass: Check for challengeable slots (inactive users)
    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        local data = redis_to_lua(red:get(key))
        
        if data then
            local ok, session = pcall(cjson.decode, data)
            if ok then
                local time_since_activity = ngx.time() - (session.last_activity or session.created_at)
                
                if time_since_activity > INACTIVE_THRESHOLD then
                    -- Check cooldown period
                    local cooldown_key = "challenge_cooldown:" .. i
                    local last_challenge = redis_to_lua(red:get(cooldown_key))
                    
                    if not last_challenge or (ngx.time() - tonumber(last_challenge)) > CHALLENGE_COOLDOWN then
                        red:close()
                        return guest_accounts[i], "challengeable"
                    end
                end
            end
        end
    end
    
    red:close()
    return nil, "All guest slots occupied"
end

local function create_secure_guest_session_with_challenge()
    ngx.log(ngx.INFO, "=== GUEST SESSION CREATION WITH CHALLENGE START ===")

    local account, slot_status = find_available_guest_slot_with_challenge()
    local challenger_ip = ngx.var.remote_addr or "unknown"
    
    if not account then
        ngx.log(ngx.WARN, "Guest session creation failed: All guest slots occupied")
        ngx.status = 429
        return ngx.exec("@custom_429")
    end
    
    -- If slot is challengeable, create challenge
    if slot_status == "challengeable" then
        ngx.log(ngx.INFO, "🚨 Creating challenge for slot " .. account.guest_slot_number)
        
        local red = connect_redis()
        if red then
            local cooldown_key = "challenge_cooldown:" .. account.guest_slot_number
            red:set(cooldown_key, ngx.time())
            red:expire(cooldown_key, CHALLENGE_COOLDOWN)
            red:close()
        end
        
        local success, challenge_id = create_guest_challenge(account.guest_slot_number, challenger_ip)
        
        if success then
            ngx.status = 202
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                challenge_required = true,
                challenge_id = challenge_id,
                slot_number = account.guest_slot_number,
                message = "An inactive user is using this slot. They have " .. CHALLENGE_TIMEOUT .. " seconds to respond or will be disconnected.",
                timeout = CHALLENGE_TIMEOUT
            }))
            return ngx.exit(202)
        else
            ngx.log(ngx.WARN, "Failed to create challenge: " .. (challenge_id or "unknown"))
            ngx.status = 503
            return ngx.exec("@custom_50x")
        end
    end
    
    -- Normal session creation
    local red = connect_redis()
    if not red then
        ngx.status = 503
        return ngx.exec("@custom_50x")
    end

    local display_name = generate_display_username()
    local now = ngx.time()
    local expires_at = now + GUEST_SESSION_DURATION

    local session = {
        username = account.username,
        user_type = "is_guest",
        jwt_token = account.token,
        guest_slot_number = account.guest_slot_number,
        session_id = display_name,
        display_username = display_name,
        created_at = now,
        expires_at = expires_at,
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = challenger_ip,
        last_activity = now,
        priority = 3,
        chat_storage = "redis",
        chat_retention_until = now + GUEST_CHAT_RETENTION
    }

    local key = "guest_active_session:" .. account.guest_slot_number
    red:set(key, cjson.encode(session))
    red:expire(key, GUEST_SESSION_DURATION)

    local user_session_key = "guest_session:" .. account.username
    red:set(user_session_key, cjson.encode(session))
    red:expire(user_session_key, GUEST_SESSION_DURATION)

    local user_key = "username:" .. account.username
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
    ngx.log(ngx.INFO, "Created session: " .. display_name .. " -> " .. account.username .. " [Slot " .. account.guest_slot_number .. "]")

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
        guest_slot_number = account.guest_slot_number,
        storage_type = "redis",
        chat_retention_days = math.floor(GUEST_CHAT_RETENTION / 86400)
    }, nil
end

-- =============================================================================
-- EXISTING FUNCTIONS
-- =============================================================================

local function validate_guest_session(token)
    if not token then return nil, "No token provided" end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then return nil, "JWT verification failed" end

    local payload = jwt_obj.payload
    if payload.user_type ~= "guest" then return nil, "Not a guest token" end

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
        red:del("guest_active_session:" .. valid_account.guest_slot_number)
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
            active_sessions = 0,
            max_sessions = MAX_GUEST_SESSIONS,
            available_slots = MAX_GUEST_SESSIONS,
            challenges_active = 0
        }
    end

    local active_count = 0
    local challenges_active = 0
    
    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        local data = redis_to_lua(red:get(key))
        
        if data then
            local ok, session = pcall(cjson.decode, data)
            if ok and session.expires_at and ngx.time() < session.expires_at then
                active_count = active_count + 1
            else
                red:del(key)
            end
        end
        
        local challenge = get_guest_challenge(i)
        if challenge then
            challenges_active = challenges_active + 1
        end
    end
    
    red:close()
    
    return {
        active_sessions = active_count,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = MAX_GUEST_SESSIONS - active_count,
        challenges_active = challenges_active
    }
end

local function cleanup_guest_session(guest_slot_number)
    if not guest_slot_number then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    local key = "guest_active_session:" .. guest_slot_number
    red:del(key)
    
    local guest_accounts = get_guest_accounts()
    for _, acc in ipairs(guest_accounts) do
        if acc.guest_slot_number == guest_slot_number then
            red:del("guest_session:" .. acc.username)
            red:del("username:" .. acc.username)
            break
        end
    end
    
    red:del("guest_challenge:" .. guest_slot_number)
    red:close()
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
        
        red:del("guest_challenge:" .. i)
        red:del("challenge_cooldown:" .. i)
    end
    
    local guest_accounts = get_guest_accounts()
    for _, acc in ipairs(guest_accounts) do
        red:del("guest_session:" .. acc.username)
        red:del("username:" .. acc.username)
    end
    
    red:close()
    return true, "Cleared " .. cleared .. " guest sessions"
end

-- =============================================================================
-- API HANDLERS
-- =============================================================================

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
        local session_data, err = create_secure_guest_session_with_challenge()
        if session_data then
            send_json(200, session_data)
        else
            send_json(429, { 
                success = false, 
                error = "no_slots_available",
                message = "All guest slots are occupied. Please try again later."
            })
        end
        
    elseif uri == "/api/guest/challenge-status" and method == "GET" then
        local slot_number = tonumber(ngx.var.arg_slot)
        if not slot_number then
            send_json(400, { error = "slot parameter required" })
        end
        
        local challenge = get_guest_challenge(slot_number)
        if challenge then
            send_json(200, {
                success = true,
                challenge_active = true,
                challenge = challenge,
                remaining_time = challenge.expires_at - ngx.time()
            })
        else
            send_json(200, {
                success = true,
                challenge_active = false,
                message = "No active challenge"
            })
        end
        
    elseif uri == "/api/guest/challenge-response" and method == "POST" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        if not body then
            send_json(400, { error = "Request body required" })
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            send_json(400, { error = "Invalid JSON" })
        end
        
        local slot_number = tonumber(data.slot_number)
        local response = data.response
        local responder_ip = ngx.var.remote_addr
        
        if not slot_number or not response then
            send_json(400, { error = "slot_number and response required" })
        end
        
        local success, result = respond_to_challenge(slot_number, response, responder_ip)
        if success then
            send_json(200, {
                success = true,
                challenge_result = result,
                message = result == "accepted" and "Challenge accepted" or "Challenge rejected"
            })
        else
            send_json(400, {
                success = false,
                error = result
            })
        end
        
    elseif uri == "/api/guest/force-claim" and method == "POST" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        if not body then
            send_json(400, { error = "Request body required" })
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            send_json(400, { error = "Invalid JSON" })
        end
        
        local slot_number = tonumber(data.slot_number)
        if not slot_number then
            send_json(400, { error = "slot_number required" })
        end
        
        local challenge = get_guest_challenge(slot_number)
        if challenge and challenge.expires_at > ngx.time() then
            send_json(400, {
                success = false,
                error = "Challenge still active",
                remaining_time = challenge.expires_at - ngx.time()
            })
        end
        
        local kick_success, kicked_user = force_kick_guest_session(slot_number, "Challenge timeout - inactive user")
        
        if kick_success then
            local session_data, err = create_secure_guest_session_with_challenge()
            if session_data then
                send_json(200, {
                    success = true,
                    session = session_data,
                    kicked_user = kicked_user,
                    message = "Inactive user removed, session created"
                })
            else
                send_json(500, {
                    success = false,
                    error = "Failed to create session after kick"
                })
            end
        else
            send_json(500, {
                success = false,
                error = "Failed to remove inactive user"
            })
        end
        
    elseif uri == "/api/guest/stats" and method == "GET" then
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

-- =============================================================================
-- PAGE HANDLERS
-- =============================================================================

local function handle_chat_page()
    local template = require "template"
    local is_who = require "is_who"
    
    local username = is_who.require_guest()
    local nav_buttons = is_who.get_nav_buttons("is_guest", username, nil)
    local chat_features = is_who.get_chat_features("is_guest")
    
    local context = {
        page_title = "Guest Chat",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = username or "guest",
        dash_buttons = nav_buttons,
        chat_features = chat_features,
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 30 minutes)"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat_guest.html", context)
end

local function handle_chat_stream()
    local server = require "server"
    local is_who = require "is_who"
    
    local username, user_data = is_who.require_guest()
    
    local function update_guest_message_count()
        if not user_data or not user_data.guest_slot_number then
            return false
        end
        
        local red = connect_redis()
        if not red then return false end
        
        user_data.message_count = (user_data.message_count or 0) + 1
        user_data.last_activity = ngx.time()
        
        local session_key = "guest_active_session:" .. user_data.guest_slot_number
        local user_session_key = "guest_session:" .. user_data.username
        
        red:set(session_key, cjson.encode(user_data))
        red:expire(session_key, GUEST_SESSION_DURATION)
        
        red:set(user_session_key, cjson.encode(user_data))
        red:expire(user_session_key, GUEST_SESSION_DURATION)
        
        red:close()
        return true
    end
    
    local function pre_stream_check(message, request_data)
        local current_count = user_data.message_count or 0
        
        if current_count >= user_data.max_messages then
            return false, "Guest message limit reached (" .. user_data.max_messages .. " messages). Register for unlimited access."
        end
        
        if ngx.time() >= user_data.expires_at then
            return false, "Guest session expired. Please start a new session."
        end
        
        update_guest_message_count()
        return true, nil
    end
    
    local stream_context = {
        user_type = "is_guest",
        username = username,
        include_history = false,
        history_limit = 0,
        get_history = nil,
        save_user_message = nil,
        save_ai_response = nil,
        pre_stream_check = pre_stream_check,
        default_options = {
            temperature = 0.7,
            max_tokens = 512,
            num_predict = 1,
            num_ctx = 64,
            priority = 3
        },
        post_stream_cleanup = function(response)
            ngx.log(ngx.INFO, "Guest stream completed for: " .. (username or "unknown"))
        end
    }
    
    server.handle_chat_stream_common(stream_context)
end

local function handle_chat_api()
    local cjson = require "cjson"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    local is_who = require "is_who"
    local username = is_who.require_guest()
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        send_json(200, {
            success = true,
            messages = {},
            user_type = "is_guest",
            storage_type = "none",
            note = "Guest users don't have persistent chat history"
        })
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        send_json(200, { 
            success = true, 
            message = "Guest chat uses localStorage only - clear from browser"
        })
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        handle_chat_stream()
        
    else
        send_json(404, { 
            error = "Guest Chat API endpoint not found",
            requested = method .. " " .. uri
        })
    end
end

return {
    create_secure_guest_session = create_secure_guest_session_with_challenge,
    validate_guest_session = validate_guest_session,
    generate_display_username = generate_display_username,
    get_guest_stats = get_guest_stats,
    cleanup_guest_session = cleanup_guest_session,
    clear_all_guest_sessions = clear_all_guest_sessions,
    handle_chat_page = handle_chat_page,
    handle_guest_api = handle_guest_api,
    handle_chat_api = handle_chat_api,
    handle_chat_stream = handle_chat_stream,
    
    -- New challenge system functions
    create_guest_challenge = create_guest_challenge,
    get_guest_challenge = get_guest_challenge,
    respond_to_challenge = respond_to_challenge,
    force_kick_guest_session = force_kick_guest_session
}