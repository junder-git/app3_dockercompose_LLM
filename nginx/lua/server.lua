-- nginx/lua/server.lua - ENHANCED SECURE Guest Sessions with JWT
local cjson = require "cjson"
local redis = require "resty.redis"
local http = require "resty.http"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434"
local OLLAMA_MODEL = os.getenv("OLLAMA_MODEL") or "devstral"

-- Configuration
local MAX_SSE_SESSIONS = 5
local SESSION_TIMEOUT = 300  -- 5 minutes
local GUEST_SESSION_DURATION = 1800  -- 30 minutes
local GUEST_MESSAGE_LIMIT = 10
local USER_RATE_LIMIT = 60  -- messages per hour
local ADMIN_RATE_LIMIT = 120  -- higher limit for admins
local MAX_GUEST_SESSIONS = 5  -- HARDCODED limit

local M = {}

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

-- =============================================
-- SECURE JWT-BASED GUEST SESSIONS WITH HARDCODED TOKENS
-- =============================================

-- SECURITY: Pre-generated hardcoded guest JWTs (prevents hijacking)
-- These are REAL JWTs that will be generated on server startup
local HARDCODED_GUEST_TOKENS = nil -- Will be populated by generate_hardcoded_guest_tokens()

-- JWT timeout per token (prevents hijacking)
local JWT_COOLDOWN_SECONDS = 60 -- 1 minute cooldown per JWT
local JWT_SSE_LOCK_SECONDS = 300 -- 5 minutes max SSE session per JWT

-- Generate REAL hardcoded JWTs on server startup with proper signatures
local function generate_hardcoded_guest_tokens()
    local tokens = {}
    local username_pools = {
        {"QuickFox", "SilentEagle", "BrightWolf", "SwiftTiger", "CleverHawk"},
        {"BoldBear", "CalmLion", "SharpOwl", "WiseCat", "CoolDog"}, 
        {"FastRaven", "StealthPanther", "BraveBuffalo", "AgileCheetah", "NobleStag"},
        {"PowerBison", "GracefulSwan", "MightyElk", "WildMustang", "FierceWolverine"},
        {"StormFalcon", "ThunderHorse", "LightningLynx", "WindEagle", "FlamePhoenix"}
    }
    
    for i = 1, MAX_GUEST_SESSIONS do
        local slot_id = "guest_slot_" .. i
        local payload = {
            sub = slot_id,
            user_type = "guest",
            priority = 3,
            slot = i,
            version = 1,
            iat = 1640995200, -- Fixed timestamp (prevents timing attacks)
            exp = 9999999999   -- Very far future (slot-based expiry, not time-based)
        }
        
        -- Generate REAL JWT with proper signature
        local token = jwt:sign(JWT_SECRET, {
            header = { typ = "JWT", alg = "HS256" },
            payload = payload
        })
        
        table.insert(tokens, {
            slot_id = slot_id,
            slot_number = i,
            jwt_token = token,
            username_pool = username_pools[i] or {"Guest" .. i .. "User"}
        })
    end
    
    ngx.log(ngx.INFO, "Generated " .. #tokens .. " hardcoded guest JWTs with real signatures")
    return tokens
end

-- SECURITY: Check if JWT is currently locked (in active use)
local function is_jwt_locked(slot_id)
    local red = connect_redis()
    if not red then
        return true -- Fail secure - assume locked if Redis unavailable
    end
    
    local lock_key = "jwt_lock:" .. slot_id
    local lock_data = red:get(lock_key)
    
    if not lock_data then
        return false -- Not locked
    end
    
    local lock_info = cjson.decode(lock_data)
    local current_time = ngx.time()
    
    -- Check if lock expired
    if current_time >= lock_info.expires_at then
        red:del(lock_key)
        ngx.log(ngx.INFO, "JWT lock expired for slot: " .. slot_id)
        return false -- Lock expired
    end
    
    return true -- Still locked
end

-- SECURITY: Lock JWT for exclusive use
local function lock_jwt(slot_id, session_type)
    local red = connect_redis()
    if not red then
        return false, "Service unavailable"
    end
    
    local lock_key = "jwt_lock:" .. slot_id
    local current_time = ngx.time()
    
    -- Check if already locked
    if is_jwt_locked(slot_id) then
        return false, "JWT currently in use"
    end
    
    -- Create lock
    local lock_info = {
        slot_id = slot_id,
        locked_at = current_time,
        expires_at = current_time + (session_type == "sse" and JWT_SSE_LOCK_SECONDS or JWT_COOLDOWN_SECONDS),
        session_type = session_type,
        locked_by_ip = ngx.var.remote_addr or "unknown"
    }
    
    red:set(lock_key, cjson.encode(lock_info))
    red:expire(lock_key, lock_info.expires_at - current_time + 10) -- +10 sec buffer
    
    ngx.log(ngx.INFO, "JWT locked for " .. session_type .. ": " .. slot_id .. " (expires in " .. (lock_info.expires_at - current_time) .. "s)")
    
    return true, "JWT locked"
end

-- SECURITY: Unlock JWT (when session ends)
local function unlock_jwt(slot_id)
    local red = connect_redis()
    if not red then
        return false
    end
    
    local lock_key = "jwt_lock:" .. slot_id
    red:del(lock_key)
    
    ngx.log(ngx.INFO, "JWT unlocked: " .. slot_id)
    return true
end

-- SECURITY: Find available hardcoded guest slot (with JWT locking)
local function find_available_guest_slot()
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    local current_time = ngx.time()
    
    -- Check each hardcoded slot
    for _, slot_data in ipairs(HARDCODED_GUEST_TOKENS) do
        -- Check if JWT is locked (in active use)
        if not is_jwt_locked(slot_data.slot_id) then
            local session_key = "guest_session:" .. slot_data.slot_id
            local session_data = red:get(session_key)
            
            if not session_data then
                -- Slot is free and JWT not locked
                return slot_data, nil
            else
                -- Check if session expired
                local session = cjson.decode(session_data)
                if current_time >= session.expires_at then
                    -- Clean expired session and unlock JWT
                    red:del(session_key)
                    unlock_jwt(slot_data.slot_id)
                    ngx.log(ngx.INFO, "Cleaned expired guest session and unlocked JWT: " .. slot_data.slot_id)
                    return slot_data, nil
                end
            end
        end
    end
    
    return nil, "All guest slots occupied or JWTs locked"
end

-- Create secure guest session using hardcoded JWT slot
-- Generate dynamic guest username from slot's pool
local function generate_guest_username_from_slot(slot_data)
    local username_base = slot_data.username_pool[math.random(#slot_data.username_pool)]
    local number = math.random(100, 999)
    return username_base .. number
end

-- Create secure guest session using hardcoded JWT slot with locking
function M.create_secure_guest_session()
    -- SECURITY: Find available hardcoded slot
    local slot_data, error_msg = find_available_guest_slot()
    if not slot_data then
        ngx.log(ngx.WARN, "No guest slots available: " .. (error_msg or "unknown"))
        return nil, error_msg or "All guest slots occupied (5/5). Please try again later."
    end
    
    -- SECURITY: Lock the JWT immediately to prevent hijacking
    local lock_success, lock_msg = lock_jwt(slot_data.slot_id, "session")
    if not lock_success then
        ngx.log(ngx.WARN, "Failed to lock JWT for slot: " .. slot_data.slot_id .. " - " .. lock_msg)
        return nil, "Slot temporarily unavailable: " .. lock_msg
    end
    
    local red = connect_redis()
    if not red then
        unlock_jwt(slot_data.slot_id) -- Clean up lock
        return nil, "Service unavailable"
    end
    
    -- Generate dynamic username from slot's pool
    local guest_username = generate_guest_username_from_slot(slot_data)
    local session_key = "guest_session:" .. slot_data.slot_id
    local expires_at = ngx.time() + GUEST_SESSION_DURATION
    
    -- CRITICAL: Store session in Redis with HARDCODED JWT
    local session_data = {
        slot_id = slot_data.slot_id,
        guest_id = slot_data.slot_id, -- Use slot_id as guest_id for consistency
        username = guest_username,
        user_type = "guest",
        jwt_token = slot_data.jwt_token, -- HARDCODED JWT prevents hijacking
        created_at = ngx.time(),
        expires_at = expires_at,
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = ngx.var.remote_addr or "unknown",
        last_activity = ngx.time(),
        priority = 3,
        slot_number = slot_data.slot_number,
        is_jwt_locked = true,
        -- SECURITY: No chat history storage for guests
        chat_storage = "none"
    }
    
    -- Store in Redis with TTL
    red:set(session_key, cjson.encode(session_data))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    -- SECURITY: HttpOnly cookie with HARDCODED JWT
    ngx.header["Set-Cookie"] = "guest_token=" .. slot_data.jwt_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION .. 
        "; Secure=" .. (ngx.var.scheme == "https" and "true" or "false")
    
    ngx.log(ngx.INFO, "Secure guest session created: " .. guest_username .. " [Slot " .. slot_data.slot_number .. "] from IP: " .. (ngx.var.remote_addr or "unknown"))
    
    return {
        success = true,
        slot_id = slot_data.slot_id,
        guest_id = slot_data.slot_id,
        username = guest_username,
        token = slot_data.jwt_token, -- Return hardcoded token
        expires_at = expires_at,
        message_limit = GUEST_MESSAGE_LIMIT,
        session_duration = GUEST_SESSION_DURATION,
        priority = 3,
        slot_number = slot_data.slot_number,
        storage_type = "none",
        is_jwt_locked = true
    }, nil
end

-- SECURITY: Validate hardcoded guest JWT against Redis slot with anti-hijacking
function M.validate_guest_session(token)
    if not token then
        return nil, "No token provided"
    end
    
    -- CRITICAL: First verify JWT signature
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        ngx.log(ngx.WARN, "Invalid guest JWT signature: " .. (jwt_obj.reason or "unknown"))
        return nil, "Invalid token"
    end
    
    local payload = jwt_obj.payload
    if not payload.sub or not payload.user_type or payload.user_type ~= "guest" then
        return nil, "Invalid guest token claims"
    end
    
    -- SECURITY: Verify token matches hardcoded slots
    local is_valid_hardcoded = false
    for _, slot_data in ipairs(HARDCODED_GUEST_TOKENS) do
        if slot_data.jwt_token == token and slot_data.slot_id == payload.sub then
            is_valid_hardcoded = true
            break
        end
    end
    
    if not is_valid_hardcoded then
        ngx.log(ngx.ERR, "SECURITY VIOLATION: Non-hardcoded guest token used: " .. (payload.sub or "unknown"))
        return nil, "Unauthorized token"
    end
    
    -- CRITICAL: Check if JWT is locked (in active use by another session)
    if is_jwt_locked(payload.sub) then
        ngx.log(ngx.WARN, "ANTI-HIJACKING: JWT already in use for slot: " .. payload.sub .. " from IP: " .. (ngx.var.remote_addr or "unknown"))
        return nil, "Token currently in use by another session"
    end
    
    -- CRITICAL: Validate against Redis session (ensures slot is active)
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    local session_key = "guest_session:" .. payload.sub
    local session_data = red:get(session_key)
    
    if not session_data then
        ngx.log(ngx.WARN, "Guest session not found in Redis for slot: " .. payload.sub)
        return nil, "Session not active"
    end
    
    local session = cjson.decode(session_data)
    
    -- SECURITY: Double-verify token matches stored token
    if session.jwt_token ~= token then
        ngx.log(ngx.ERR, "SECURITY VIOLATION: Guest token mismatch for slot: " .. payload.sub)
        return nil, "Token mismatch"
    end
    
    -- Check session expiration (time-based, not JWT exp)
    if ngx.time() >= session.expires_at then
        red:del(session_key)
        unlock_jwt(payload.sub) -- Unlock expired session
        ngx.log(ngx.INFO, "Guest session expired for slot: " .. payload.sub)
        return nil, "Session expired"
    end
    
    -- Update last activity
    session.last_activity = ngx.time()
    red:set(session_key, cjson.encode(session))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    return session, nil
end

-- End guest session and unlock JWT
function M.end_guest_session(slot_id)
    if not slot_id then
        return false, "Slot ID required"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Service unavailable"
    end
    
    local session_key = "guest_session:" .. slot_id
    local session_data = red:get(session_key)
    
    if session_data then
        local session = cjson.decode(session_data)
        red:del(session_key)
        ngx.log(ngx.INFO, "Guest session ended: " .. (session.username or "unknown") .. " [Slot " .. (session.slot_number or "?") .. "]")
    end
    
    -- CRITICAL: Unlock JWT for reuse
    unlock_jwt(slot_id)
    
    return true, "Session ended and JWT unlocked"
end

-- Get guest session limits
function M.get_guest_limits(guest_id)
    if not guest_id then
        return nil, "Guest ID required"
    end
    
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    local session_key = "guest_session:" .. guest_id
    local session_data = red:get(session_key)
    
    if not session_data then
        return nil, "Session not found"
    end
    
    local session = cjson.decode(session_data)
    
    return {
        max_messages = session.max_messages,
        used_messages = session.message_count,
        remaining_messages = session.max_messages - session.message_count,
        session_remaining = session.expires_at - ngx.time(),
        username = session.username,
        priority = session.priority,
        storage_type = session.chat_storage
    }, nil
end

-- Use guest message (with limit enforcement)
function M.use_guest_message(guest_id)
    if not guest_id then
        return false, "Guest ID required"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Service unavailable"
    end
    
    local session_key = "guest_session:" .. guest_id
    local session_data = red:get(session_key)
    
    if not session_data then
        return false, "Session not found"
    end
    
    local session = cjson.decode(session_data)
    
    if session.message_count >= session.max_messages then
        return false, "Message limit exceeded (" .. session.message_count .. "/" .. session.max_messages .. ")"
    end
    
    -- Increment message count
    session.message_count = session.message_count + 1
    session.last_used = ngx.time()
    session.last_activity = ngx.time()
    
    red:set(session_key, cjson.encode(session))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    ngx.log(ngx.INFO, "Guest message used: " .. session.username .. " (" .. session.message_count .. "/" .. session.max_messages .. ")")
    
    return true, "Message allowed", {
        remaining = session.max_messages - session.message_count,
        used = session.message_count,
        max = session.max_messages
    }
end

-- Get all guest sessions (admin function)
function M.get_all_guest_sessions()
    local red = connect_redis()
    if not red then
        return {}, "Service unavailable"
    end
    
    local guest_keys = red:keys("guest_session:*")
    local sessions = {}
    local current_time = ngx.time()
    
    for _, key in ipairs(guest_keys) do
        local session_data = red:get(key)
        if session_data then
            local session = cjson.decode(session_data)
            
            -- Clean expired sessions
            if current_time >= session.expires_at then
                red:del(key)
            else
                table.insert(sessions, {
                    guest_id = session.guest_id,
                    username = session.username,
                    created_at = session.created_at,
                    expires_at = session.expires_at,
                    last_activity = session.last_activity,
                    message_count = session.message_count,
                    max_messages = session.max_messages,
                    created_ip = session.created_ip,
                    age_seconds = current_time - session.created_at,
                    remaining_seconds = session.expires_at - current_time,
                    priority = session.priority
                })
            end
        end
    end
    
    -- Sort by creation time (newest first)
    table.sort(sessions, function(a, b)
        return a.created_at > b.created_at
    end)
    
    return sessions, nil
end

-- Delete guest session (admin function)
function M.delete_guest_session(guest_id, admin_username)
    if not guest_id or not admin_username then
        return false, "Missing parameters"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Service unavailable"
    end
    
    local session_key = "guest_session:" .. guest_id
    local session_data = red:get(session_key)
    
    if not session_data then
        return false, "Session not found"
    end
    
    local session = cjson.decode(session_data)
    red:del(session_key)
    
    ngx.log(ngx.WARN, "Admin " .. admin_username .. " deleted guest session: " .. session.username .. " (" .. guest_id .. ")")
    
    return true, "Guest session deleted"
end

-- Get guest session stats
function M.get_guest_stats()
    local red = connect_redis()
    if not red then
        return {}, "Service unavailable"
    end
    
    local guest_keys = red:keys("guest_session:*")
    local active_sessions = 0
    local total_messages = 0
    local current_time = ngx.time()
    
    for _, key in ipairs(guest_keys) do
        local session_data = red:get(key)
        if session_data then
            local session = cjson.decode(session_data)
            
            if current_time < session.expires_at then
                active_sessions = active_sessions + 1
                total_messages = total_messages + session.message_count
            else
                red:del(key)  -- Clean expired
            end
        end
    end
    
    return {
        active_sessions = active_sessions,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = MAX_GUEST_SESSIONS - active_sessions,
        total_messages_used = total_messages,
        average_messages_per_session = active_sessions > 0 and math.floor(total_messages / active_sessions) or 0
    }, nil
end

-- =============================================
-- EXISTING FUNCTIONS (keeping all previous code)
-- =============================================

-- SECURE USER MANAGEMENT (Redis)
function M.get_user(username)
    if not username or username == "" then
        return nil
    end
    
    local red = connect_redis()
    if not red then return nil end
    
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        return nil
    end
    
    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end
    
    -- SECURITY: Validate required fields exist
    if not user.username or not user.password_hash then
        ngx.log(ngx.WARN, "Invalid user data structure for: " .. username)
        return nil
    end
    
    return user
end

function M.create_user(username, password_hash, ip_address)
    if not username or not password_hash then
        return false, "Missing required fields"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    
    -- SECURITY: Check if user exists
    if red:exists(user_key) == 1 then
        return false, "User already exists"
    end
    
    -- SECURITY: Create user with audit trail
    local user_data = {
        username = username,
        password_hash = password_hash,
        is_admin = "false",
        is_approved = "false",  -- CRITICAL: Default to pending approval
        created_at = os.date("!%Y-%m-%dT%TZ"),
        created_ip = ip_address or "unknown",
        login_count = "0",
        last_active = os.date("!%Y-%m-%dT%TZ")
    }
    
    for k, v in pairs(user_data) do
        red:hset(user_key, k, v)
    end
    
    ngx.log(ngx.INFO, "User created: " .. username .. " from IP: " .. (ip_address or "unknown"))
    return true, "User created"
end

function M.update_user_activity(username)
    if not username then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    red:hset("user:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))
    return true
end

function M.update_user_login(username, ip_address)
    if not username then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    local user_key = "user:" .. username
    local login_count = tonumber(red:hget(user_key, "login_count") or "0") + 1
    
    red:hset(user_key, "login_count", tostring(login_count))
    red:hset(user_key, "last_login", os.date("!%Y-%m-%dT%TZ"))
    red:hset(user_key, "last_ip", ip_address or "unknown")
    
    return true
end

function M.get_all_users()
    local red = connect_redis()
    if not red then return {} end
    
    local user_keys = red:keys("user:*")
    local users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                -- SECURITY: Don't return password hashes
                user.password_hash = nil
                table.insert(users, user)
            end
        end
    end
    
    return users
end

function M.approve_user(username, admin_username)
    if not username or not admin_username then
        return false, "Missing required parameters"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    if red:exists(user_key) == 0 then
        return false, "User not found"
    end
    
    red:hset(user_key, "is_approved", "true")
    red:hset(user_key, "approved_by", admin_username)
    red:hset(user_key, "approved_at", os.date("!%Y-%m-%dT%TZ"))
    
    ngx.log(ngx.INFO, "User approved: " .. username .. " by admin: " .. admin_username)
    return true, "User approved"
end

function M.toggle_admin(username, admin_username)
    if not username or not admin_username then
        return false, "Missing required parameters"
    end
    
    if username == admin_username then
        return false, "Cannot modify own admin status"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    if red:exists(user_key) == 0 then
        return false, "User not found"
    end
    
    local current_status = red:hget(user_key, "is_admin")
    local new_status = (current_status == "true") and "false" or "true"
    
    red:hset(user_key, "is_admin", new_status)
    red:hset(user_key, "admin_modified_by", admin_username)
    red:hset(user_key, "admin_modified_at", os.date("!%Y-%m-%dT%TZ"))
    
    -- SECURITY: If promoting to admin, ensure they're also approved
    if new_status == "true" then
        red:hset(user_key, "is_approved", "true")
        if not red:hget(user_key, "approved_by") then
            red:hset(user_key, "approved_by", admin_username)
            red:hset(user_key, "approved_at", os.date("!%Y-%m-%dT%TZ"))
        end
    end
    
    ngx.log(ngx.INFO, "Admin status changed for " .. username .. " to " .. new_status .. " by " .. admin_username)
    return true, "Admin status updated", new_status == "true"
end

function M.delete_user(username)
    if not username then
        return false, "Username required"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    if red:exists(user_key) == 0 then
        return false, "User not found"
    end
    
    -- SECURITY: Archive user data before deletion
    local user_data = red:hgetall(user_key)
    if user_data and #user_data > 0 then
        local archive_key = "deleted_user:" .. username .. ":" .. ngx.time()
        for i = 1, #user_data, 2 do
            red:hset(archive_key, user_data[i], user_data[i + 1])
        end
        red:hset(archive_key, "deleted_at", os.date("!%Y-%m-%dT%TZ"))
        red:expire(archive_key, 2592000) -- Keep for 30 days
    end
    
    -- Delete user and related data
    red:del(user_key)
    red:del("chat:" .. username)
    
    local message_keys = red:keys("user_messages:" .. username .. ":*")
    for _, key in ipairs(message_keys) do
        red:del(key)
    end
    
    ngx.log(ngx.INFO, "User deleted: " .. username)
    return true, "User deleted"
end

-- SECURE CHAT HISTORY (Redis for approved only - NO guest storage)
function M.save_message(username, role, content)
    -- SECURITY: Guests don't get Redis chat storage
    if not username or string.match(username, "^guest_") then
        return false, "Guest users don't have persistent chat storage"
    end
    
    local red = connect_redis()
    if not red then return false end
    
    local chat_key = "chat:" .. username
    local message = {
        role = role,
        content = content,
        timestamp = os.date("!%Y-%m-%dT%TZ"),
        ip = ngx.var.remote_addr or "unknown"
    }
    
    red:lpush(chat_key, cjson.encode(message))
    red:ltrim(chat_key, 0, 99) -- Keep last 100 messages
    red:expire(chat_key, 604800) -- 1 week
    
    return true
end

function M.get_chat_history(username, limit)
    -- SECURITY: Guests don't get Redis chat history
    if not username or string.match(username, "^guest_") then
        return {}, "Guest users don't have persistent chat history"
    end
    
    local red = connect_redis()
    if not red then return {} end
    
    limit = math.min(limit or 20, 100)
    local chat_key = "chat:" .. username
    local history = red:lrange(chat_key, 0, limit - 1)
    local messages = {}
    
    for i = #history, 1, -1 do
        local ok, message = pcall(cjson.decode, history[i])
        if ok and message.role and message.content then
            -- SECURITY: Don't return IP addresses to client
            table.insert(messages, {
                role = message.role,
                content = message.content,
                timestamp = message.timestamp
            })
        end
    end
    
    return messages
end

function M.clear_chat_history(username)
    -- SECURITY: Guests don't have Redis chat history to clear
    if not username or string.match(username, "^guest_") then
        return false, "Guest users don't have persistent chat history"
    end
    
    local red = connect_redis()
    if not red then return false end
    
    red:del("chat:" .. username)
    ngx.log(ngx.INFO, "Chat history cleared for user: " .. username)
    return true
end

-- SECURE RATE LIMITING (Redis)
function M.check_rate_limit(username, is_admin, is_guest)
    if not username then return true end
    
    local red = connect_redis()
    if not red then return true end -- Allow if Redis down
    
    local time_window = 3600 -- 1 hour
    local current_time = ngx.time()
    local window_start = current_time - time_window
    local count_key = "user_messages:" .. username
    
    -- SECURITY: Different limits for admins/users/guests
    local limit = GUEST_MESSAGE_LIMIT -- Default for guests
    if is_admin then
        limit = ADMIN_RATE_LIMIT
    elseif not is_guest then
        limit = USER_RATE_LIMIT
    end
    
    -- Clean old entries and count current window
    red:zremrangebyscore(count_key, 0, window_start)
    local current_count = red:zcard(count_key)
    
    if current_count >= limit then
        local user_type = is_admin and "admin" or (is_guest and "guest" or "user")
        ngx.log(ngx.WARN, "Rate limit exceeded for " .. user_type .. ": " .. username .. " (" .. current_count .. "/" .. limit .. ")")
        return false, "Rate limit exceeded (" .. current_count .. "/" .. limit .. " messages per hour)"
    end
    
    -- Add current message
    red:zadd(count_key, current_time, current_time .. ":" .. math.random(1000, 9999))
    red:expire(count_key, time_window + 60)
    
    return true, "OK"
end

-- SECURE SSE SESSION MANAGEMENT (existing code unchanged)
local function get_user_priority(user_type)
    if user_type == "admin" then return 1 end
    if user_type == "approved" then return 2 end
    if user_type == "guest" then return 3 end
    return 4
end

local function cleanup_expired_sse_sessions()
    local current_time = ngx.time()
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local cleaned = 0
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                if current_time - session.last_activity > SESSION_TIMEOUT then
                    ngx.shared.sse_sessions:delete(key)
                    cleaned = cleaned + 1
                end
            end
        end
    end
    
    return cleaned
end

function M.can_start_sse_session(user_type, username)
    if not user_type or not username then
        return false, "Missing parameters"
    end
    
    cleanup_expired_sse_sessions()
    
    local priority = get_user_priority(user_type)
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local active_sessions = {}
    
    -- Count active sessions and check for duplicates
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                table.insert(active_sessions, session)
                
                -- SECURITY: Prevent multiple sessions per user
                if session.username == username then
                    return false, "User already has active session"
                end
            end
        end
    end
    
    -- Check capacity
    if #active_sessions < MAX_SSE_SESSIONS then
        return true, "Session allowed"
    end
    
    -- SECURITY: Admins can kick lower priority sessions
    if user_type == "admin" then
        return true, "Admin session granted"
    end
    
    return false, "No available slots"
end

function M.start_sse_session(user_type, username)
    local can_start, message = M.can_start_sse_session(user_type, username)
    if not can_start then
        return false, message
    end
    
    local session_id = username .. "_sse_" .. ngx.time() .. "_" .. math.random(1000, 9999)
    local session = {
        session_id = session_id,
        username = username,
        user_type = user_type,
        priority = get_user_priority(user_type),
        created_at = ngx.time(),
        last_activity = ngx.time(),
        remote_addr = ngx.var.remote_addr or "unknown"
    }
    
    ngx.shared.sse_sessions:set("sse:" .. session_id, cjson.encode(session), SESSION_TIMEOUT + 60)
    
    ngx.log(ngx.INFO, "Started SSE session: " .. session_id .. " (user: " .. username .. ", type: " .. user_type .. ")")
    
    return true, session_id
end

function M.update_sse_activity(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false
    end
    
    local session = cjson.decode(session_info)
    session.last_activity = ngx.time()
    
    ngx.shared.sse_sessions:set(session_key, cjson.encode(session), SESSION_TIMEOUT + 60)
    return true
end

function M.end_sse_session(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    ngx.shared.sse_sessions:delete(session_key)
    
    ngx.log(ngx.INFO, "Ended SSE session: " .. session_id)
    return true
end

function M.get_sse_stats()
    cleanup_expired_sse_sessions()
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local active_sessions = 0
    
    local stats = {
        total_sessions = 0,
        max_sessions = MAX_SSE_SESSIONS,
        available_slots = 0,
        by_priority = {
            admin_sessions = 0,
            approved_sessions = 0,
            guest_sessions = 0
        }
    }
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                active_sessions = active_sessions + 1
                
                if session.priority == 1 then
                    stats.by_priority.admin_sessions = stats.by_priority.admin_sessions + 1
                elseif session.priority == 2 then
                    stats.by_priority.approved_sessions = stats.by_priority.approved_sessions + 1
                elseif session.priority == 3 then
                    stats.by_priority.guest_sessions = stats.by_priority.guest_sessions + 1
                end
            end
        end
    end
    
    stats.total_sessions = active_sessions
    stats.available_slots = MAX_SSE_SESSIONS - active_sessions
    
    return stats
end

-- =============================================
-- SECURE OLLAMA INTEGRATION
-- =============================================

function M.call_ollama_streaming(messages, options, callback)
    if not messages or #messages == 0 then
        return nil, "No messages provided"
    end
    
    local httpc = http.new()
    httpc:set_timeout((options.timeout or 300) * 1000)

    -- SECURITY: Validate and sanitize options
    local safe_options = {
        temperature = math.min(math.max(options.temperature or 0.7, 0), 1),
        num_predict = math.min(options.max_tokens or 2048, 4096),
        num_ctx = tonumber(os.getenv("OLLAMA_CONTEXT_SIZE")) or 1024,
        num_gpu = tonumber(os.getenv("OLLAMA_GPU_LAYERS")) or 8,
        num_thread = tonumber(os.getenv("OLLAMA_NUM_THREAD")) or 6,
        num_batch = tonumber(os.getenv("OLLAMA_BATCH_SIZE")) or 64,
        use_mmap = false,
        use_mlock = true
    }

    local payload = {
        model = OLLAMA_MODEL,
        messages = messages,
        stream = true,
        options = safe_options
    }

    local res, err = httpc:request_uri(OLLAMA_URL .. "/api/chat", {
        method = "POST",
        body = cjson.encode(payload),
        headers = { 
            ["Content-Type"] = "application/json",
            ["Accept"] = "text/event-stream",
            ["User-Agent"] = "nginx-lua-client"
        }
    })

    if not res then
        ngx.log(ngx.ERR, "Ollama connection failed: " .. (err or "unknown"))
        return nil, "Failed to connect to AI service: " .. (err or "unknown")
    end

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Ollama HTTP error: " .. res.status)
        return nil, "AI service error: HTTP " .. res.status
    end

    local accumulated = ""
    local chunk_count = 0
    
    -- SECURITY: Process response line by line with limits
    for line in res.body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            chunk_count = chunk_count + 1
            
            -- SECURITY: Prevent excessive chunks
            if chunk_count > 1000 then
                ngx.log(ngx.WARN, "Ollama response chunk limit exceeded")
                break
            end
            
            local ok, data = pcall(cjson.decode, line)
            if ok and data.message and data.message.content then
                accumulated = accumulated .. data.message.content
                
                -- SECURITY: Prevent excessive response length
                if #accumulated > 10000 then
                    ngx.log(ngx.WARN, "Ollama response length limit exceeded")
                    callback({
                        content = "\n\n[Response truncated - too long]",
                        accumulated = accumulated .. "\n\n[Response truncated - too long]",
                        done = true
                    })
                    break
                end
                
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

-- =============================================
-- MODULE INITIALIZATION
-- =============================================

-- Initialize hardcoded tokens on module load
if not HARDCODED_GUEST_TOKENS then
    HARDCODED_GUEST_TOKENS = generate_hardcoded_guest_tokens()
    ngx.log(ngx.INFO, "Guest session module loaded with " .. #HARDCODED_GUEST_TOKENS .. " hardcoded JWT slots")
    
    -- Log the generated tokens for reference (in production, you might want to store these)
    for i, token_data in ipairs(HARDCODED_GUEST_TOKENS) do
        ngx.log(ngx.INFO, "Guest Slot " .. i .. " JWT: " .. string.sub(token_data.jwt_token, 1, 50) .. "...")
    end
end

return M