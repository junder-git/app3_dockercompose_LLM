-- =============================================================================
-- nginx/lua/is_none.lua - IMPORT SHARED FUNCTIONS FROM manage_auth
-- =============================================================================

local template = require "manage_template"
local cjson = require "cjson"
local jwt = require "resty.jwt"

-- Import required modules
local auth = require "manage_auth"

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 600  -- 10 minutes
local GUEST_MESSAGE_LIMIT = 10
local GUEST_CHAT_RETENTION = 259200  -- 3 days
local CHALLENGE_TIMEOUT = 8  -- 8 seconds for challenge response
local CHALLENGE_COOLDOWN = 0  -- 0 seconds between challenges
local INACTIVE_THRESHOLD = 3  -- 3secs to be considered inactive

local JWT_SECRET = os.getenv("JWT_SECRET")

-- =============================================
-- HELPER FUNCTIONS - IMPORT FROM manage_auth
-- =============================================

-- Use shared Redis functions from manage_auth
local redis_to_lua = auth.redis_to_lua
local connect_redis = auth.connect_redis

local USERNAME_POOLS = {
    adjectives = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Cosmic", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural"},
    animals = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}
}

local function get_guest_accounts()
    local now = ngx.time()
    return {
        {
            username = "guest_user_1",
            password = "nkcukfulnckfckufnckdgjvjgv",
            token = jwt:sign(JWT_SECRET, {
                header = { typ = "JWT", alg = "HS256" },
                payload = {
                    username = "guest_user_1",
                    user_type = "is_guest",
                    iat = now,
                    exp = now + GUEST_SESSION_DURATION
                }
            })
        },
        {
            username = "guest_user_2", 
            password = "ymbkclhfpbdfbsdfwdsbwfdsbp",
            token = jwt:sign(JWT_SECRET, {
                header = { typ = "JWT", alg = "HS256" },
                payload = {
                    username = "guest_user_2",
                    user_type = "is_guest",
                    iat = now,
                    exp = now + GUEST_SESSION_DURATION
                }
            })
        }
    }
end

-- Generate navigation buttons for public users
local function get_nav_buttons()
    return '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
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
    local guest_accounts = get_guest_accounts()
    
    for _, account in ipairs(guest_accounts) do
        local session_key = "guest_active_session:" .. account.username
        local session_data = redis_to_lua(red:get(session_key))
        
        if session_data then
            local ok, session = pcall(cjson.decode, session_data)
            if ok and session.expires_at and ngx.time() < session.expires_at then
                active_count = active_count + 1
            else
                -- Clean expired session
                red:del(session_key)
            end
        end
        
        local challenge_key = "guest_challenge:" .. account.username
        local challenge_data = redis_to_lua(red:get(challenge_key))
        if challenge_data then
            local ok, challenge = pcall(cjson.decode, challenge_data)
            if ok and challenge.expires_at and ngx.time() < challenge.expires_at then
                challenges_active = challenges_active + 1
            else
                red:del(challenge_key)
            end
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

-- =============================================
-- CHALLENGE SYSTEM FUNCTIONS
-- =============================================

local function create_guest_challenge(username)
    local red = connect_redis()
    if not red then return false, "Redis unavailable" end
    
    local challenge_id = "challenge_" .. username .. "_" .. ngx.time() .. "_" .. math.random(1000, 9999)
    local challenge_key = "guest_challenge:" .. username
    
    -- Check if challenge already exists for this guest user
    local existing_challenge = redis_to_lua(red:get(challenge_key))
    if existing_challenge then
        local ok, challenge_data = pcall(cjson.decode, existing_challenge)
        if ok and challenge_data.expires_at > ngx.time() then
            red:close()
            return false, "Challenge already active for " .. username
        end
    end
    
    local challenge = {
        challenge_id = challenge_id,
        username = username,
        created_at = ngx.time(),
        expires_at = ngx.time() + CHALLENGE_TIMEOUT,
        status = "pending"
    }
    
    red:set(challenge_key, cjson.encode(challenge))
    red:expire(challenge_key, CHALLENGE_TIMEOUT + 5)
    red:close()
    
    ngx.log(ngx.INFO, "🚨 Guest challenge created for " .. username)
    return true, challenge_id
end

local function get_guest_challenge(username)
    local red = connect_redis()
    if not red then return nil end
    
    local challenge_key = "guest_challenge:" .. username
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
    
    if challenge.expires_at <= ngx.time() then
        ngx.log(ngx.WARN, "🚨 Challenge expired for " .. username .. " - auto-kicking inactive user")
        
        red:del(challenge_key)
        
        local session_key = "guest_active_session:" .. username
        local session_data = redis_to_lua(red:get(session_key))
        if session_data then
            local session_ok, session = pcall(cjson.decode, session_data)
            if session_ok then
                red:del("guest_session:" .. session.username)
                red:del("username:" .. session.username)
                ngx.log(ngx.WARN, "👢 Auto-kicked inactive user '" .. (session.display_username or session.username) .. "' (no challenge response)")
            end
            red:del(session_key)
        end
        
        red:close()
        return nil
    end
    
    red:close()
    return challenge
end

local function respond_to_challenge(username, response, responder_ip)
    local red = connect_redis()
    if not red then return false, "Redis unavailable" end
    
    local challenge_key = "guest_challenge:" .. username
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
    
    if challenge.expires_at <= ngx.time() then
        red:del(challenge_key)
        red:close()
        return false, "Challenge expired"
    end
    
    challenge.response = response
    challenge.responder_ip = responder_ip
    challenge.responded_at = ngx.time()
    challenge.status = response == "accept" and "accepted" or "rejected"
    
    red:set(challenge_key, cjson.encode(challenge))
    red:expire(challenge_key, 60)
    red:close()
    
    ngx.log(ngx.INFO, "✅ Challenge response for " .. username .. ": " .. response .. " by " .. responder_ip)
    return true, challenge.status
end

-- =============================================
-- SESSION MANAGEMENT FUNCTIONS
-- =============================================

local function find_available_guest_slot_or_challenge()
    local red = connect_redis()
    if not red then return nil, "Service unavailable" end
    local guest_accounts = get_guest_accounts()
    
    -- Check each guest account
    for _, account in ipairs(guest_accounts) do
        local session_key = "guest_active_session:" .. account.username
        local session_data = redis_to_lua(red:get(session_key))
        
        -- If no active session, this slot is available
        if not session_data then
            red:close()
            return account, nil
        end
        
        -- Check if session is expired
        local ok, session = pcall(cjson.decode, session_data)
        if ok and session.expires_at and ngx.time() >= session.expires_at then
            -- Clean up expired session
            red:del(session_key)
            red:del("guest_session:" .. session.username)
            red:del("username:" .. session.username)
            red:del("guest_challenge:" .. account.username)
            ngx.log(ngx.INFO, "🧹 Auto-cleaned expired session for " .. account.username)
            red:close()
            return account, nil
        end
        
        -- Check if there's an active challenge that expired
        local challenge = get_guest_challenge(account.username)
        if not challenge then
            -- No challenge, but session exists, check if it's still valid
            local session_check = redis_to_lua(red:get(session_key))
            if not session_check then
                ngx.log(ngx.INFO, "🎯 Slot " .. account.username .. " freed by expired challenge cleanup")
                red:close()
                return account, nil
            end
        end
    end
    
    -- All slots are occupied, need to challenge one
    -- Toggle between guest_user_1 and guest_user_2
    local toggle_dict = ngx.shared.guest_toggle
    local last = toggle_dict:get("last_slot") or 1
    local j = (last == 1) and 2 or 1
    toggle_dict:set("last_slot", j)
    
    local target_account = guest_accounts[j]
    ngx.log(ngx.INFO, "🎲 All slots occupied - will challenge " .. target_account.username)
    red:close()
    return target_account, "challengeable"
end

local function create_secure_guest_session_with_challenge()
    local account, slot_status = find_available_guest_slot_or_challenge()
    
    if not slot_status then
        -- Slot is available, create session immediately
        local red = connect_redis()
        if not red then
            ngx.status = 503
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                error = "redis_connection_failed",
                message = "Database connection failed"
            }))
            return
        end
        
        local display_name = generate_display_username()
        local now = ngx.time()
        local expires_at = now + GUEST_SESSION_DURATION
        
        local session = {
            username = account.username,
            user_type = "is_guest",
            jwt_token = account.token,
            session_id = display_name,
            display_username = display_name,
            created_at = now,
            expires_at = expires_at,
            message_count = 0,
            max_messages = GUEST_MESSAGE_LIMIT,
            last_activity = now,
            priority = 3,
            chat_storage = "redis",
            chat_retention_until = now + GUEST_CHAT_RETENTION
        }
        
        local session_key = "guest_active_session:" .. account.username
        red:set(session_key, cjson.encode(session))
        red:expire(session_key, GUEST_SESSION_DURATION)
        
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
        
        ngx.log(ngx.INFO, "✅ GUEST SESSION CREATION SUCCESS")
        ngx.log(ngx.INFO, "Created session: " .. display_name .. " -> " .. account.username)
        
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            username = display_name,
            internal_username = account.username,
            session_id = display_name,
            token = account.token,
            expires_at = expires_at,
            message_limit = GUEST_MESSAGE_LIMIT,
            session_duration = GUEST_SESSION_DURATION,
            priority = 3,
            storage_type = "redis",
            chat_retention_days = math.floor(GUEST_CHAT_RETENTION / 86400),
            redirect = "/chat"
        }))
        return
        
    elseif slot_status == "challengeable" then
        -- Need to challenge the current user
        local success, challenge_id = create_guest_challenge(account.username)
        
        if success then
            ngx.status = 202
            ngx.header.content_type = 'application/json'
            
            ngx.say(cjson.encode({
                success = false,
                challenge_required = true,
                challenge_id = challenge_id,
                username = account.username,
                message = "An inactive user is using this slot. They have " .. CHALLENGE_TIMEOUT .. " seconds to respond or will be disconnected.",
                timeout = CHALLENGE_TIMEOUT
            }))
            
            return
        else
            ngx.status = 500
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                error = "challenge_creation_failed",
                message = "Unable to challenge inactive user. Please try again."
            }))
            return
        end
    else
        -- All slots occupied and challenges active
        ngx.status = 429
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "all_slots_busy",
            message = "All guest sessions are occupied and challenges are active. Please try again in a few moments."
        }))
        return
    end
end

-- =============================================
-- API HANDLERS
-- =============================================

local function handle_guest_session_api()
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/guest/create-session" and method == "POST" then
        create_secure_guest_session_with_challenge()
        
    elseif uri == "/api/guest/challenge-status" and method == "GET" then
        local username = ngx.var.arg_username
        if not username then
            send_json(400, { error = "username parameter required" })
        end
        
        local challenge = get_guest_challenge(username)
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
        
        local username = data.username
        local response = data.response
        local responder_ip = ngx.var.remote_addr
        
        if not username or not response then
            send_json(400, { error = "username and response required" })
        end
        
        local success, result = respond_to_challenge(username, response, responder_ip)
        if success then
            send_json(200, {
                success = true,
                challenge_result = result,
                message = result == "accepted" and "Challenge accepted" or "Challenge rejected"
            })
        else
            send_json(500, {
                success = false,
                error = result,
                message = "Challenge response failed"
            })
        end
        
    elseif uri == "/api/guest/stats" and method == "GET" then
        local stats = get_guest_stats()
        send_json(200, {
            success = true,
            stats = stats
        })
        
    else
        send_json(404, { error = "API endpoint not found" })
    end
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {   
    -- API handlers
    handle_guest_session_api = handle_guest_session_api,
    
    -- Helper functions that might be needed by other modules
    get_guest_stats = get_guest_stats,
    
    -- Session management functions
    create_secure_guest_session_with_challenge = create_secure_guest_session_with_challenge,
    find_available_guest_slot_or_challenge = find_available_guest_slot_or_challenge,
    
    -- Challenge system functions
    create_guest_challenge = create_guest_challenge,
    get_guest_challenge = get_guest_challenge,
    respond_to_challenge = respond_to_challenge,
    
    -- Utility functions
    get_guest_accounts = get_guest_accounts,
    generate_display_username = generate_display_username,
}