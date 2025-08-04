-- =============================================================================
-- nginx/lua/manage_auth.lua - SIMPLIFIED AUTH (JWT ONLY - NO SESSION LOGIC)
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local redis = require "resty.redis"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
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

-- Helper function to send JSON response and exit
local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- USER DATA RETRIEVAL
-- =============================================

function M.get_user(username)
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

-- =============================================
-- PASSWORD VERIFICATION
-- =============================================

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
-- JWT VALIDATION WITH GUEST PROTECTION
-- =============================================

function M.check_user_type()
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
    
    -- CRITICAL: Additional validation for guest users
    if string.match(username, "^guest_user_") then
        -- For guest users, validate the JWT more strictly
        local guest_user_type = payload.user_type
        
        if guest_user_type ~= "is_guest" then
            ngx.log(ngx.WARN, "❌ Guest username with invalid user_type: " .. tostring(guest_user_type))
            return "is_none", nil, nil
        end
        
        -- Check if guest session is still valid (shorter expiry)
        local guest_exp = payload.exp or 0
        local guest_max_age = 3600 -- 1 hour
        local issued_at = payload.iat or 0
        
        if ngx.time() - issued_at > guest_max_age then
            ngx.log(ngx.WARN, "❌ Guest JWT token too old")
            return "is_none", nil, nil
        end
    end
    
    -- Get fresh user data from Redis
    local user_data = M.get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "User from JWT not found in Redis: " .. username)
        return "is_none", nil, nil
    end
    
    -- CRITICAL: Cross-validate JWT user_type with Redis user_type
    local redis_user_type = user_data.user_type
    local jwt_user_type = payload.user_type
    
    -- For guest users, ensure consistency
    if string.match(username, "^guest_user_") then
        if redis_user_type ~= "is_guest" then
            ngx.log(ngx.WARN, "❌ Guest user has wrong type in Redis: " .. tostring(redis_user_type))
            return "is_none", nil, nil
        end
        
        if jwt_user_type ~= "is_guest" then
            ngx.log(ngx.WARN, "❌ Guest user has wrong type in JWT: " .. tostring(jwt_user_type))
            return "is_none", nil, nil
        end
    end
    
    -- For non-guest users, ensure they're not using guest usernames
    if not string.match(username, "^guest_user_") and redis_user_type == "is_guest" then
        ngx.log(ngx.WARN, "❌ Non-guest username with guest user_type: " .. username)
        return "is_none", nil, nil
    end
    
    ngx.log(ngx.INFO, "📊 Redis user data. Type: " .. tostring(redis_user_type) .. ", Active: " .. tostring(user_data.is_active))
    
    return redis_user_type, username, user_data
end

-- =============================================
-- SIMPLIFIED LOGIN HANDLER (JWT + SESSION DELEGATION)
-- =============================================

function M.handle_login()
    ngx.log(ngx.INFO, "=== POST LOGIN ATTEMPT START ===")
    
    -- CHECK: If user is already logged in, reactivate their session
    local current_user_type, current_username, current_user_data = M.check_user_type()
    if current_user_type ~= "is_none" and current_username then
        ngx.log(ngx.INFO, "User already logged in: " .. current_username .. " (" .. current_user_type .. ")")
        
        -- Delegate session activation to session manager
        local session_manager = require "manage_redis_sessions"
        local session_active = session_manager.check_session_active(current_username, current_user_type)
        if not session_active then
            ngx.log(ngx.INFO, "Reactivating session for already logged in user")
            local session_success, session_result = session_manager.set_user_active(current_username, current_user_type)
            if not session_success then
                ngx.log(ngx.WARN, "Failed to reactivate session: " .. (session_result or "unknown"))
                -- If we can't reactivate, continue with normal login flow
            else
                ngx.log(ngx.INFO, "Session reactivated successfully")
                send_json(200, {
                    success = true,
                    message = "Session reactivated",
                    username = current_username,
                    user_type = current_user_type,
                    cookie_set = true,
                    already_logged_in = true,
                    session_reactivated = true
                })
            end
        else
            -- Session is already active
            send_json(200, {
                success = true,
                message = "Already logged in",
                username = current_username,
                user_type = current_user_type,
                cookie_set = true,
                already_logged_in = true
            })
        end
    end
    
    -- Continue with normal login process
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
    
    -- CRITICAL: Block guest user login attempts
    if string.match(username, "^guest_user_") then
        ngx.log(ngx.WARN, "Login: Blocked guest user login attempt: " .. username)
        send_json(403, { 
            error = "Guest users cannot login manually",
            message = "Guest accounts are created automatically. Please use the 'Guest Chat' button instead.",
            suggestion = "Use the 'Guest Chat' button to start a guest session"
        })
    end
    
    ngx.log(ngx.INFO, "Login: Attempting login for username: " .. username)
    
    local user_data = M.get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "Login: User not found: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    -- ADDITIONAL: Block if user_type is is_guest (in case someone manually created a guest in Redis)
    if user_data.user_type == "is_guest" then
        ngx.log(ngx.WARN, "Login: Blocked guest user type login: " .. username)
        send_json(403, { 
            error = "Guest accounts cannot login manually",
            message = "This is a guest account. Guest sessions are created automatically.",
            suggestion = "Use the 'Guest Chat' button to start a guest session"
        })
    end
    
    -- Verify password
    if not verify_password(password, user_data.password_hash) then
        ngx.log(ngx.WARN, "Login: Invalid password for user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    local session_user_type = user_data.user_type
    
    -- DELEGATE session activation to session manager
    local session_manager = require "manage_redis_sessions"
    local session_success, session_result = session_manager.set_user_active(username, session_user_type)
    if not session_success then
        ngx.log(ngx.WARN, string.format("Login denied for %s '%s': %s", 
            user_data.user_type, username, session_result))
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
    
    -- Set cookie and return success
    local cookie_value = string.format("access_token=%s; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800", token)
    ngx.header["Set-Cookie"] = cookie_value
    ngx.log(ngx.INFO, "🍪 Setting cookie: " .. cookie_value)
    
    ngx.log(ngx.INFO, string.format("Login: Success for %s '%s' - cookie set, client will handle navigation", 
        user_data.user_type, username))
    
    -- Send success response and exit
    send_json(200, {
        success = true,
        message = "Login successful - cookie set",
        username = username,
        user_type = user_data.user_type,
        cookie_set = true
    })
end

-- =============================================
-- SIMPLIFIED LOGOUT HANDLER (JWT + SESSION DELEGATION)
-- =============================================

function M.handle_logout()
    ngx.log(ngx.INFO, "=== LOGOUT START ===")
    
    local user_type, username, user_data = M.check_user_type()
    
    ngx.log(ngx.INFO, "Logging out user: " .. (username or "unknown") .. " (type: " .. (user_type or "none") .. ")")
    
    -- DELEGATE session clearing to session manager
    if username and user_type ~= "is_none" then
        local session_manager = require "manage_redis_sessions"
        local success, err = session_manager.clear_user_session(username)
        if success then
            ngx.log(ngx.INFO, "Session cleared successfully")
        else
            ngx.log(ngx.WARN, "Failed to clear session: " .. (err or "unknown"))
        end
    end
    
    -- Clear JWT cookies
    local cookie_headers = {
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    }
    ngx.header["Set-Cookie"] = cookie_headers
    
    local logout_user = username or "guest"
    local logout_type = user_type or "is_none"
    
    ngx.log(ngx.INFO, "=== LOGOUT COMPLETE ===")
    ngx.log(ngx.INFO, "User logged out successfully: " .. logout_user .. " (type: " .. logout_type .. ")")
    
    -- Send success response and exit
    send_json(200, {
        success = true,
        message = "Logout successful",
        redirect = "/",
        logged_out_user = logout_user,
        logged_out_type = logout_type
    })
end

-- =============================================
-- SESSION DELEGATION FUNCTIONS
-- =============================================

-- Check if user's session is active (delegates to session manager)
function M.check_is_active(username, user_type)
    local session_manager = require "manage_redis_sessions"
    return session_manager.check_session_active(username, user_type)
end

-- =============================================
-- ADMIN SESSION MANAGEMENT API DELEGATION
-- =============================================

function M.handle_session_status()
    local session_manager = require "manage_redis_sessions"
    return session_manager.handle_session_status()
end

function M.handle_force_logout()
    local session_manager = require "manage_redis_sessions"
    return session_manager.handle_force_logout()
end

function M.handle_all_sessions()
    local session_manager = require "manage_redis_sessions"
    return session_manager.handle_all_sessions()
end

function M.handle_cleanup_sessions()
    local session_manager = require "manage_redis_sessions"
    return session_manager.handle_cleanup_sessions()
end

-- =============================================
-- MODULE EXPORTS (SIMPLIFIED)
-- =============================================

return {
    -- Core auth functions
    check_user_type = M.check_user_type,
    get_user = M.get_user,
    verify_password = verify_password,
    
    -- Auth handlers
    handle_login = M.handle_login,
    handle_logout = M.handle_logout,
    
    -- Session delegation functions
    check_is_active = M.check_is_active,
    
    -- Admin session API delegation
    handle_session_status = M.handle_session_status,
    handle_force_logout = M.handle_force_logout,
    handle_all_sessions = M.handle_all_sessions,
    handle_cleanup_sessions = M.handle_cleanup_sessions,
    
    -- Export Redis helper functions for other modules
    redis_to_lua = redis_to_lua,
    connect_redis = connect_redis
}