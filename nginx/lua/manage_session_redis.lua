-- =============================================================================
-- nginx/lua/manage_session_redis.lua - REDIS-BASED SESSION MANAGEMENT
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- REDIS SESSION CONFIGURATION
-- =============================================

local REDIS_SESSION_KEY = "system:active_session"
local SESSION_TIMEOUT = 3600  -- 1 hour for regular users
local ADMIN_SESSION_TIMEOUT = 7200  -- 2 hours for admin

-- Priority levels (lower number = higher priority)
local function get_user_priority(user_type)
    if user_type == "is_admin" then return 1 end
    if user_type == "is_approved" then return 2 end
    if user_type == "is_guest" then return 3 end
    return 4
end

-- =============================================
-- CORE SESSION FUNCTIONS
-- =============================================

function M.get_active_session()
    local red = auth.connect_redis()
    if not red then
        return nil, "Redis connection failed"
    end
    
    local session_data = red:get(REDIS_SESSION_KEY)
    red:close()
    
    if not session_data or session_data == ngx.null then
        return nil, "No active session"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        ngx.log(ngx.ERR, "Invalid session data in Redis")
        M.clear_active_session()
        return nil, "Invalid session data"
    end
    
    -- Check if session has expired
    local current_time = ngx.time()
    if session.expires_at and current_time > session.expires_at then
        ngx.log(ngx.INFO, "Session expired for user: " .. (session.username or "unknown"))
        M.clear_active_session()
        return nil, "Session expired"
    end
    
    return session, nil
end

function M.create_session(username, user_type)
    if not username or not user_type then
        return false, "Missing username or user_type"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local session_timeout = (user_type == "is_admin") and ADMIN_SESSION_TIMEOUT or SESSION_TIMEOUT
    
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
        ngx.log(ngx.INFO, string.format("Kicking out %s '%s' for higher priority %s '%s'",
            existing_session.user_type, existing_session.username, user_type, username))
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
        session_id = username .. "_" .. current_time .. "_" .. math.random(10000, 99999),
        is_active = true
    }
    
    -- Store session in Redis with TTL
    local session_json = cjson.encode(session)
    local ok, err = red:setex(REDIS_SESSION_KEY, session_timeout + 60, session_json)
    
    if not ok then
        red:close()
        return false, "Failed to store session: " .. (err or "unknown")
    end
    
    -- Also store user-specific session for reference
    local user_session_key = "user_session:" .. username
    red:setex(user_session_key, session_timeout + 60, session_json)
    
    red:close()
    
    ngx.log(ngx.INFO, string.format("✅ Session created for %s '%s' (expires in %d seconds)", 
        user_type, username, session_timeout))
    
    return true, session
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
    
    -- Update activity timestamp
    M.update_session_activity(username, user_type)
    
    return true, active_session
end

function M.update_session_activity(username, user_type)
    if not username then
        return false, "Missing username"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local session_data = red:get(REDIS_SESSION_KEY)
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
    local current_time = ngx.time()
    session.last_activity = current_time
    
    local session_json = cjson.encode(session)
    local session_timeout = (user_type == "is_admin") and ADMIN_SESSION_TIMEOUT or SESSION_TIMEOUT
    
    red:setex(REDIS_SESSION_KEY, session_timeout + 60, session_json)
    
    -- Update user-specific session too
    local user_session_key = "user_session:" .. username
    red:setex(user_session_key, session_timeout + 60, session_json)
    
    red:close()
    
    return true, session
end

function M.clear_active_session()
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    -- Get session before clearing to log properly
    local session_data = red:get(REDIS_SESSION_KEY)
    local username = "unknown"
    local user_type = "unknown"
    
    if session_data and session_data ~= ngx.null then
        local ok, session = pcall(cjson.decode, session_data)
        if ok then
            username = session.username or "unknown"
            user_type = session.user_type or "unknown"
            
            -- Clear user-specific session
            local user_session_key = "user_session:" .. username
            red:del(user_session_key)
        end
    end
    
    -- Clear global active session
    red:del(REDIS_SESSION_KEY)
    red:close()
    
    ngx.log(ngx.INFO, string.format("🗑️ Session cleared for %s '%s'", user_type, username))
    
    return true, nil
end

function M.force_logout_current_user()
    local active_session, err = M.get_active_session()
    if not active_session then
        return false, "No active session to logout"
    end
    
    local success, clear_err = M.clear_active_session()
    if not success then
        return false, clear_err
    end
    
    ngx.log(ngx.INFO, string.format("🔨 Force logged out %s '%s'", 
        active_session.user_type, active_session.username))
    
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

function M.get_session_stats()
    local active_session, err = M.get_active_session()
    
    local stats = {
        max_concurrent_sessions = 1,
        admin_priority_enabled = true,
        active_sessions = active_session and 1 or 0,
        available_slots = active_session and 0 or 1,
        storage_type = "redis"
    }
    
    if active_session then
        stats.current_session = {
            username = active_session.username,
            user_type = active_session.user_type,
            created_at = active_session.created_at,
            last_activity = active_session.last_activity,
            expires_at = active_session.expires_at,
            time_remaining = active_session.expires_at - ngx.time(),
            remote_addr = active_session.remote_addr,
            session_id = active_session.session_id
        }
    end
    
    return stats, nil
end

function M.get_user_session(username)
    if not username then
        return nil, "Missing username"
    end
    
    local red = auth.connect_redis()
    if not red then
        return nil, "Redis connection failed"
    end
    
    local user_session_key = "user_session:" .. username
    local session_data = red:get(user_session_key)
    red:close()
    
    if not session_data or session_data == ngx.null then
        return nil, "No session found for user"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        return nil, "Invalid session data"
    end
    
    return session, nil
end

-- =============================================
-- CLEANUP FUNCTIONS
-- =============================================

function M.cleanup_expired_sessions()
    -- Redis TTL handles most cleanup automatically
    -- This function just validates the current session
    local active_session, err = M.get_active_session()
    
    if not active_session and err == "Session expired" then
        ngx.log(ngx.INFO, "🧹 Cleaned up expired session")
        return 1, nil
    end
    
    return 0, nil
end

function M.heartbeat_session(username, user_type)
    -- Simple heartbeat to keep session alive
    return M.update_session_activity(username, user_type)
end

-- =============================================
-- ADMIN FUNCTIONS
-- =============================================

function M.admin_force_logout(target_username)
    local active_session, err = M.get_active_session()
    if not active_session then
        return false, "No active session"
    end
    
    if active_session.username ~= target_username then
        return false, "Target user not in active session"
    end
    
    return M.force_logout_current_user()
end

function M.admin_get_all_user_sessions()
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local session_keys = red:keys("user_session:*")
    local sessions = {}
    
    for _, key in ipairs(session_keys) do
        local session_data = red:get(key)
        if session_data and session_data ~= ngx.null then
            local ok, session = pcall(cjson.decode, session_data)
            if ok then
                table.insert(sessions, session)
            end
        end
    end
    
    red:close()
    return sessions, nil
end

return M