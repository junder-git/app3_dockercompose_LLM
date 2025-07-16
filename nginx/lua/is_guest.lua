-- =============================================================================
-- nginx/lua/is_guest.lua - IMPROVED GUEST SESSION MANAGEMENT
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
local JWT_COOLDOWN_SECONDS = 60
local CURRENT_VERSION = "v2.1"

-- HELPER: Safe Redis response handling
local function redis_to_lua(value)
    if value == ngx.null or value == nil then
        return nil
    end
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

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- GUEST USER MANAGEMENT - CREATE PERSISTENT GUEST ACCOUNTS
-- =============================================

-- Create persistent guest user accounts in Redis
local function create_guest_user_accounts()
    local red = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    local server = require "server"
    
    -- Create 2 permanent guest user accounts
    for i = 1, MAX_GUEST_SESSIONS do
        local guest_username = "guest_slot_" .. i
        local guest_password = "hardcoded_guest_pass_" .. i .. "_secure"
        
        -- Check if guest user already exists
        local existing_user = server.get_user(guest_username)
        if not existing_user then
            -- Create the guest user account
            local guest_user_data = {
                username = guest_username,
                password_hash = server.hash_password(guest_password),
                is_admin = "false",
                is_approved = "false",
                is_guest_account = "true",
                slot_number = i,
                created_at = os.date("!%Y-%m-%dT%TZ"),
                last_login = "never",
                version = CURRENT_VERSION
            }
            
            -- Store in Redis using server module pattern
            local user_key = "user:" .. guest_username
            red:hmset(user_key, guest_user_data)
            red:expire(user_key, 86400 * 30) -- 30 days expiry, refreshed on use
            
            ngx.log(ngx.INFO, "Created persistent guest account: " .. guest_username)
        else
            ngx.log(ngx.INFO, "Guest account already exists: " .. guest_username)
        end
    end
    
    red:set("guest_accounts_initialized", CURRENT_VERSION)
    red:expire("guest_accounts_initialized", 86400)
    
    return true, "Guest accounts ready"
end

-- =============================================
-- IMPROVED GUEST SESSION LOGIC
-- =============================================

-- Initialize guest system
local function initialize_guest_system()
    local red = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    local initialized = redis_to_lua(red:get("guest_system_initialized"))
    if initialized == CURRENT_VERSION then
        return true, "Already initialized"
    end
    
    -- Clean up old guest sessions
    local old_sessions = redis_to_lua(red:keys("guest_session:*")) or {}
    for _, key in ipairs(old_sessions) do
        red:del(key)
    end
    
    -- Create persistent guest user accounts
    local ok, err = create_guest_user_accounts()
    if not ok then
        return false, err
    end
    
    red:set("guest_system_initialized", CURRENT_VERSION)
    red:expire("guest_system_initialized", 86400)
    
    ngx.log(ngx.INFO, "Guest system initialized with " .. MAX_GUEST_SESSIONS .. " slots")
    return true, "Initialized"
end

-- Find available guest slot and return user credentials
local function find_available_guest_slot()
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    -- Ensure guest system is initialized
    local ok, err = initialize_guest_system()
    if not ok then
        return nil, err
    end
    
    local current_time = ngx.time()
    
    for i = 1, MAX_GUEST_SESSIONS do
        local guest_username = "guest_slot_" .. i
        local session_key = "guest_active_session:" .. i
        
        -- Check if this slot is currently active
        local active_session = redis_to_lua(red:get(session_key))
        
        if not active_session then
            -- Slot is free, return guest credentials
            return {
                username = guest_username,
                password = "hardcoded_guest_pass_" .. i .. "_secure",
                slot_number = i,
                slot_id = "guest_slot_" .. i
            }, nil
        else
            -- Check if session expired
            local ok_session, session_data = pcall(cjson.decode, active_session)
            if ok_session and session_data.expires_at and current_time >= session_data.expires_at then
                -- Clean expired session
                red:del(session_key)
                return {
                    username = guest_username,
                    password = "hardcoded_guest_pass_" .. i .. "_secure",
                    slot_number = i,
                    slot_id = "guest_slot_" .. i
                }, nil
            end
        end
    end
    
    return nil, "All guest slots occupied (" .. MAX_GUEST_SESSIONS .. "/" .. MAX_GUEST_SESSIONS .. ")"
end

-- Create guest session using existing authentication flow
local function create_secure_guest_session()
    local slot_data, error_msg = find_available_guest_slot()
    if not slot_data then
        return nil, error_msg
    end
    
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    local server = require "server"
    
    -- Authenticate the guest user using existing server methods
    local user_data = server.get_user(slot_data.username)
    if not user_data then
        return nil, "Guest account not found: " .. slot_data.username
    end
    
    -- Verify guest password
    local valid = server.verify_password(slot_data.password, user_data.password_hash)
    if not valid then
        return nil, "Guest authentication failed"
    end
    
    -- Generate proper JWT token using existing auth flow
    local payload = {
        username = slot_data.username,
        user_type = "guest",
        slot_number = slot_data.slot_number,
        iat = ngx.time(),
        exp = ngx.time() + GUEST_SESSION_DURATION
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    -- Create session record
    local expires_at = ngx.time() + GUEST_SESSION_DURATION
    local session_data = {
        username = slot_data.username,
        user_type = "guest",
        jwt_token = token,
        created_at = ngx.time(),
        expires_at = expires_at,
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = ngx.var.remote_addr or "unknown",
        last_activity = ngx.time(),
        priority = 3,
        slot_number = slot_data.slot_number,
        chat_storage = "none"
    }
    
    -- Store active session
    local session_key = "guest_active_session:" .. slot_data.slot_number
    red:set(session_key, cjson.encode(session_data))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    -- Also store by username for is_who compatibility  
    local user_session_key = "guest_session:" .. slot_data.username
    red:set(user_session_key, cjson.encode(session_data))
    red:expire(user_session_key, GUEST_SESSION_DURATION)
    
    -- Update user last login
    server.update_user_activity(slot_data.username)
    
    -- Set JWT cookie
    ngx.header["Set-Cookie"] = "access_token=" .. token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    ngx.log(ngx.INFO, "Guest session created: " .. slot_data.username .. " [Slot " .. slot_data.slot_number .. "] from " .. (ngx.var.remote_addr or "unknown"))
    
    return {
        success = true,
        username = slot_data.username,
        token = token,
        expires_at = expires_at,
        message_limit = GUEST_MESSAGE_LIMIT,
        session_duration = GUEST_SESSION_DURATION,
        priority = 3,
        slot_number = slot_data.slot_number,
        storage_type = "none"
    }, nil
end

-- Cleanup guest session
local function cleanup_guest_session(slot_number)
    local red = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    local guest_username = "guest_slot_" .. slot_number
    
    -- Remove active session
    red:del("guest_active_session:" .. slot_number)
    red:del("guest_session:" .. guest_username)
    
    ngx.log(ngx.INFO, "Cleaned up guest session for slot " .. slot_number)
    return true, "Session cleaned"
end

-- Validate guest session
local function validate_guest_session(token)
    if not token then
        return nil, "No token provided"
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        return nil, "Invalid token"
    end
    
    local payload = jwt_obj.payload
    if not payload.username or payload.user_type ~= "guest" then
        return nil, "Invalid guest token"
    end
    
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    -- Check both session keys for compatibility
    local session_key = "guest_session:" .. payload.username
    local session_data = redis_to_lua(red:get(session_key))
    
    if not session_data then
        -- Try alternate key
        local alt_key = "guest_active_session:" .. (payload.slot_number or "")
        session_data = redis_to_lua(red:get(alt_key))
    end
    
    if not session_data then
        return nil, "Session not active"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        return nil, "Invalid session data"
    end
    
    if ngx.time() >= session.expires_at then
        cleanup_guest_session(session.slot_number)
        return nil, "Session expired"
    end
    
    -- Update activity
    session.last_activity = ngx.time()
    red:set(session_key, cjson.encode(session))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    if session.slot_number then
        local alt_key = "guest_active_session:" .. session.slot_number
        red:set(alt_key, cjson.encode(session))
        red:expire(alt_key, GUEST_SESSION_DURATION)
    end
    
    return session, nil
end

-- Get guest stats
local function get_guest_stats()
    local red = connect_redis()
    if not red then
        return {
            active_sessions = 0,
            max_sessions = MAX_GUEST_SESSIONS,
            available_slots = 0,
            error = "Redis unavailable"
        }, "Service unavailable"
    end
    
    -- Count active sessions
    local active_sessions = 0
    local current_time = ngx.time()
    
    for i = 1, MAX_GUEST_SESSIONS do
        local session_key = "guest_active_session:" .. i
        local session_data = redis_to_lua(red:get(session_key))
        
        if session_data then
            local ok, session = pcall(cjson.decode, session_data)
            if ok and session.expires_at then
                if current_time < session.expires_at then
                    active_sessions = active_sessions + 1
                else
                    -- Clean expired session
                    cleanup_guest_session(i)
                end
            end
        end
    end
    
    return {
        active_sessions = active_sessions,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = MAX_GUEST_SESSIONS - active_sessions
    }, nil
end

-- Clear all guest sessions (admin function)
local function clear_all_guest_sessions()
    local red = connect_redis()
    if not red then
        return false, "Service unavailable"
    end
    
    for i = 1, MAX_GUEST_SESSIONS do
        cleanup_guest_session(i)
    end
    
    red:del("guest_system_initialized")
    red:del("guest_accounts_initialized")
    
    return true, "Cleared all guest sessions. System will re-initialize."
end

-- =============================================
-- API HANDLERS - Guest Session Management
-- =============================================

-- Create secure guest session
local function handle_create_guest_session()
    local ip = ngx.var.remote_addr or "unknown"
    local rate_limit_key = "guest_create_attempts:" .. ip
    local attempts = ngx.shared.guest_sessions:get(rate_limit_key) or 0
    
    if attempts >= 3 then
        ngx.log(ngx.WARN, "Too many guest session creation attempts from " .. ip)
        send_json(429, { 
            error = "Too many guest session attempts",
            message = "Please wait before creating another guest session",
            retry_after = 300,
            cooldown_minutes = 5
        })
    end
    
    local session_data, error_msg = create_secure_guest_session()
    
    if not session_data then
        ngx.shared.guest_sessions:set(rate_limit_key, attempts + 1, 300)
        ngx.log(ngx.WARN, "Guest session creation failed from " .. ip .. ": " .. (error_msg or "unknown"))
        
        send_json(503, {
            error = "Guest session creation failed",
            message = error_msg or "All guest slots are currently occupied",
            available_soon = true,
            suggestion = "Try again in a few minutes or register for guaranteed access",
            max_guests = MAX_GUEST_SESSIONS,
            slots_full = true
        })
    end
    
    ngx.shared.guest_sessions:delete(rate_limit_key)
    
    send_json(200, {
        success = true,
        message = "Guest session created successfully",
        session = {
            username = session_data.username,
            slot_number = session_data.slot_number,
            slot_id = session_data.slot_id,
            message_limit = session_data.message_limit,
            session_duration_minutes = math.floor(session_data.session_duration / 60),
            expires_at = session_data.expires_at,
            priority = session_data.priority,
            storage_type = session_data.storage_type
        },
        instructions = {
            "You have " .. session_data.message_limit .. " messages available",
            "Session expires in " .. math.floor(session_data.session_duration / 60) .. " minutes", 
            "Chat history is not saved (register for persistent storage)",
            "Your messages are processed with priority " .. session_data.priority .. " (lowest)"
        },
        security = {
            persistent_guest_account = true,
            anti_hijacking = true,
            slot_locked = true,
            uses_standard_auth = true
        },
        redirect = "/chat"
    })
end

-- Get guest session info
local function handle_guest_info()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type ~= "guest" then
        send_json(403, {
            error = "Not a guest session",
            user_type = user_type or "none",
            message = "This endpoint requires an active guest session"
        })
    end
    
    if not user_data or not user_data.slot_number then
        send_json(404, {
            error = "Guest session not found",
            message = "Session may have expired or been invalidated",
            suggestion = "Create a new guest session"
        })
    end
    
    send_json(200, {
        success = true,
        session = {
            username = user_data.username,
            slot_number = user_data.slot_number,
            max_messages = user_data.max_messages,
            used_messages = user_data.message_count,
            remaining_messages = user_data.max_messages - user_data.message_count,
            session_remaining_seconds = user_data.expires_at - ngx.time(),
            session_remaining_minutes = math.floor((user_data.expires_at - ngx.time()) / 60),
            priority = user_data.priority,
            storage_type = user_data.chat_storage
        },
        status = {
            can_chat = (user_data.max_messages - user_data.message_count) > 0,
            session_active = user_data.expires_at > ngx.time(),
            slot_secured = true
        }
    })
end

-- Get guest session stats
local function handle_guest_stats()
    local stats, err = get_guest_stats()
    if not stats then
        send_json(500, {
            error = "Failed to get guest stats",
            message = err or "Service unavailable"
        })
    end
    
    send_json(200, {
        success = true,
        stats = stats,
        info = {
            message_limit_per_guest = GUEST_MESSAGE_LIMIT,
            session_duration_minutes = math.floor(GUEST_SESSION_DURATION / 60),
            persistent_guest_accounts = true,
            uses_standard_auth = true,
            max_concurrent_guests = MAX_GUEST_SESSIONS
        },
        availability = {
            can_create_session = stats.available_slots > 0,
            estimated_wait_time = stats.available_slots == 0 and "1-30 minutes" or "immediate"
        }
    })
end

-- End guest session
local function handle_end_guest_session()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type ~= "guest" then
        send_json(403, {
            error = "Not a guest session",
            message = "Only active guest sessions can be ended"
        })
    end
    
    if user_data and user_data.slot_number then
        cleanup_guest_session(user_data.slot_number)
        
        -- Clear cookies
        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        
        ngx.log(ngx.INFO, "Guest session ended voluntarily: " .. (username or "unknown") .. " [Slot " .. user_data.slot_number .. "]")
        
        send_json(200, {
            success = true,
            message = "Guest session ended successfully",
            slot_freed = true,
            slot_number = user_data.slot_number
        })
    else
        send_json(404, {
            error = "Session not found",
            message = "No active guest session to end"
        })
    end
end

-- =============================================
-- API ROUTING
-- =============================================

local function handle_guest_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "Guest API access: " .. method .. " " .. uri .. " from " .. (ngx.var.remote_addr or "unknown"))
    
    if uri == "/api/guest/create-session" and method == "POST" then
        handle_create_guest_session()
    elseif uri == "/api/guest/info" and method == "GET" then
        handle_guest_info()
    elseif uri == "/api/guest/stats" and method == "GET" then
        handle_guest_stats()
    elseif uri == "/api/guest/end-session" and method == "POST" then
        handle_end_guest_session()
    else
        send_json(404, { 
            error = "Guest API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/guest/create-session - Create new guest session",
                "GET /api/guest/info - Get current session info", 
                "GET /api/guest/stats - Get public guest statistics",
                "POST /api/guest/end-session - End current session"
            }
        })
    end
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    -- API handlers
    handle_guest_api = handle_guest_api,
    
    -- Core functions (for other modules to use)
    create_secure_guest_session = create_secure_guest_session,
    validate_guest_session = validate_guest_session,
    get_guest_stats = get_guest_stats,
    clear_all_guest_sessions = clear_all_guest_sessions,
    cleanup_guest_session = cleanup_guest_session,
    initialize_guest_system = initialize_guest_system
}