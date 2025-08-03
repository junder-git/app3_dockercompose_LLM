-- =============================================================================
-- nginx/lua/manage_auth.lua - FIXED CIRCULAR DEPENDENCY AND SYNTAX
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local redis = require "resty.redis"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379

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

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- Get user function with proper Redis handling
local function get_user(username)
    if not username or username == "" then
        ngx.log(ngx.WARN, "get_user called with empty username")
        return nil
    end
    
    local red = connect_redis()
    if not red then 
        ngx.log(ngx.ERR, "get_user: Redis connection failed")
        return nil 
    end
    
    local user_key = "username:" .. username
    local user_data = red:hgetall(user_key)
    
    -- Check if Redis returned an empty array (key doesn't exist)
    if not user_data or #user_data == 0 then
        ngx.log(ngx.WARN, "User not found: " .. user_key)
        red:close()
        return nil
    end
    
    -- Convert Redis hash to Lua table
    local user = {}
    for i = 1, #user_data, 2 do
        local key = user_data[i]
        local value = redis_to_lua(user_data[i + 1])
        user[key] = value
    end
    
    red:close()
    
    -- Validate required fields
    if not user.username or not user.password_hash then
        ngx.log(ngx.WARN, "Missing required fields for user: " .. username)
        return nil
    end
    
    return user
end

-- Password verification with exact same method as Redis init script
local function verify_password(password, stored_hash)
    if not password or not stored_hash then
        ngx.log(ngx.WARN, "verify_password: Missing password or hash")
        return false
    end
    
    -- CRITICAL: Use exact same method as redis/init-redis.sh
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | awk '{print $2}'",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    
    return hash == stored_hash
end

-- =============================================
-- INLINE SESSION FUNCTIONS (NO EXTERNAL MODULE)
-- =============================================

-- Get priority level based on user type
local function get_user_priority(user_type)
    if user_type == "admin" then return 1 end
    if user_type == "approved" then return 2 end
    if user_type == "guest" then return 3 end
    return 4  -- pending, none, etc.
end

-- Get the currently active user (if any)
local function get_active_user()
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

-- Set a user as active (handles priority and kicking)
local function set_user_active(username, user_type)
    if not username or not user_type then
        return false, "Missing username or user_type"
    end
    
    local red = connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local new_priority = get_user_priority(user_type)
    
    -- Check for currently active user
    local active_user, err = get_active_user()
    if active_user then
        local active_priority = get_user_priority(active_user.user_type)
        
        -- If new user has lower or equal priority, deny access
        if new_priority >= active_priority then
            red:close()
            return false, string.format("Access denied. %s '%s' is currently active", 
                active_user.user_type, active_user.username)
        end
        
        -- New user has higher priority - kick out existing user
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

-- Validate that a user's session is still active
local function validate_session(username, user_type)
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
    
    return true, "Session valid"
end

-- Clear a user's active session
local function clear_user_session(username)
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

-- =============================================
-- SEPARATED AUTH CHECK FUNCTIONS
-- =============================================

-- Check if user has valid JWT and get user data
local function check_user_type()
    local token = ngx.var.cookie_access_token
    
    ngx.log(ngx.INFO, "🔍 Checking JWT token. Token present: " .. (token and "YES" or "NO"))
    
    if not token then
        ngx.log(ngx.INFO, "❌ No JWT token found in cookies")
        return "is_none", nil, nil
    end
    
    ngx.log(ngx.INFO, "🔑 JWT token found, length: " .. string.len(token))
    
    -- Verify and decode JWT
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj or not jwt_obj.valid or not jwt_obj.payload then
        ngx.log(ngx.WARN, "❌ JWT verification failed. Valid: " .. tostring(jwt_obj and jwt_obj.valid))
        return "is_none", nil, nil
    end
    
    local payload = jwt_obj.payload
    ngx.log(ngx.INFO, "✅ JWT valid. Username: " .. tostring(payload.username) .. ", Type: " .. tostring(payload.user_type))
    
    -- Check token expiration
    if payload.exp and payload.exp < ngx.time() then
        ngx.log(ngx.WARN, "❌ JWT token expired")
        return "is_none", nil, nil
    end
    
    -- Get username from JWT
    local username = payload.username
    if not username then
        ngx.log(ngx.WARN, "JWT token missing username")
        return "is_none", nil, nil
    end
    
    -- Get fresh user data from Redis
    local user_data = get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "User from JWT not found in Redis: " .. username)
        return "is_none", nil, nil
    end
    
    local user_type = user_data.user_type
    ngx.log(ngx.INFO, "📊 Redis user data. Type: " .. tostring(user_type) .. ", Active: " .. tostring(user_data.is_active))
    
    -- Return user type based on fresh data from Redis (with is_ prefix for compatibility)
    if user_type == "admin" then
        return "is_admin", username, user_data
    elseif user_type == "approved" then
        return "is_approved", username, user_data
    elseif user_type == "pending" then
        return "is_pending", username, user_data
    elseif user_type == "guest" then
        return "is_guest", username, user_data
    else
        ngx.log(ngx.WARN, "Unknown user type from Redis: " .. tostring(user_type))
        return "is_none", nil, nil
    end
end

-- Check if user's session is active (for non-guest users)
local function check_is_active(username, user_type)
    ngx.log(ngx.INFO, "🔄 Checking session activity for: " .. tostring(username) .. " (" .. tostring(user_type) .. ")")
    
    if not username or user_type == "is_guest" or user_type == "is_none" then
        ngx.log(ngx.INFO, "✅ Skipping session check for guest/none user")
        return true -- Guests and unauthenticated users don't need active session check
    end
    
    -- Convert is_ prefix back to plain user_type for session manager
    local plain_user_type = user_type:gsub("^is_", "")
    
    local session_valid, session_err = validate_session(username, plain_user_type)
    if not session_valid then
        ngx.log(ngx.WARN, string.format("❌ Session validation failed for %s '%s': %s", 
            user_type, username, session_err or "unknown"))
        return false
    end
    
    ngx.log(ngx.INFO, "✅ Session active for " .. username)
    return true
end

-- =============================================
-- LOGIN AND LOGOUT HANDLERS
-- =============================================

local function handle_login()
    ngx.log(ngx.INFO, "=== LOGIN ATTEMPT START ===")
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        ngx.log(ngx.WARN, "Login: No request body")
        send_json(400, { error = "No request body" })
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        ngx.log(ngx.WARN, "Login: Invalid JSON: " .. tostring(data))
        send_json(400, { error = "Invalid JSON" })
    end
    
    local username = data.username
    local password = data.password
    
    if not username or not password then
        ngx.log(ngx.WARN, "Login: Missing credentials")
        send_json(400, { error = "Username and password required" })
    end
    
    ngx.log(ngx.INFO, "Login: Attempting login for username: " .. username)
    
    local user_data = get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "Login: User not found: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    -- Verify password
    if not verify_password(password, user_data.password_hash) then
        ngx.log(ngx.WARN, "Login: Invalid password for user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    -- Set user as active (handles priority and kicking)
    local plain_user_type = user_data.user_type
    local session_success, session_result = set_user_active(username, plain_user_type)
    if not session_success then
        ngx.log(ngx.WARN, string.format("Login denied for %s '%s': %s", 
            plain_user_type, username, session_result))
        send_json(409, { 
            error = "Login not allowed",
            message = session_result,
            reason = "sessions_full"
        })
    end
    
    ngx.log(ngx.INFO, "Login: Session activated successfully")
    
    -- Generate JWT
    local payload = {
        username = username,
        user_type = user_data.user_type,
        iat = ngx.time(),
        exp = ngx.time() + 86400 * 7  -- 7 days
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    -- Set secure cookie with proper format
    local cookie_value = string.format("access_token=%s; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800", token)
    ngx.header["Set-Cookie"] = cookie_value
    
    ngx.log(ngx.INFO, "🍪 Setting cookie: " .. cookie_value)
    
    ngx.log(ngx.INFO, string.format("Login: Success for %s '%s'", 
        user_data.user_type, username))
    
    send_json(200, {
        success = true,
        message = "Login successful",
        username = username,
        user_type = user_data.user_type,
        redirect = "/chat"
    })
end

local function handle_logout()
    ngx.log(ngx.INFO, "=== LOGOUT START ===")
    
    local user_type, username, user_data = check_user_type()
    
    ngx.log(ngx.INFO, "Logging out user: " .. (username or "unknown") .. " (type: " .. (user_type or "none") .. ")")
    
    -- Clear session if authenticated
    if username and user_type ~= "is_none" then
        local success, err = clear_user_session(username)
        if success then
            ngx.log(ngx.INFO, "Session cleared successfully")
        else
            ngx.log(ngx.WARN, "Failed to clear session: " .. (err or "unknown"))
        end
    end
    
    -- Clear cookies
    local cookie_headers = {
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    }
    ngx.header["Set-Cookie"] = cookie_headers
    
    local logout_user = username or "guest"
    local logout_type = user_type or "is_none"
    
    ngx.log(ngx.INFO, "=== LOGOUT COMPLETE ===")
    ngx.log(ngx.INFO, "User logged out successfully: " .. logout_user .. " (type: " .. logout_type .. ")")
    
    send_json(200, {
        success = true,
        message = "Logout successful",
        redirect = "/",
        logged_out_user = logout_user,
        logged_out_type = logout_type
    })
end

-- =============================================
-- ADMIN SESSION MANAGEMENT APIs
-- =============================================

local function get_session_stats()
    local active_user, err = get_active_user()
    
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

local function handle_session_status()
    local session_stats, err = get_session_stats()
    if err then
        send_json(500, {
            success = false,
            error = "Failed to get session status: " .. err
        })
    end
    
    send_json(200, {
        success = true,
        session_stats = session_stats
    })
end

local function handle_force_logout()
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
        success, err = clear_user_session(target_username)
    else
        -- Force logout current active user
        local active_user, active_err = get_active_user()
        if active_user then
            success, err = clear_user_session(active_user.username)
        else
            success, err = false, "No active session"
        end
    end
    
    if success then
        send_json(200, {
            success = true,
            message = "Session cleared successfully"
        })
    else
        send_json(400, {
            success = false,
            error = err or "Failed to clear session"
        })
    end
end

local function handle_all_sessions()
    local red = connect_redis()
    if not red then
        send_json(500, {
            success = false,
            error = "Redis connection failed"
        })
        return
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
            
            -- Only include sessions with activity data
            if user.last_activity then
                table.insert(sessions, {
                    username = user.username,
                    user_type = user.user_type,
                    is_active = user.is_active == "true",
                    priority = get_user_priority(user.user_type),
                    last_activity = tonumber(user.last_activity) or 0,
                    login_time = tonumber(user.login_time) or 0
                })
            end
        end
    end
    
    red:close()
    
    send_json(200, {
        success = true,
        sessions = sessions,
        count = #sessions
    })
end

local function handle_cleanup_sessions()
    local red = connect_redis()
    if not red then
        send_json(500, {
            success = false,
            error = "Redis connection failed"
        })
        return
    end
    
    local user_keys = red:keys("username:*")
    local cleaned = 0
    
    for _, key in ipairs(user_keys) do
        local is_active = red:hget(key, "is_active")
        local last_activity = red:hget(key, "last_activity")
        
        -- If active but no activity for over 24 hours, clear session
        if is_active == "true" and last_activity then
            local activity_time = tonumber(last_activity) or 0
            local current_time = ngx.time()
            
            if current_time - activity_time > 86400 then -- 24 hours
                red:hset(key, "is_active", "false")
                cleaned = cleaned + 1
                ngx.log(ngx.INFO, "🧹 Cleaned stale session: " .. key)
            end
        end
    end
    
    red:close()
    
    send_json(200, {
        success = true,
        message = "Session cleanup completed",
        cleaned_sessions = cleaned
    })
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    check_user_type = check_user_type,
    check_is_active = check_is_active,
    get_user = get_user,
    verify_password = verify_password,
    handle_login = handle_login,
    handle_logout = handle_logout,
    handle_session_status = handle_session_status,
    handle_force_logout = handle_force_logout,
    handle_all_sessions = handle_all_sessions,
    handle_cleanup_sessions = handle_cleanup_sessions,
    -- Export Redis helper functions for other modules
    redis_to_lua = redis_to_lua,
    connect_redis = connect_redis,
    -- Export session functions for compatibility
    session_manager = {
        get_active_user = get_active_user,
        set_user_active = set_user_active,
        validate_session = validate_session,
        clear_user_session = clear_user_session
    }
}