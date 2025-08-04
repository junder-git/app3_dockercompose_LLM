-- =============================================================================
-- nginx/lua/is_guest.lua - UPDATED TO USE EXISTING HARDCODED GUEST_USER_1 ACCOUNT
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local auth = require "manage_auth"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local M = {}

-- Helper function to send JSON response and exit
local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- GUEST NAME GENERATION FOR DISPLAY
-- =============================================

local ADJECTIVES = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural", "Cosmic"}
local ANIMALS = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}

local function generate_guest_display_name()
    local adjective = ADJECTIVES[math.random(#ADJECTIVES)]
    local animal = ANIMALS[math.random(#ANIMALS)]
    local number = math.random(100, 999)
    return adjective .. animal .. number
end

-- =============================================
-- SESSION COLLISION DETECTION (USING REDIS SESSIONS)
-- =============================================

local function check_session_availability()
    local session_manager = require "manage_redis_sessions"
    
    -- Check for any active high-priority users (admin/approved)
    local active_user, err = session_manager.get_active_user()
    if err then
        return false, "Session check failed: " .. err
    end
    
    if active_user then
        local blocking_type = active_user.user_type
        local blocking_username = active_user.username
        
        -- If there's an active admin or approved user, deny guest session
        if blocking_type == "is_admin" or blocking_type == "is_approved" then
            return false, string.format("%s '%s' is currently active", 
                blocking_type == "is_admin" and "Administrator" or "Approved User", 
                blocking_username)
        end
        
        -- If there's an active guest, check activity to prevent collision
        if blocking_type == "is_guest" then
            local last_activity = tonumber(active_user.last_activity) or 0
            local current_time = ngx.time()
            local session_age = current_time - last_activity
            
            -- If guest session is recently active (within 60 seconds), block
            if session_age <= 60 then
                return false, string.format("Another guest user is currently active (last seen %d seconds ago)", session_age)
            end
            
            ngx.log(ngx.INFO, string.format("♻️ Guest session available - previous guest inactive for %ds", session_age))
        end
    end
    
    return true, "Session available"
end

-- =============================================
-- ACTIVATE EXISTING GUEST_USER_1 ACCOUNT WITH REDIS SESSIONS
-- =============================================

function M.handle_create_session()
    ngx.log(ngx.INFO, "✅ is_guest: Activating hardcoded guest_user_1 account")
    
    -- Step 1: Check session availability using Redis session manager
    local session_manager = require "manage_redis_sessions"
    local active_user, err = session_manager.get_active_user()
    
    -- "No active user" is actually GOOD - it means session is available!
    if err and err ~= "No active user" then
        ngx.log(ngx.ERR, "Session check failed: " .. err)
        send_json(500, {
            success = false,
            error = "Session check failed",
            message = err
        })
    end
    
    -- Step 2: Check for blocking sessions (only if there IS an active user)
    if active_user then
        local blocking_type = active_user.user_type
        local blocking_username = active_user.username
        local last_activity = tonumber(active_user.last_activity) or 0
        local current_time = ngx.time()
        local session_age = current_time - last_activity
        
        ngx.log(ngx.INFO, string.format("🔍 Found active user: %s '%s' (age: %ds)", blocking_type, blocking_username, session_age))
        
        -- If there's an active admin or approved user, deny guest session
        if blocking_type == "is_admin" or blocking_type == "is_approved" then
            ngx.log(ngx.INFO, string.format("❌ Guest session blocked by %s '%s'", blocking_type, blocking_username))
            send_json(409, {
                success = false,
                error = "Sessions are currently full",
                message = string.format("%s '%s' is currently active", 
                    blocking_type == "is_admin" and "Administrator" or "Approved User", 
                    blocking_username),
                reason = "high_priority_user_active"
            })
        end
        
        -- If there's an active guest, check if it's recently active
        if blocking_type == "is_guest" and session_age <= 60 then
            ngx.log(ngx.INFO, string.format("❌ Guest session blocked - another guest active %ds ago", session_age))
            send_json(409, {
                success = false,
                error = "Guest session already active",
                message = string.format("Another guest user is currently active (last seen %d seconds ago)", session_age),
                reason = "guest_recently_active"
            })
        end
        
        ngx.log(ngx.INFO, string.format("♻️ Can reuse session - previous user inactive for %ds", session_age))
    else
        ngx.log(ngx.INFO, "✅ No active sessions - guest session can be created")
    end
    
    -- Step 3: Generate display name and prepare session data
    local display_name = generate_guest_display_name()
    local guest_username = "guest_user_1"  -- Use the hardcoded account
    local now = ngx.time()
    
    -- Step 4: Use Redis session manager to activate the session (this handles priority and kicking)
    local session_success, session_result = session_manager.set_user_active(guest_username, "is_guest")
    if not session_success then
        ngx.log(ngx.WARN, "Session activation failed: " .. (session_result or "unknown"))
        send_json(409, {
            success = false,
            error = "Session activation failed",
            message = session_result or "Could not activate guest session"
        })
    end
    
    ngx.log(ngx.INFO, "✅ Session activated successfully via session manager")
    
    -- Step 5: Update the guest user record with session-specific data
    local red = auth.connect_redis()
    if not red then
        send_json(500, {
            success = false,
            error = "Database connection failed"
        })
    end
    
    local user_key = "username:" .. guest_username
    
    -- Update session-specific fields (the session manager already set is_active and last_activity)
    local ok, err = red:hmset(user_key,
        "display_name", display_name,
        "session_start", now,
        "created_ip", ngx.var.remote_addr or "unknown",
        "session_id", tostring(now) .. "_" .. math.random(1000, 9999)
    )
    
    if not ok then
        red:close()
        send_json(500, {
            success = false,
            error = "Failed to update guest session: " .. tostring(err)
        })
    end
    
    red:close()
    
    -- Step 6: Create JWT token for the existing account
    local payload = {
        username = guest_username,
        user_type = "is_guest",
        display_name = display_name,
        session_start = now,
        iat = now,
        exp = now + 3600  -- 1 hour expiration
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    -- Set cookie and return success response
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600"
    
    ngx.log(ngx.INFO, "🍪 Setting guest cookie: access_token=" .. string.sub(token, 1, 50) .. "... (length: " .. string.len(token) .. ")")
    ngx.log(ngx.INFO, "✅ Guest session activated using hardcoded account: " .. display_name .. " -> " .. guest_username)
    
    send_json(200, {
        success = true,
        message = "Guest session activated successfully",
        username = display_name,
        internal_username = guest_username,
        user_type = "is_guest",
        cookie_set = true,
        session_expires_in = 3600,
        action_taken = "activated_existing_account",
        session_info = {
            display_name = display_name,
            expires_at = os.date("!%Y-%m-%dT%H:%M:%SZ", now + 3600),
            features = {
                chat_access = true,
                message_limit = "none_during_session",
                history_storage = "temporary",
                export_available = false
            }
        }
    })
end

-- =============================================
-- GUEST SESSION VALIDATION (USING EXISTING ACCOUNT)
-- =============================================

function M.validate_guest_session(username)
    if username ~= "guest_user_1" then
        return false, "Invalid guest username - only guest_user_1 supported"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        red:close()
        return false, "Guest account not found"
    end
    
    -- Parse session data
    local session = {}
    for i = 1, #user_data, 2 do
        local field = user_data[i]
        local value = user_data[i + 1]
        if value == ngx.null then value = nil end
        session[field] = value
    end
    
    red:close()
    
    -- Validate session
    if session.user_type ~= "is_guest" then
        return false, "Invalid user type for guest session"
    end
    
    if session.is_active ~= "true" then
        return false, "Guest session is not active"
    end
    
    local current_time = ngx.time()
    local last_activity = tonumber(session.last_activity) or 0
    local session_age = current_time - last_activity
    
    if session_age > 3600 then  -- 1 hour
        return false, "Guest session has expired"
    end
    
    return true, session
end

-- =============================================
-- CLEANUP FUNCTIONS (FOR EXISTING ACCOUNT)
-- =============================================

function M.cleanup_guest_session()
    local guest_username = "guest_user_1"
    
    -- Use Redis session manager to properly clear session
    local session_manager = require "manage_redis_sessions"
    local success, message = session_manager.clear_user_session(guest_username)
    
    if success then
        -- Also clear session-specific fields from the user record
        local red = auth.connect_redis()
        if red then
            local user_key = "username:" .. guest_username
            red:hdel(user_key, "display_name", "session_start", "session_id")
            red:hset(user_key, "last_activity", ngx.time())
            red:close()
            ngx.log(ngx.INFO, "🧹 Guest session cleaned up: " .. guest_username)
        end
    end
    
    return success, message
end

-- =============================================
-- STATUS AND DEBUG INFO
-- =============================================

function M.get_guest_session_status()
    local session_available, availability_message = check_session_availability()
    
    return {
        success = true,
        guest_account = "guest_user_1",
        session_available = session_available,
        availability_message = availability_message,
        account_type = "hardcoded_in_redis",
        system_info = {
            guest_account_name = "guest_user_1",
            session_timeout = 3600,
            inactivity_threshold = 60,
            current_timestamp = ngx.time()
        }
    }
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return M