-- =============================================================================
-- nginx/lua/is_guest.lua - HARDCODED JWT WITH RANDOM UI USERNAMES + PERSISTENT CHAT
-- =============================================================================

local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 1800  -- 30 minutes for active session
local GUEST_MESSAGE_LIMIT = 10
local GUEST_CHAT_RETENTION = 259200   -- 3 days for chat history persistence

-- Random username pools for UI display
local USERNAME_POOLS = {
    {
        adjectives = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool"},
        animals = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog"}
    },
    {
        adjectives = {"Cosmic", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural"},
        animals = {"Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}
    }
}

-- HARDCODED GUEST ACCOUNTS - Simple username-based like regular users
local GUEST_ACCOUNTS = {
    {
        slot_number = 1,
        username = "guest_slot_1",
        token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1c2VybmFtZSI6Imd1ZXN0X3Nsb3RfMSIsInVzZXJfdHlwZSI6Imd1ZXN0IiwicHJpb3JpdHkiOjMsInNsb3RfbnVtYmVyIjoxLCJpYXQiOjE2NDA5OTUyMDAsImV4cCI6OTk5OTk5OTk5OX0"
    },
    {
        slot_number = 2,
        username = "guest_slot_2", 
        token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1c2VybmFtZSI6Imd1ZXN0X3Nsb3RfMiIsInVzZXJfdHlwZSI6Imd1ZXN0IiwicHJpb3JpdHkiOjMsInNsb3RfbnVtYmVyIjoyLCJpYXQiOjE2NDA5OTUyMDAsImV4cCI6OTk5OTk5OTk5OX0"
    }
}

-- Generate actual JWTs on module load
local function generate_guest_jwts()
    for i, guest_data in ipairs(GUEST_ACCOUNTS) do
        local payload = {
            username = guest_data.username,
            user_type = "guest",
            priority = 3,
            slot_number = guest_data.slot_number,
            iat = 1640995200,  -- Fixed timestamp
            exp = 9999999999   -- Far future expiry (JWT doesn't expire, session does)
        }
        
        local token = jwt:sign(JWT_SECRET, {
            header = { typ = "JWT", alg = "HS256" },
            payload = payload
        })
        
        GUEST_ACCOUNTS[i].token = token
        ngx.log(ngx.INFO, "Generated hardcoded JWT for " .. guest_data.username)
    end
end

-- Initialize JWTs on module load
generate_guest_jwts()

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

-- Generate random display username for UI (with collision prevention)
local function generate_display_username(slot_number)
    local red = connect_redis()
    if not red then
        -- Fallback if Redis unavailable
        local pool = USERNAME_POOLS[slot_number] or USERNAME_POOLS[1]
        local adjective = pool.adjectives[math.random(#pool.adjectives)]
        local animal = pool.animals[math.random(#pool.animals)]
        local number = math.random(100, 999)
        return adjective .. animal .. number
    end
    
    local pool = USERNAME_POOLS[slot_number] or USERNAME_POOLS[1]
    local max_attempts = 3  -- Prevent infinite loops
    local attempts = 0
    
    while attempts < max_attempts do
        local adjective = pool.adjectives[math.random(#pool.adjectives)]
        local animal = pool.animals[math.random(#pool.animals)]
        local number = math.random(100, 999)
        local candidate_username = adjective .. animal .. number
        
        -- Check if this username is blacklisted (currently in use or recently used)
        local blacklist_key = "guest_username_blacklist:" .. candidate_username
        local is_blacklisted = redis_to_lua(red:get(blacklist_key))
        
        if not is_blacklisted then
            -- Username is available, blacklist it for 3 days + buffer
            red:set(blacklist_key, "1")
            red:expire(blacklist_key, GUEST_CHAT_RETENTION + 3600)  -- 3 days + 1 hour buffer
            
            ngx.log(ngx.INFO, "Generated unique session username: " .. candidate_username .. " (attempt " .. (attempts + 1) .. ")")
            return candidate_username
        end
        
        attempts = attempts + 1
        ngx.log(ngx.DEBUG, "Username collision detected: " .. candidate_username .. " (attempt " .. attempts .. ")")
    end
    
    -- Fallback: if we can't find a unique name after max_attempts, use timestamp suffix
    local pool = USERNAME_POOLS[slot_number] or USERNAME_POOLS[1]
    local adjective = pool.adjectives[math.random(#pool.adjectives)]
    local animal = pool.animals[math.random(#pool.animals)]
    local timestamp_suffix = tostring(ngx.time()):sub(-4)  -- Last 4 digits of timestamp
    local fallback_username = adjective .. animal .. timestamp_suffix
    
    -- Still blacklist the fallback
    local blacklist_key = "guest_username_blacklist:" .. fallback_username
    red:set(blacklist_key, "1")
    red:expire(blacklist_key, GUEST_CHAT_RETENTION + 3600)
    
    ngx.log(ngx.WARN, "Used fallback username generation: " .. fallback_username .. " after " .. max_attempts .. " attempts")
    return fallback_username
end

-- =============================================
-- GUEST SESSION MANAGEMENT
-- =============================================

-- Find available guest slot
local function find_available_guest_slot()
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    local current_time = ngx.time()
    
    for i = 1, MAX_GUEST_SESSIONS do
        local session_key = "guest_active_session:" .. i
        local active_session = redis_to_lua(red:get(session_key))
        
        if not active_session then
            -- Slot is free
            return GUEST_ACCOUNTS[i], nil
        else
            -- Check if session expired
            local ok_session, session_data = pcall(cjson.decode, active_session)
            if ok_session and session_data.expires_at and current_time >= session_data.expires_at then
                -- Clean expired session but keep chat history
                red:del(session_key)
                return GUEST_ACCOUNTS[i], nil
            end
        end
    end
    
    return nil, "All guest slots occupied (" .. MAX_GUEST_SESSIONS .. "/" .. MAX_GUEST_SESSIONS .. ")"
end

-- Create guest session using hardcoded JWT
local function create_secure_guest_session()
    ngx.log(ngx.INFO, "=== GUEST SESSION CREATION START ===")
    
    local account_data, error_msg = find_available_guest_slot()
    if not account_data then
        ngx.log(ngx.WARN, "No available guest slot: " .. (error_msg or "unknown"))
        return nil, error_msg
    end
    
    ngx.log(ngx.INFO, "Found available slot: " .. account_data.slot_number)
    
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    -- Generate random display username - this becomes the session_id for admin tracking
    local session_username = generate_display_username(account_data.slot_number)
    local session_start_time = ngx.time()
    
    -- Create session record
    local expires_at = session_start_time + GUEST_SESSION_DURATION
    local session_data = {
        -- Standard auth fields (same as regular users)
        username = account_data.username,  -- guest_slot_1 or guest_slot_2 (for JWT)
        user_type = "guest",
        jwt_token = account_data.token,
        slot_number = account_data.slot_number,
        
        -- Session tracking (for UI and admin)
        session_id = session_username,     -- QuickFox123 - unique session identifier
        display_username = session_username,
        display_name = session_username,
        
        -- Session data
        created_at = session_start_time,
        expires_at = expires_at,
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = ngx.var.remote_addr or "unknown",
        last_activity = session_start_time,
        priority = 3,
        chat_storage = "redis",
        chat_retention_until = session_start_time + GUEST_CHAT_RETENTION
    }
    
    -- Store active session by slot number
    local session_key = "guest_active_session:" .. account_data.slot_number
    local ok, err = red:set(session_key, cjson.encode(session_data))
    if not ok then
        ngx.log(ngx.ERR, "Failed to store guest session: " .. (err or "unknown"))
        return nil, "Failed to store session"
    end
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    -- Store session by username for JWT validation (same pattern as regular users)
    local user_session_key = "guest_session:" .. account_data.username
    red:set(user_session_key, cjson.encode(session_data))
    red:expire(user_session_key, GUEST_SESSION_DURATION)
    
    -- Initialize chat history using session_username as key (for admin dashboard)
    local chat_key = "chat_history:guest:" .. session_username
    local chat_record = {
        session_id = session_username,
        internal_username = account_data.username,  -- guest_slot_1/guest_slot_2
        display_username = session_username,        -- QuickFox123
        slot_number = account_data.slot_number,
        user_type = "guest",
        created_at = session_start_time,
        created_ip = ngx.var.remote_addr or "unknown",
        expires_at = expires_at,
        chat_retention_until = session_start_time + GUEST_CHAT_RETENTION,
        messages = {},
        last_activity = session_start_time,
        session_active = true
    }
    
    red:set(chat_key, cjson.encode(chat_record))
    red:expire(chat_key, GUEST_CHAT_RETENTION)  -- 3 days
    
    -- Set current chat session pointer
    red:set("current_chat_session:" .. account_data.username, session_username)
    red:expire("current_chat_session:" .. account_data.username, GUEST_SESSION_DURATION)
    
    -- Add to admin tracking list (for dashboard)
    local admin_key = "admin:guest_sessions"
    red:sadd(admin_key, session_username)  -- Add to set of guest sessions
    red:expire(admin_key, GUEST_CHAT_RETENTION)
    
    -- Set JWT cookie (contains real username: guest_slot_1/guest_slot_2)
    ngx.header["Set-Cookie"] = "access_token=" .. account_data.token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    ngx.log(ngx.INFO, "=== GUEST SESSION CREATION SUCCESS ===")
    ngx.log(ngx.INFO, "Created session: " .. session_username .. " -> " .. account_data.username .. " [Slot " .. account_data.slot_number .. "]")
    ngx.log(ngx.INFO, "From IP: " .. (ngx.var.remote_addr or "unknown"))
    
    return {
        success = true,
        username = session_username,  -- Return display name (QuickFox123) to frontend
        internal_username = account_data.username,  -- For debugging
        session_id = session_username,
        token = account_data.token,
        expires_at = expires_at,
        message_limit = GUEST_MESSAGE_LIMIT,
        session_duration = GUEST_SESSION_DURATION,
        priority = 3,
        slot_number = account_data.slot_number,
        storage_type = "redis",
        chat_retention_days = math.floor(GUEST_CHAT_RETENTION / 86400)
    }, nil
end

-- Cleanup guest session (but keep chat history and username blacklist)
local function cleanup_guest_session(slot_number)
    local red = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    -- Get session data to mark chat history as ended
    local session_key = "guest_active_session:" .. slot_number
    local session_data = redis_to_lua(red:get(session_key))
    
    if session_data then
        local ok, session = pcall(cjson.decode, session_data)
        if ok and session.session_id then
            -- Mark chat history as session ended
            local chat_key = "chat_history:guest:" .. session.session_id
            local chat_data = redis_to_lua(red:get(chat_key))
            if chat_data then
                local ok_chat, chat_history = pcall(cjson.decode, chat_data)
                if ok_chat then
                    chat_history.session_active = false
                    chat_history.ended_at = ngx.time()
                    chat_history.ended_reason = "session_expired"
                    red:set(chat_key, cjson.encode(chat_history))
                    red:expire(chat_key, GUEST_CHAT_RETENTION)
                end
            end
            
            ngx.log(ngx.INFO, "Marked chat history as ended for session: " .. session.session_id)
        end
    end
    
    -- Remove active session but keep chat history and blacklist
    red:del("guest_active_session:" .. slot_number)
    red:del("guest_session:guest_slot_" .. slot_number)
    red:del("current_chat_session:guest_slot_" .. slot_number)
    
    ngx.log(ngx.INFO, "Cleaned up guest session for slot " .. slot_number .. " (chat history and username blacklist preserved)")
    return true, "Session cleaned"
end

-- Validate guest session (now checks for valid hardcoded JWT)
local function validate_guest_session(token)
    if not token then
        return nil, "No token provided"
    end
    
    -- First check if this is one of our hardcoded guest JWTs
    local valid_guest_account = nil
    for _, account in ipairs(GUEST_ACCOUNTS) do
        if account.token == token then
            valid_guest_account = account
            break
        end
    end
    
    if not valid_guest_account then
        return nil, "Invalid guest token"
    end
    
    -- Verify JWT structure (double-check)
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        return nil, "JWT verification failed"
    end
    
    local payload = jwt_obj.payload
    if payload.username ~= valid_guest_account.username or payload.user_type ~= "guest" then
        return nil, "JWT payload mismatch"
    end
    
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    -- Check active session
    local session_key = "guest_session:" .. valid_guest_account.username
    local session_data = redis_to_lua(red:get(session_key))
    
    if not session_data then
        return nil, "No active session for this guest account"
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

-- Get guest chat history (for current session)
local function get_guest_chat_history(username)
    local red = connect_redis()
    if not red then
        return nil, "Redis unavailable"
    end
    
    -- Get current session ID (which is the display username)
    local session_username = redis_to_lua(red:get("current_chat_session:" .. username))
    if not session_username then
        return [], nil  -- No current session, return empty
    end
    
    -- Get chat history using session_username as key
    local chat_key = "chat_history:guest:" .. session_username
    local chat_data = redis_to_lua(red:get(chat_key))
    
    if not chat_data then
        return [], nil  -- No chat history yet
    end
    
    local ok, chat_history = pcall(cjson.decode, chat_data)
    if not ok then
        return [], "Invalid chat data"
    end
    
    return chat_history.messages or [], nil
end

-- Save guest chat message
local function save_guest_chat_message(username, message_data)
    local red = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    -- Get current session ID (display username)
    local session_username = redis_to_lua(red:get("current_chat_session:" .. username))
    if not session_username then
        return false, "No active session"
    end
    
    -- Get existing chat history
    local chat_key = "chat_history:guest:" .. session_username
    local chat_data = redis_to_lua(red:get(chat_key))
    
    local chat_history = {}
    if chat_data then
        local ok, existing = pcall(cjson.decode, chat_data)
        if ok then
            chat_history = existing
        end
    end
    
    -- Add new message
    if not chat_history.messages then
        chat_history.messages = {}
    end
    
    table.insert(chat_history.messages, {
        timestamp = ngx.time(),
        iso_timestamp = os.date("!%Y-%m-%dT%TZ"),
        type = message_data.type or "user",
        content = message_data.content,
        message_id = message_data.message_id or ("msg_" .. ngx.time() .. "_" .. math.random(1000, 9999)),
        from_display_name = session_username,  -- For admin tracking
        from_internal_user = username,         -- guest_slot_1/guest_slot_2
        ip_address = ngx.var.remote_addr or "unknown"
    })
    
    chat_history.last_activity = ngx.time()
    
    -- Save updated history
    red:set(chat_key, cjson.encode(chat_history))
    red:expire(chat_key, GUEST_CHAT_RETENTION)  -- Extend retention
    
    return true, nil
end

-- Admin function: Get all guest chat sessions
local function get_all_guest_sessions_for_admin()
    local red = connect_redis()
    if not red then
        return nil, "Redis unavailable"
    end
    
    local admin_key = "admin:guest_sessions"
    local session_usernames = redis_to_lua(red:smembers(admin_key)) or {}
    
    local sessions = {}
    for _, session_username in ipairs(session_usernames) do
        local chat_key = "chat_history:guest:" .. session_username
        local chat_data = redis_to_lua(red:get(chat_key))
        
        if chat_data then
            local ok, session_info = pcall(cjson.decode, chat_data)
            if ok then
                -- Add summary info for admin dashboard
                session_info.message_count = #(session_info.messages or {})
                session_info.duration_minutes = math.floor((session_info.last_activity - session_info.created_at) / 60)
                session_info.is_expired = (ngx.time() > session_info.expires_at)
                session_info.days_until_deletion = math.floor((session_info.chat_retention_until - ngx.time()) / 86400)
                
                -- Check if username is still blacklisted
                local blacklist_key = "guest_username_blacklist:" .. session_username
                local is_blacklisted = redis_to_lua(red:get(blacklist_key))
                session_info.username_blacklisted = (is_blacklisted ~= nil)
                session_info.blacklist_expires_in_hours = is_blacklisted and math.floor(red:ttl(blacklist_key) / 3600) or 0
                
                table.insert(sessions, session_info)
            end
        end
    end
    
    -- Sort by created_at (newest first)
    table.sort(sessions, function(a, b) return a.created_at > b.created_at end)
    
    return sessions, nil
end

-- Admin function: Manual cleanup of expired data
local function cleanup_expired_guest_data()
    local red = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    local current_time = ngx.time()
    local cleaned_sessions = 0
    local cleaned_blacklists = 0
    
    -- Clean expired chat histories
    local admin_key = "admin:guest_sessions"
    local session_usernames = redis_to_lua(red:smembers(admin_key)) or {}
    
    for _, session_username in ipairs(session_usernames) do
        local chat_key = "chat_history:guest:" .. session_username
        local chat_data = redis_to_lua(red:get(chat_key))
        
        if chat_data then
            local ok, session_info = pcall(cjson.decode, chat_data)
            if ok and session_info.chat_retention_until and current_time > session_info.chat_retention_until then
                -- Remove expired chat history
                red:del(chat_key)
                red:srem(admin_key, session_username)
                cleaned_sessions = cleaned_sessions + 1
                
                ngx.log(ngx.INFO, "Cleaned expired guest chat history: " .. session_username)
            end
        end
    end
    
    -- Clean expired username blacklists (Redis TTL should handle this, but manual cleanup for safety)
    local blacklist_keys = redis_to_lua(red:keys("guest_username_blacklist:*")) or {}
    for _, blacklist_key in ipairs(blacklist_keys) do
        local ttl = red:ttl(blacklist_key)
        if ttl == -1 or ttl == -2 then  -- No TTL or expired
            red:del(blacklist_key)
            cleaned_blacklists = cleaned_blacklists + 1
        end
    end
    
    ngx.log(ngx.INFO, "Guest cleanup completed: " .. cleaned_sessions .. " sessions, " .. cleaned_blacklists .. " blacklists")
    return true, "Cleaned " .. cleaned_sessions .. " sessions and " .. cleaned_blacklists .. " blacklists"
end

-- Admin function: Get specific guest session details
local function get_guest_session_details_for_admin(session_username)
    local red = connect_redis()
    if not red then
        return nil, "Redis unavailable"
    end
    
    local chat_key = "chat_history:guest:" .. session_username
    local chat_data = redis_to_lua(red:get(chat_key))
    
    if not chat_data then
        return nil, "Session not found"
    end
    
    local ok, session_details = pcall(cjson.decode, chat_data)
    if not ok then
        return nil, "Invalid session data"
    end
    
    return session_details, nil
end

-- =============================================
-- API HANDLERS
-- =============================================

-- Create secure guest session
local function handle_create_guest_session()
    local ip = ngx.var.remote_addr or "unknown"
    local rate_limit_key = "guest_create_attempts:" .. ip
    local attempts = ngx.shared.guest_sessions:get(rate_limit_key) or 0
    
    ngx.log(ngx.INFO, "=== GUEST SESSION API CREATION START ===")
    ngx.log(ngx.INFO, "Request from IP: " .. ip .. ", attempts: " .. attempts)
    
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
        ngx.log(ngx.ERR, "Guest session creation failed from " .. ip .. ": " .. (error_msg or "unknown"))
        
        send_json(503, {
            error = "Guest session creation failed",
            message = error_msg or "All guest slots are currently occupied",
            available_soon = true,
            suggestion = "Try again in a few minutes or register for guaranteed access",
            max_guests = MAX_GUEST_SESSIONS,
            slots_full = true,
            debug_error = error_msg
        })
    end
    
    ngx.shared.guest_sessions:delete(rate_limit_key)
    ngx.log(ngx.INFO, "=== GUEST SESSION API CREATION SUCCESS ===")
    
    send_json(200, {
        success = true,
        message = "Guest session created successfully",
        session = {
            username = session_data.username,  -- Display name (QuickFox123)
            session_id = session_data.session_id,
            slot_number = session_data.slot_number,
            message_limit = session_data.message_limit,
            session_duration_minutes = math.floor(session_data.session_duration / 60),
            expires_at = session_data.expires_at,
            priority = session_data.priority,
            storage_type = session_data.storage_type,
            chat_retention_days = session_data.chat_retention_days
        },
        instructions = {
            "You have " .. session_data.message_limit .. " messages available",
            "Session expires in " .. math.floor(session_data.session_duration / 60) .. " minutes", 
            "Chat history is saved for " .. session_data.chat_retention_days .. " days for admin review",
            "Your messages are processed with priority " .. session_data.priority .. " (lowest)"
        },
        security = {
            hardcoded_jwt_slots = true,
            anti_hijacking = true,
            slot_locked = true,
            chat_retention_enabled = true
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
            username = user_data.display_username or user_data.session_id,
            session_id = user_data.session_id,
            internal_username = user_data.username,
            slot_number = user_data.slot_number,
            max_messages = user_data.max_messages,
            used_messages = user_data.message_count,
            remaining_messages = user_data.max_messages - user_data.message_count,
            session_remaining_seconds = user_data.expires_at - ngx.time(),
            session_remaining_minutes = math.floor((user_data.expires_at - ngx.time()) / 60),
            priority = user_data.priority,
            storage_type = user_data.chat_storage,
            created_at = user_data.created_at,
            created_ip = user_data.created_ip
        },
        status = {
            can_chat = (user_data.max_messages - user_data.message_count) > 0,
            session_active = user_data.expires_at > ngx.time(),
            slot_secured = true,
            chat_persistent = true
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
            chat_retention_days = math.floor(GUEST_CHAT_RETENTION / 86400),
            hardcoded_jwt_slots = true,
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
        -- Mark session as ended in chat history
        if user_data.session_id then
            local red = connect_redis()
            if red then
                local chat_key = "chat_history:guest:" .. user_data.session_id
                local chat_data = redis_to_lua(red:get(chat_key))
                if chat_data then
                    local ok, chat_history = pcall(cjson.decode, chat_data)
                    if ok then
                        chat_history.session_active = false
                        chat_history.ended_at = ngx.time()
                        chat_history.ended_voluntarily = true
                        red:set(chat_key, cjson.encode(chat_history))
                        red:expire(chat_key, GUEST_CHAT_RETENTION)
                    end
                end
            end
        end
        
        cleanup_guest_session(user_data.slot_number)
        
        -- Clear cookies
        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        
        ngx.log(ngx.INFO, "Guest session ended voluntarily: " .. (user_data.session_id or "unknown") .. " [Slot " .. user_data.slot_number .. "]")
        
        send_json(200, {
            success = true,
            message = "Guest session ended successfully",
            slot_freed = true,
            slot_number = user_data.slot_number,
            session_id = user_data.session_id,
            chat_preserved = true,
            preservation_days = math.floor(GUEST_CHAT_RETENTION / 86400)
        })
    else
        send_json(404, {
            error = "Session not found",
            message = "No active guest session to end"
        })
    end
end

-- Chat API handler for guests
local function handle_chat_api()
    local cjson = require "cjson"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "Guest chat API: " .. method .. " " .. uri .. " by " .. (user_data and user_data.session_id or username or "unknown"))
    
    if uri == "/api/chat/history" and method == "GET" then
        local messages, err = get_guest_chat_history(username)
        if err then
            send_json(500, { error = "Failed to get chat history", message = err })
        end
        
        send_json(200, {
            success = true,
            messages = messages,
            user_type = "guest",
            storage_type = "redis",
            session_id = user_data and user_data.session_id or "unknown",
            message = "Guest chat history (persistent for " .. math.floor(GUEST_CHAT_RETENTION / 86400) .. " days)"
        })
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        send_json(200, { 
            success = true, 
            message = "Guest users cannot clear chat history (admin function only)" 
        })
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        send_json(501, { 
            error = "Guest streaming chat not implemented yet",
            message = "Guest streaming chat coming soon"
        })
        
    else
        send_json(404, { 
            error = "Guest chat API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "GET /api/chat/history - Get persistent chat history",
                "POST /api/chat/clear - Clear history (admin only)",
                "POST /api/chat/stream - Stream chat messages (coming soon)"
            }
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
    handle_chat_api = handle_chat_api,
    
    -- Core functions (for other modules to use)
    create_secure_guest_session = create_secure_guest_session,
    validate_guest_session = validate_guest_session,
    get_guest_stats = get_guest_stats,
    cleanup_guest_session = cleanup_guest_session,
    
    -- Chat functions
    get_guest_chat_history = get_guest_chat_history,
    save_guest_chat_message = save_guest_chat_message,
    
    -- Admin functions
    get_all_guest_sessions_for_admin = get_all_guest_sessions_for_admin,
    get_guest_session_details_for_admin = get_guest_session_details_for_admin,
    cleanup_expired_guest_data = cleanup_expired_guest_data,
    
    -- Username generation (for testing)
    generate_display_username = generate_display_username
}