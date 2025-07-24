-- =============================================================================
-- nginx/lua/manage_auth.lua - CLEAN PRODUCTION VERSION
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
    -- Redis script: printf '%s%s' $ADMIN_PASSWORD $JWT_SECRET | openssl dgst -sha256 -hex | awk '{print $2}'
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | awk '{print $2}'",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    
    return hash == stored_hash
end

-- =============================================
-- AUTH CHECK FUNCTION - CORE LOGIC WITH GUEST HANDLING
-- =============================================
local function check()
    local token = ngx.var.cookie_access_token
    if not token then
        return "is_none", nil, nil
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        ngx.log(ngx.WARN, "Invalid JWT token: " .. (jwt_obj.reason or "unknown"))
        -- Clear the invalid cookie
        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        return "is_none", nil, nil
    end
    
    local username = jwt_obj.payload.username
    local display_username = jwt_obj.payload.display_username
    
    -- GUEST USER HANDLING: If JWT has display_username but no username, it's a guest
    if display_username and not username then
        -- This is a guest JWT - find which guest user slot is active
        local is_none = require "is_none"
        
        -- Check both guest slots to find the active one for this display name
        for slot = 1, 2 do
            local session = is_none.get_session(slot)
            if session and session.display_name == display_username and session.expires_at > ngx.time() then
                -- Found the active guest session
                local guest_username = "guest_user_" .. slot
                
                -- Get the guest user data from Redis
                local user_data = get_user(guest_username)
                if user_data then
                    -- Update session activity in Lua shared memory
                    is_none.update_session_activity(slot)
                    
                    -- Return guest auth info with display name
                    user_data.display_username = display_username
                    user_data.slot = slot
                    return "is_guest", guest_username, user_data
                end
            end
        end
        
        -- Guest session not found or expired
        ngx.log(ngx.WARN, "Guest JWT for non-existent session: " .. display_username)
        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        return "is_none", nil, nil
    end
    
    -- REGULAR USER HANDLING: JWT has username
    if not username or username == "" then
        ngx.log(ngx.WARN, "JWT token missing username - clearing invalid cookie")
        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        return "is_none", nil, nil
    end
    
    -- For regular users, check Redis
    local user_data = get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "Valid JWT for non-existent user: " .. username .. " - clearing stale cookie")
        -- Clear the stale cookie
        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        return "is_none", nil, nil
    end
    
    -- Update user activity (now safe since username is validated)
    local red = connect_redis()
    if red then
        red:hset("username:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))
        red:close()
    end
    
    -- Return user type based on Redis data (using is_* format)
    if user_data.user_type == "is_admin" then
        return "is_admin", username, user_data
    end
    if user_data.user_type == "is_approved" then
        return "is_approved", username, user_data
    end
    if user_data.user_type == "is_pending" then
        return "is_pending", username, user_data
    end
    if user_data.user_type == "is_guest" then
        return "is_guest", username, user_data
    end
    if user_data.user_type == "is_none" then
        return "is_none", "guest", nil
    end
    
    -- Default fallback
    return "is_none", nil, nil
end

-- =============================================
-- LOGIN HANDLER
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
    
    ngx.log(ngx.INFO, "Login: User found, verifying password")
    
    -- Verify password
    if not verify_password(password, user_data.password_hash) then
        ngx.log(ngx.WARN, "Login: Invalid password for user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    ngx.log(ngx.INFO, "Login: Password verified, generating JWT")
    
    -- Generate JWT based on user type
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
    
    -- Set secure cookie
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800"
    
    ngx.log(ngx.INFO, "Login: Success for user: " .. username .. " (type: " .. user_data.user_type .. ")")
    
    send_json(200, {
        success = true,
        message = "Login successful",
        username = username,
        user_type = user_data.user_type,
        redirect = "/chat"  -- Always redirect to chat after login
    })
end

-- =============================================
-- LOGOUT HANDLER
-- =============================================
local function handle_logout()
    ngx.log(ngx.INFO, "=== LOGOUT START ===")
    
    local user_type, username, user_data = check()  -- Use the existing check function
    
    ngx.log(ngx.INFO, "Logging out user: " .. (username or "unknown") .. " (type: " .. (user_type or "none") .. ")")
    
    -- Clear cookies
    local cookie_headers = {
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    }
    ngx.header["Set-Cookie"] = cookie_headers
    
    -- Guest session cleanup
    if user_type == "is_guest" and user_data and user_data.username then
        local ok, err = pcall(function()
            local red = connect_redis()
            if red then
                -- Clean up guest session
                red:del("guest_session:" .. user_data.username)
                red:del("guest_active_session:" .. user_data.username)
                red:del("username:" .. user_data.username)
                red:close()
                ngx.log(ngx.INFO, "Guest session cleaned up for: " .. user_data.username)
            end
        end)
        if not ok then
            ngx.log(ngx.WARN, "Failed to cleanup guest session: " .. tostring(err))
        end
    end
    
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
-- MODULE EXPORTS
-- =============================================

return {
    check = check,
    get_user = get_user,
    verify_password = verify_password,
    handle_login = handle_login,
    handle_logout = handle_logout,
    -- Export Redis helper functions for other modules
    redis_to_lua = redis_to_lua,
    connect_redis = connect_redis
}