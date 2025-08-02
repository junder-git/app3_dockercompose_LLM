-- =============================================================================
-- nginx/lua/manage_session.lua - SINGLE USER SESSION MANAGEMENT WITH ADMIN PRIORITY
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- SESSION CONFIGURATION
-- =============================================

local MAX_CONCURRENT_SESSIONS = 1
local ADMIN_PRIORITY = true
local SESSION_TIMEOUT = 3600 -- 1 hour for regular users
local ADMIN_SESSION_TIMEOUT = 7200 -- 2 hours for admin

-- =============================================
-- SESSION KEY HELPERS
-- =============================================

local function get_session_key(username)
    return "active_session:" .. username
end

local function get_global_session_key()
    return "global_active_session"
end

local function get_user_priority(user_type)
    if user_type == "admin" then return 1 end
    if user_type == "approved" then return 2 end
    if user_type == "guest" then return 3 end
    return 4
end

-- =============================================
-- SESSION TRACKING
-- =============================================

function M.get_active_session()
    local red = auth.connect_redis()
    if not red then
        return nil, "Redis connection failed"
    end
    
    local session_data = red:get(get_global_session_key())
    red:close()
    
    if not session_data or session_data == ngx.null then
        return nil, "No active session"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        return nil, "Invalid session data"
    end
    
    -- Check if session has expired
    local current_time = ngx.time()
    if session.expires_at and current_time > session.expires_at then
        ngx.log(ngx.INFO, "Session expired for user: " .. (session.username or "unknown"))
        M.clear_session(session.username, session.user_type)
        return nil, "Session expired"
    end
    
    return session, nil
end

function M.create_session(username, user_type, user_data)
    if not username or not user_type then
        return false, "Missing username or user_type"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local session_timeout = (user_type == "admin") and ADMIN_SESSION_TIMEOUT or SESSION_TIMEOUT
    
    -- Check for existing active session
    local existing_session, err = M.get_active_session()
    if existing_session then
        local existing_priority = get_user_priority(existing_session.user_type)
        local new_priority = get_user_priority(user_type)
        
        -- If new user has lower or equal priority, deny access
        if new_priority >= existing_priority then
            red:close()
            return false, string.format("Access denied. %s '%s' is currently logged in.", 
                existing_session.user_type, existing_session.username)
        end
        
        -- New user has higher priority - kick out existing user
        if ADMIN_PRIORITY and new_priority < existing_priority then
            ngx.log(ngx.INFO, string.format("Kicking out %s '%s' for higher priority %s '%s'",
                existing_session.user_type, existing_session.username, user_type, username))
            
            M.clear_session(existing_session.username, existing_session.user_type)
        end
    end
    
    -- Create new session
    local session = {
        username = username,
        user_type = user_type,
        created_at = current_time,
        last_activity = current_time,
        expires_at = current_time + session_timeout,
        remote_addr = ngx.var.remote_addr or "unknown",
        user_agent = ngx.var.http_user_agent or "unknown",
        session_id = username .. "_" .. current_time .. "_" .. math.random(10000, 99999)
    }
    
    -- Store global session
    local session_json = cjson.encode(session)
    red:setex(get_global_session_key(), session_timeout + 60, session_json)
    
    -- Store user-specific session
    red:setex(get_session_key(username), session_timeout + 60, session_json)
    
    red:close()
    
    ngx.log(ngx.INFO, string.format("✅ Session created for %s '%s' (expires in %d seconds)", 
        user_type, username, session_timeout))
    
    return true, session
end

function M.update_session_activity(username, user_type)
    if not username then
        return false, "Missing username"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    
    -- Get current session
    local session_data = red:get(get_global_session_key())
    if not session_data or session_data == ngx.null then
        red:close()
        return false, "No active session found"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok or session.username ~= username then
        red:close()
        return false, "Session mismatch"
    end
    
    -- Update activity timestamp
    session.last_activity = current_time
    
    local session_json = cjson.encode(session)
    local session_timeout = (user_type == "admin") and ADMIN_SESSION_TIMEOUT or SESSION_TIMEOUT
    
    red:setex(get_global_session_key(), session_timeout + 60, session_json)
    red:setex(get_session_key(username), session_timeout + 60, session_json)
    
    red:close()
    
    return true, session
end

function M.clear_session(username, user_type)
    if not username then
        return false, "Missing username"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    -- Clear global session
    red:del(get_global_session_key())
    
    -- Clear user-specific session
    red:del(get_session_key(username))
    
    red:close()
    
    ngx.log(ngx.INFO, string.format("🗑️ Session cleared for %s '%s'", user_type or "unknown", username))
    
    return true, nil
end

function M.validate_session(username, user_type)
    if not username then
        return false, "Missing username"
    end
    
    local active_session, err = M.get_active_session()
    if not active_session then
        return false, err or "No active session"
    end
    
    -- Check if this user owns the active session
    if active_session.username ~= username then
        return false, string.format("Session belongs to different user: %s", active_session.username)
    end
    
    -- Update activity
    M.update_session_activity(username, user_type)
    
    return true, active_session
end

-- =============================================
-- SESSION MANAGEMENT API
-- =============================================

function M.can_login(username, user_type)
    local active_session, err = M.get_active_session()
    if not active_session then
        return true, "No active session"
    end
    
    -- Same user trying to login again
    if active_session.username == username then
        return true, "Same user login"
    end
    
    -- Check priority
    local existing_priority = get_user_priority(active_session.user_type)
    local new_priority = get_user_priority(user_type)
    
    if new_priority < existing_priority then
        return true, "Higher priority user"
    end
    
    return false, string.format("Lower priority. %s '%s' is active until %s", 
        active_session.user_type, 
        active_session.username,
        os.date("%H:%M:%S", active_session.expires_at))
end

function M.force_logout_current_user()
    local active_session, err = M.get_active_session()
    if not active_session then
        return false, "No active session to logout"
    end
    
    local success, clear_err = M.clear_session(active_session.username, active_session.user_type)
    if not success then
        return false, clear_err
    end
    
    ngx.log(ngx.INFO, string.format("🔨 Force logged out %s '%s'", 
        active_session.user_type, active_session.username))
    
    return true, active_session
end

function M.get_session_stats()
    local active_session, err = M.get_active_session()
    
    local stats = {
        max_concurrent_sessions = MAX_CONCURRENT_SESSIONS,
        admin_priority_enabled = ADMIN_PRIORITY,
        active_sessions = active_session and 1 or 0,
        available_slots = active_session and 0 or 1
    }
    
    if active_session then
        stats.current_session = {
            username = active_session.username,
            user_type = active_session.user_type,
            created_at = active_session.created_at,
            last_activity = active_session.last_activity,
            expires_at = active_session.expires_at,
            time_remaining = active_session.expires_at - ngx.time()
        }
    end
    
    return stats, nil
end

-- =============================================
-- CLEANUP FUNCTIONS
-- =============================================

function M.cleanup_expired_sessions()
    local red = auth.connect_redis()
    if not red then
        return 0, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local cleaned = 0
    
    -- Check global session
    local session_data = red:get(get_global_session_key())
    if session_data and session_data ~= ngx.null then
        local ok, session = pcall(cjson.decode, session_data)
        if ok and session.expires_at and current_time > session.expires_at then
            M.clear_session(session.username, session.user_type)
            cleaned = cleaned + 1
        end
    end
    
    red:close()
    
    if cleaned > 0 then
        ngx.log(ngx.INFO, string.format("🧹 Cleaned up %d expired sessions", cleaned))
    end
    
    return cleaned, nil
end

return M