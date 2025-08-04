-- =============================================================================
-- nginx/lua/manage_redis_sessions.lua - REDIS SESSION MANAGEMENT (EXTRACTED FROM AUTH)
-- =============================================================================

local cjson = require "cjson"
local redis = require "resty.redis"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379

local M = {}

-- Helper function to handle Redis null values
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

-- =============================================
-- PRIORITY SYSTEM
-- =============================================

local function get_user_priority(user_type)
    if user_type == "is_admin" then return 1 end
    if user_type == "is_approved" then return 2 end
    if user_type == "is_guest" then return 3 end
    return 4  -- is_pending, is_none, etc.
end

-- =============================================
-- SESSION QUERIES
-- =============================================

-- Get the currently active user (if any)
function M.get_active_user()
    local red = connect_redis()
    if not red then
        return nil, "Redis connection failed"
    end
    
    -- Find user with is_active = true
    local user_keys = red:keys("username:*")
    
    for _, key in ipairs(user_keys) do
        local is_active = red:hget(key, "is_active")
        if is_active == "true" then
            local user_data = red:hgetall(key)
            red:close()
            
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    local field = user_data[i]
                    local value = redis_to_lua(user_data[i + 1])
                    user[field] = value
                end
                return user, nil
            end
        end
    end
    
    red:close()
    return nil, "No active user"
end

-- Check if a specific user's session is still active
function M.is_user_session_active(username)
    if not username then
        return false, "Missing username"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    local is_active = red:hget(user_key, "is_active")
    
    red:close()
    
    return is_active == "true", "Session checked"
end

-- Get all active sessions with details
function M.get_all_active_sessions()
    local red = connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local user_keys = red:keys("username:*")
    local sessions = {}
    
    for _, key in ipairs(user_keys) do
        local user_data = red:hgetall(key)
        if user_data and #user_data > 0 then
            local user = {}
            for i = 1, #user_data, 2 do
                local field = user_data[i]
                local value = redis_to_lua(user_data[i + 1])
                user[field] = value
            end
            
            -- Only include sessions with activity data and active status
            if user.last_activity and user.is_active == "true" then
                table.insert(sessions, {
                    username = user.username,
                    user_type = user.user_type,
                    is_active = true,
                    priority = get_user_priority(user.user_type),
                    last_activity = tonumber(user.last_activity) or 0,
                    login_time = tonumber(user.login_time) or 0
                })
            end
        end
    end
    
    red:close()
    return sessions, nil
end

-- =============================================
-- SESSION ACTIVATION (WITH PRIORITY HANDLING)
-- =============================================

-- Set a user as active (handles priority and kicking)
function M.set_user_active(username, user_type)
    if not username or not user_type then
        return false, "Missing username or user_type"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local new_priority = get_user_priority(user_type)
    
    -- Check for currently active user
    local active_user, err = M.get_active_user()
    if active_user then
        local active_priority = get_user_priority(active_user.user_type)
        
        -- If new user has lower or equal priority, deny access UNLESS it's manual admin override
        if new_priority >= active_priority then
            -- SPECIAL CASE: Allow admin/approved users to override guest sessions
            if (user_type == "is_admin" or user_type == "is_approved") and active_user.user_type == "is_guest" then
                ngx.log(ngx.INFO, string.format("🔧 %s '%s' overriding guest session", user_type, username))
                -- Continue to kick out the guest
            else
                red:close()
                return false, string.format("Access denied. %s '%s' is currently active", 
                    active_user.user_type, active_user.username)
            end
        end
        
        -- New user has higher priority OR is overriding guest - kick out existing user
        local active_key = "username:" .. active_user.username
        red:hset(active_key, "is_active", "false")
        red:hset(active_key, "last_activity", ngx.time())
        
        ngx.log(ngx.INFO, string.format("🚫 Kicked out %s '%s' for higher priority %s '%s'",
            active_user.user_type, active_user.username, user_type, username))
    end
    
    -- Set new user as active
    local user_key = "username:" .. username
    local current_time = ngx.time()
    
    red:hset(user_key, "is_active", "true")
    red:hset(user_key, "last_activity", current_time)
    red:hset(user_key, "login_time", current_time)
    
    red:close()
    
    ngx.log(ngx.INFO, string.format("✅ Session activated for %s '%s'", user_type, username))
    return true, "Session activated"
end

-- =============================================
-- SESSION VALIDATION AND MAINTENANCE
-- =============================================

-- Validate that a user's session is still active and update activity
function M.validate_and_update_session(username, user_type)
    if not username then
        return false, "Missing username"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    local is_active = red:hget(user_key, "is_active")
    
    if is_active ~= "true" then
        red:close()
        return false, "Session not active"
    end
    
    -- Update activity timestamp
    red:hset(user_key, "last_activity", ngx.time())
    red:close()
    
    return true, "Session valid and updated"
end

-- Check if user's session is active with enhanced guest session checking
function M.check_session_active(username, user_type)
    ngx.log(ngx.INFO, "🔄 Checking session activity for: " .. tostring(username) .. " (" .. tostring(user_type) .. ")")
    
    if not username then
        ngx.log(ngx.WARN, "❌ No username provided for session check")
        return false
    end
    
    -- Guest users have special handling - check expiration
    if user_type == "is_guest" then
        local red = connect_redis()
        if not red then
            ngx.log(ngx.ERR, "❌ Redis connection failed for guest session check")
            return false
        end
        
        local user_key = "username:" .. username
        local last_activity = tonumber(red:hget(user_key, "last_activity")) or 0
        local current_time = ngx.time()
        
        red:close()
        
        -- Check if guest session expired (1 hour = 3600 seconds)
        if current_time - last_activity > 3600 then
            ngx.log(ngx.INFO, "❌ Guest session expired for " .. username)
            return false
        end
        
        ngx.log(ngx.INFO, "✅ Guest session active for " .. username)
        return true
    end
    
    -- For non-guest users, check is_active flag
    if user_type == "is_none" then
        return true -- No session needed for unauthenticated users
    end
    
    local session_valid, session_err = M.validate_and_update_session(username, user_type)
    if not session_valid then
        ngx.log(ngx.WARN, string.format("❌ Session validation failed for %s '%s': %s", 
            user_type, username, session_err or "unknown"))
        return false
    end
    
    ngx.log(ngx.INFO, "✅ Session active for " .. username)
    return true
end

-- =============================================
-- SESSION DEACTIVATION
-- =============================================

-- Clear a user's active session
function M.clear_user_session(username)
    if not username then
        return false, "Missing username"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    red:hset(user_key, "is_active", "false")
    red:hset(user_key, "last_activity", ngx.time())
    
    red:close()
    
    ngx.log(ngx.INFO, "🗑️ Session cleared for user: " .. username)
    return true, "Session cleared"
end

-- Force logout a specific user (admin function)
function M.force_logout_user(target_username)
    if not target_username then
        return false, "Username required"
    end
    
    local success, err = M.clear_user_session(target_username)
    if success then
        ngx.log(ngx.INFO, "🔨 Force logout successful for: " .. target_username)
        return true, "User forcefully logged out"
    else
        return false, err or "Failed to force logout"
    end
end

-- Clear all active sessions (emergency function)
function M.clear_all_active_sessions()
    local red = connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_keys = red:keys("username:*")
    local cleared = 0
    
    for _, key in ipairs(user_keys) do
        local is_active = red:hget(key, "is_active")
        if is_active == "true" then
            red:hset(key, "is_active", "false")
            red:hset(key, "last_activity", ngx.time())
            cleared = cleared + 1
        end
    end
    
    red:close()
    
    ngx.log(ngx.INFO, "🧹 Cleared " .. cleared .. " active sessions")
    return true, "Cleared " .. cleared .. " active sessions"
end

-- =============================================
-- SESSION CLEANUP AND MAINTENANCE
-- =============================================

-- Clean up stale sessions (sessions active but no activity for over 24 hours)
function M.cleanup_stale_sessions()
    local red = connect_redis()
    if not red then
        return 0, "Redis connection failed"
    end
    
    local user_keys = red:keys("username:*")
    local cleaned = 0
    local current_time = ngx.time()
    
    for _, key in ipairs(user_keys) do
        local is_active = red:hget(key, "is_active")
        local last_activity = red:hget(key, "last_activity")
        
        -- If active but no activity for over 24 hours, clear session
        if is_active == "true" and last_activity then
            local activity_time = tonumber(last_activity) or 0
            
            if current_time - activity_time > 86400 then -- 24 hours
                red:hset(key, "is_active", "false")
                cleaned = cleaned + 1
                ngx.log(ngx.INFO, "🧹 Cleaned stale session: " .. key)
            end
        end
    end
    
    red:close()
    return cleaned, nil
end

-- Clean up expired guest sessions but preserve hardcoded guest_user_1 account
function M.cleanup_expired_guest_sessions()
    local red = connect_redis()
    if not red then
        return 0, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local guest_keys = red:keys("username:guest_user_*")
    local cleaned = 0
    
    for _, key in ipairs(guest_keys) do
        local username = string.match(key, "username:(.+)")
        
        -- SPECIAL HANDLING: Never delete the hardcoded guest_user_1 account
        if username == "guest_user_1" then
            -- Just check if session is expired and deactivate it
            local last_activity = tonumber(red:hget(key, "last_activity")) or 0
            local session_age = current_time - last_activity
            
            if session_age > 3600 and red:hget(key, "is_active") == "true" then
                -- Deactivate expired session but keep the account
                red:hset(key, "is_active", "false")
                red:hdel(key, "display_name", "session_start", "session_id")
                cleaned = cleaned + 1
                ngx.log(ngx.INFO, "🧹 Deactivated expired guest_user_1 session (age: " .. session_age .. "s)")
            end
        else
            -- For any other guest users (if they exist), clean them up normally
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local session = {}
                for i = 1, #user_data, 2 do
                    local field = user_data[i]
                    local value = redis_to_lua(user_data[i + 1])
                    session[field] = value
                end
                
                -- Check for incomplete records (missing required fields)
                if not session.username or not session.user_type then
                    red:del(key)
                    cleaned = cleaned + 1
                    ngx.log(ngx.INFO, "🧹 Cleaned incomplete guest record: " .. key)
                else
                    local last_activity = tonumber(session.last_activity) or 0
                    local session_age = current_time - last_activity
                    
                    -- Remove expired sessions (>1 hour old)
                    if session_age > 3600 then
                        red:del(key)
                        cleaned = cleaned + 1
                        ngx.log(ngx.INFO, "🧹 Cleaned expired guest session: " .. key .. " (age: " .. session_age .. "s)")
                    end
                end
            else
                -- Empty or corrupted record
                red:del(key)
                cleaned = cleaned + 1
                ngx.log(ngx.INFO, "🧹 Cleaned empty guest record: " .. key)
            end
        end
    end
    
    red:close()
    return cleaned, nil
end

-- =============================================
-- ADMIN SESSION MANAGEMENT APIs
-- =============================================

function M.get_session_stats()
    local active_user, err = M.get_active_user()
    
    local stats = {
        max_concurrent_sessions = 1,
        priority_system_enabled = true,
        active_sessions = active_user and 1 or 0,
        available_slots = active_user and 0 or 1,
        storage_type = "redis_simple"
    }
    
    if active_user then
        stats.current_session = {
            username = active_user.username,
            user_type = active_user.user_type,
            priority = get_user_priority(active_user.user_type),
            login_time = tonumber(active_user.login_time) or 0,
            last_activity = tonumber(active_user.last_activity) or 0,
            remote_addr = active_user.created_ip or "unknown"
        }
    end
    
    return stats, nil
end

-- =============================================
-- API HANDLERS FOR ADMIN ENDPOINTS
-- =============================================

function M.handle_session_status()
    local session_stats, err = M.get_session_stats()
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to get session status: " .. err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        session_stats = session_stats
    }))
    ngx.exit(200)
end

function M.handle_force_logout()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    local target_username = nil
    if body then
        local ok, data = pcall(cjson.decode, body)
        if ok and data.username then
            target_username = data.username
        end
    end
    
    local success, err
    if target_username then
        success, err = M.force_logout_user(target_username)
    else
        -- Force logout current active user
        local active_user, active_err = M.get_active_user()
        if active_user then
            success, err = M.clear_user_session(active_user.username)
        else
            success, err = false, "No active session"
        end
    end
    
    if success then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            message = err or "Session cleared successfully"
        }))
    else
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = err or "Failed to clear session"
        }))
    end
    ngx.exit(ngx.status)
end

function M.handle_all_sessions()
    local sessions, err = M.get_all_active_sessions()
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        sessions = sessions,
        count = #sessions
    }))
    ngx.exit(200)
end

function M.handle_cleanup_sessions()
    local cleaned_stale, stale_err = M.cleanup_stale_sessions()
    local cleaned_guests, guest_err = M.cleanup_expired_guest_sessions()
    
    if stale_err or guest_err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = stale_err or guest_err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Session cleanup completed",
        cleaned_stale_sessions = cleaned_stale,
        cleaned_guest_sessions = cleaned_guests,
        total_cleaned = cleaned_stale + cleaned_guests
    }))
    ngx.exit(200)
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    -- Session queries
    get_active_user = M.get_active_user,
    is_user_session_active = M.is_user_session_active,
    get_all_active_sessions = M.get_all_active_sessions,
    
    -- Session activation/deactivation
    set_user_active = M.set_user_active,
    validate_and_update_session = M.validate_and_update_session,
    check_session_active = M.check_session_active,
    clear_user_session = M.clear_user_session,
    force_logout_user = M.force_logout_user,
    clear_all_active_sessions = M.clear_all_active_sessions,
    
    -- Session maintenance
    cleanup_stale_sessions = M.cleanup_stale_sessions,
    cleanup_expired_guest_sessions = M.cleanup_expired_guest_sessions,
    get_session_stats = M.get_session_stats,
    
    -- Admin API handlers
    handle_session_status = M.handle_session_status,
    handle_force_logout = M.handle_force_logout,
    handle_all_sessions = M.handle_all_sessions,
    handle_cleanup_sessions = M.handle_cleanup_sessions,
    
    -- Utility functions for other modules
    redis_to_lua = redis_to_lua,
    connect_redis = connect_redis
}