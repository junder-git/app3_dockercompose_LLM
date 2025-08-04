-- =============================================================================
-- nginx/lua/is_guest.lua - COMPLETE WITH COLLISION DETECTION AND PROTECTION
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
-- GUEST NAME GENERATION
-- =============================================

local ADJECTIVES = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural", "Cosmic"}
local ANIMALS = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}

local function generate_guest_name()
    local adjective = ADJECTIVES[math.random(#ADJECTIVES)]
    local animal = ANIMALS[math.random(#ANIMALS)]
    local number = math.random(100, 999)
    return adjective .. animal .. number
end

-- =============================================
-- COLLISION DETECTION AND SESSION MANAGEMENT
-- =============================================

local function check_existing_guest_session()
    local red = auth.connect_redis()
    if not red then
        return nil, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local guest_username = "guest_user_1"  -- Our single guest slot
    local user_key = "username:" .. guest_username
    
    -- Check if guest_user_1 exists
    local existing_data = red:hgetall(user_key)
    
    if existing_data and #existing_data > 0 then
        -- Parse existing session data
        local session = {}
        for i = 1, #existing_data, 2 do
            local field = existing_data[i]
            local value = existing_data[i + 1]
            if value == ngx.null then value = nil end
            session[field] = value
        end
        
        local last_activity = tonumber(session.last_activity) or 0
        local is_active = session.is_active == "true"
        local session_age = current_time - last_activity
        
        ngx.log(ngx.INFO, string.format("🔍 Found existing guest_user_1: active=%s, age=%ds", 
            tostring(is_active), session_age))
        
        red:close()
        
        -- Return session analysis
        return {
            exists = true,
            is_active = is_active,
            session_age = session_age,
            last_activity = last_activity,
            can_reuse = not is_active or session_age > 60,  -- Can reuse if inactive or old
            should_block = is_active and session_age <= 60,  -- Block if recently active
            session_data = session
        }, nil
    else
        red:close()
        ngx.log(ngx.INFO, "✨ No existing guest_user_1 found")
        return {
            exists = false,
            can_reuse = true,
            should_block = false
        }, nil
    end
end

local function check_high_priority_sessions()
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local user_keys = red:keys("username:*")
    local high_priority_sessions = {}
    
    for _, key in ipairs(user_keys) do
        local is_active = red:hget(key, "is_active")
        local user_type = red:hget(key, "user_type")
        local username = red:hget(key, "username")
        local last_activity = tonumber(red:hget(key, "last_activity")) or 0
        
        -- Check for active admin or approved users
        if is_active == "true" and (user_type == "is_admin" or user_type == "is_approved") then
            local session_age = current_time - last_activity
            
            -- Only consider recently active (within 1 minute) as blocking
            if session_age <= 60 then
                table.insert(high_priority_sessions, {
                    username = username,
                    user_type = user_type,
                    last_activity = last_activity,
                    session_age = session_age,
                    priority = user_type == "is_admin" and 1 or 2
                })
            end
        end
    end
    
    red:close()
    return high_priority_sessions, nil
end

-- =============================================
-- SMART GUEST SESSION CREATION WITH COMPREHENSIVE COLLISION DETECTION
-- =============================================

function M.handle_create_session()
    ngx.log(ngx.INFO, "✅ is_guest: Smart guest session creation with collision detection")
    
    -- Step 1: Check for high priority users (admin/approved) that would block guest creation
    local high_priority_sessions, hp_err = check_high_priority_sessions()
    if hp_err then
        ngx.log(ngx.ERR, "Failed to check high priority sessions: " .. hp_err)
        send_json(500, {
            success = false,
            error = "Session check failed",
            message = "Unable to verify current session state"
        })
    end
    
    if #high_priority_sessions > 0 then
        local blocking_session = high_priority_sessions[1]  -- Get the first (highest priority) blocking session
        local priority_name = blocking_session.user_type == "is_admin" and "Administrator" or "Approved User"
        
        ngx.log(ngx.INFO, string.format("❌ Guest session blocked by %s '%s' (active %ds ago)", 
            priority_name, blocking_session.username, blocking_session.session_age))
        
        send_json(409, {
            success = false,
            error = "Sessions are currently full",
            message = string.format("%s '%s' is currently active (last seen %d seconds ago)", 
                priority_name, blocking_session.username, blocking_session.session_age),
            reason = "high_priority_user_active",
            blocking_info = {
                user_type = blocking_session.user_type,
                priority = blocking_session.priority,
                session_age = blocking_session.session_age
            },
            suggestion = "Please try again in a few minutes when the current session becomes inactive"
        })
    end
    
    -- Step 2: Check existing guest session for collision
    local guest_session_info, guest_err = check_existing_guest_session()
    if guest_err then
        ngx.log(ngx.ERR, "Failed to check guest session: " .. guest_err)
        send_json(500, {
            success = false,
            error = "Guest session check failed",
            message = "Unable to verify guest session state"
        })
    end
    
    if guest_session_info.should_block then
        ngx.log(ngx.INFO, string.format("❌ Guest session blocked - another guest active %ds ago", 
            guest_session_info.session_age))
        
        send_json(409, {
            success = false,
            error = "Guest session already active",
            message = string.format("Another guest user is currently active (last seen %d seconds ago). Please wait a moment.", 
                guest_session_info.session_age),
            reason = "guest_session_active",
            session_info = {
                session_age = guest_session_info.session_age,
                time_until_available = math.max(0, 60 - guest_session_info.session_age)
            },
            suggestion = "Please try again in " .. math.max(1, math.ceil((60 - guest_session_info.session_age) / 60)) .. " minute(s)"
        })
    end
    
    -- Step 3: Session creation is allowed - proceed with creation/reuse
    local now = ngx.time()
    local guest_username = "guest_user_1"
    local display_name = generate_guest_name()
    
    -- Create/overwrite guest user in Redis
    local red = auth.connect_redis()
    if not red then
        send_json(500, {
            success = false,
            error = "Database connection failed"
        })
    end
    
    local user_key = "username:" .. guest_username
    
    -- CRITICAL: Always delete the old session first to prevent conflicts
    if guest_session_info.exists then
        ngx.log(ngx.INFO, "♻️ Reusing guest slot - deleting old session first")
        red:del(user_key)
    end
    
    -- Create fresh session with all required fields
    local ok, err = red:hmset(user_key,
        "username", guest_username,
        "user_type", "is_guest",
        "display_name", display_name,
        "created_at", os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "last_activity", now,
        "is_active", "true",  -- CRITICAL: Set as active
        "created_ip", ngx.var.remote_addr or "unknown",
        "session_id", tostring(now) .. "_" .. math.random(1000, 9999),  -- Unique session ID
        "creation_method", "guest_api"
    )
    
    if not ok then
        red:close()
        send_json(500, {
            success = false,
            error = "Failed to create guest session: " .. tostring(err)
        })
    end
    
    -- Set expiration for guest user (1 hour)
    red:expire(user_key, 3600)
    red:close()
    
    -- Create JWT token with proper structure
    local payload = {
        username = guest_username,
        user_type = "is_guest",
        display_name = display_name,
        last_activity = now,
        iat = now,
        exp = now + 3600  -- 1 hour expiration
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    -- Set cookie and return success response
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600"
    
    local action_taken = guest_session_info.exists and "reused_inactive_session" or "created_new_session"
    
    ngx.log(ngx.INFO, "✅ Guest session " .. action_taken .. ": " .. display_name .. " -> " .. guest_username)
    
    send_json(200, {
        success = true,
        message = "Guest session created successfully",
        username = display_name,
        internal_username = guest_username,
        user_type = "is_guest",
        cookie_set = true,
        slot = 1,
        session_expires_in = 3600,
        action_taken = action_taken,
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
-- GUEST SESSION VALIDATION AND UTILITIES
-- =============================================

function M.validate_guest_session(username)
    if not username or not string.match(username, "^guest_user_") then
        return false, "Invalid guest username"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        red:close()
        return false, "Guest session not found"
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

function M.cleanup_expired_guest_sessions()
    local red = auth.connect_redis()
    if not red then
        return 0, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local guest_keys = red:keys("username:guest_user_*")
    local cleaned = 0
    
    for _, key in ipairs(guest_keys) do
        local user_data = red:hgetall(key)
        if user_data and #user_data > 0 then
            local session = {}
            for i = 1, #user_data, 2 do
                local field = user_data[i]
                local value = user_data[i + 1]
                if value == ngx.null then value = nil end
                session[field] = value
            end
            
            local last_activity = tonumber(session.last_activity) or 0
            local session_age = current_time - last_activity
            
            -- Remove expired sessions (>1 hour old)
            if session_age > 3600 then
                red:del(key)
                cleaned = cleaned + 1
                ngx.log(ngx.INFO, "🧹 Cleaned expired guest session: " .. key .. " (age: " .. session_age .. "s)")
            end
        end
    end
    
    red:close()
    return cleaned, nil
end

-- =============================================
-- GUEST SESSION STATUS AND DEBUG INFO
-- =============================================

function M.get_guest_session_status()
    local guest_session_info, err1 = check_existing_guest_session()
    local high_priority_sessions, err2 = check_high_priority_sessions()
    
    if err1 or err2 then
        return {
            success = false,
            error = err1 or err2
        }
    end
    
    local cleaned_sessions, _ = M.cleanup_expired_guest_sessions()
    
    return {
        success = true,
        guest_session = guest_session_info,
        high_priority_sessions = high_priority_sessions,
        can_create_guest = not guest_session_info.should_block and #high_priority_sessions == 0,
        blocking_reason = guest_session_info.should_block and "guest_recently_active" or 
                         (#high_priority_sessions > 0 and "high_priority_user_active" or nil),
        cleaned_expired_sessions = cleaned_sessions,
        system_info = {
            max_guest_sessions = 1,
            guest_session_timeout = 3600,
            inactivity_threshold = 60,
            current_timestamp = ngx.time()
        }
    }
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return M