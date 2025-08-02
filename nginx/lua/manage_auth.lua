-- =============================================================================
-- nginx/lua/manage_auth.lua - UPDATED WITH SINGLE USER SESSION MANAGEMENT
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local redis = require "resty.redis"
local session_manager = require "manage_session"

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
-- ENHANCED AUTH CHECK WITH SESSION VALIDATION
-- =============================================
local function check()
    local token = ngx.var.cookie_access_token
    if not token then
        return "is_none", nil, nil
    end
    
    -- Verify and decode JWT
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj or not jwt_obj.valid or not jwt_obj.payload then
        return "is_none", nil, nil
    end
    
    local payload = jwt_obj.payload
    
    -- Check token expiration
    if payload.exp and payload.exp < ngx.time() then
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
    
    -- CRITICAL: Validate session for non-guest users
    if user_type ~= "guest" then
        local session_valid, session_err = session_manager.validate_session(username, user_type)
        if not session_valid then
            ngx.log(ngx.WARN, string.format("Session validation failed for %s '%s': %s", 
                user_type, username, session_err or "unknown"))
            return "is_none", nil, nil
        end
    end
    
    -- Return user type based on fresh data from Redis
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

-- =============================================
-- ENHANCED LOGIN HANDLER WITH SESSION MANAGEMENT
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
    
    -- CRITICAL: Check if user can login (session limits)
    local can_login, login_message = session_manager.can_login(username, user_data.user_type)
    if not can_login then
        ngx.log(ngx.WARN, string.format("Login denied for %s '%s': %s", 
            user_data.user_type, username, login_message))
        send_json(409, { 
            error = "Login not allowed",
            message = login_message,
            reason = "concurrent_session_limit"
        })
    end
    
    -- CREATE SESSION
    local session_success, session_result = session_manager.create_session(username, user_data.user_type, user_data)
    if not session_success then
        ngx.log(ngx.ERR, string.format("Failed to create session for %s '%s': %s", 
            user_data.user_type, username, session_result))
        send_json(500, { 
            error = "Failed to create session",
            message = session_result
        })
    end
    
    ngx.log(ngx.INFO, "Login: Session created successfully")
    
    -- Generate JWT
    local payload = {
        username = username,
        user_type = user_data.user_type,
        session_id = session_result.session_id,
        iat = ngx.time(),
        exp = ngx.time() + 86400 * 7  -- 7 days (longer than session for convenience)
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    -- Set secure cookie
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800"
    
    ngx.log(ngx.INFO, string.format("Login: Success for %s '%s' (session: %s)", 
        user_data.user_type, username, session_result.session_id))
    
    send_json(200, {
        success = true,
        message = "Login successful",
        username = username,
        user_type = user_data.user_type,
        session_info = {
            session_id = session_result.session_id,
            expires_at = session_result.expires_at,
            time_remaining = session_result.expires_at - ngx.time()
        },
        redirect = "/chat"
    })
end

-- =============================================
-- ENHANCED LOGOUT HANDLER WITH SESSION CLEANUP
-- =============================================
local function handle_logout()
    ngx.log(ngx.INFO, "=== LOGOUT START ===")
    
    local user_type, username, user_data = check()
    
    ngx.log(ngx.INFO, "Logging out user: " .. (username or "unknown") .. " (type: " .. (user_type or "none") .. ")")
    
    -- Clear session if authenticated
    if username and user_type ~= "is_none" then
        local session_success, session_err = session_manager.clear_session(username, user_type:gsub("is_", ""))
        if not session_success then
            ngx.log(ngx.WARN, "Failed to clear session: " .. (session_err or "unknown"))
        else
            ngx.log(ngx.INFO, "Session cleared successfully")
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
-- SESSION STATUS API
-- =============================================
local function handle_session_status()
    local stats, err = session_manager.get_session_stats()
    if err then
        send_json(500, {
            success = false,
            error = err
        })
        return
    end
    
    send_json(200, {
        success = true,
        session_stats = stats
    })
end

-- =============================================
-- FORCE LOGOUT API (ADMIN ONLY)
-- =============================================
local function handle_force_logout()
    -- Check if requester is admin
    local user_type, username, user_data = check()
    if user_type ~= "is_admin" then
        send_json(403, {
            success = false,
            error = "Admin access required"
        })
        return
    end
    
    local success, result = session_manager.force_logout_current_user()
    if not success then
        send_json(404, {
            success = false,
            error = result
        })
        return
    end
    
    send_json(200, {
        success = true,
        message = "User force logged out",
        logged_out_session = result
    })
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    check = check,
    get_user = get_user,
    verify_password = verify_password,
    handle_login = handle_login,
    handle_logout = handle_logout,
    handle_session_status = handle_session_status,
    handle_force_logout = handle_force_logout,
    -- Export Redis helper functions for other modules
    redis_to_lua = redis_to_lua,
    connect_redis = connect_redis
}