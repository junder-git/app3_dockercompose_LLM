-- =============================================================================
-- nginx/lua/auth.lua - FIXED LOGIN/LOGOUT WITH CORRECT REDIS STRUCTURE
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

-- FIXED: Get user function that properly handles Redis structure
local function get_user(username)
    if not username or username == "" then
        return nil
    end
    
    local red = connect_redis()
    if not red then return nil end
    
    local user_key = "username:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        red:close()
        return nil
    end
    
    -- Convert Redis hash to Lua table
    local user = {}
    for i = 1, #user_data, 2 do
        local key = user_data[i]
        local value = redis_to_lua(user_data[i + 1])
        
        -- FIXED: Handle keys with trailing colons from your Redis structure
        if string.sub(key, -1) == ":" then
            key = string.sub(key, 1, -2)  -- Remove trailing colon
        end
        
        user[key] = value
    end
    
    red:close()
    
    -- Validate required fields
    if not user.username or not user.password_hash then
        return nil
    end
    
    return user
end

-- FIXED: Password verification function
local function verify_password(password, stored_hash)
    if not password or not stored_hash then
        return false
    end
    
    -- Use the same hashing method as your setup script
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | awk '{print $2}'",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    
    return hash == stored_hash
end

-- FIXED: Generate JWT for guest users
local function generate_guest_jwt(username, guest_slot_number)
    local payload = {
        username = username,
        user_type = "is_guest",
        guest_slot_number = guest_slot_number,
        iat = ngx.time(),
        exp = ngx.time() + 1800  -- 30 minutes
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    return token
end
-- =============================================
-- LOGIN HANDLER
-- =============================================
local function handle_login()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        send_json(400, { error = "No request body" })
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        send_json(400, { error = "Invalid JSON" })
    end
    
    local username = data.username
    local password = data.password
    
    if not username or not password then
        send_json(400, { error = "Username and password required" })
    end
    
    -- Get user from Redis
    local user_data = get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "Login attempt for non-existent user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    -- Verify password
    if not verify_password(password, user_data.password_hash) then
        ngx.log(ngx.WARN, "Invalid password for user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
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
    
    ngx.log(ngx.INFO, "User logged in successfully: " .. username .. " (type: " .. user_data.user_type .. ")")
    
    send_json(200, {
        success = true,
        message = "Login successful",
        username = username,
        user_type = user_data.user_type
    })
end

-- =============================================
-- LOGOUT HANDLER
-- =============================================

local function handle_logout()
    ngx.log(ngx.INFO, "=== LOGOUT START ===")
    
    local user_type, username, user_data = check()
    
    ngx.log(ngx.INFO, "Logging out user: " .. (username or "unknown") .. " (type: " .. (user_type or "none") .. ")")
    
    -- Clear cookies
    local cookie_headers = {
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    }
    ngx.header["Set-Cookie"] = cookie_headers
    
    -- Guest session cleanup
    if user_type == "is_guest" and user_data and user_data.guest_slot_number then
        local ok, err = pcall(function()
            local is_guest = require "is_guest"
            if is_guest.cleanup_guest_session then
                is_guest.cleanup_guest_session(user_data.guest_slot_number)
                ngx.log(ngx.INFO, "Guest session cleaned up for slot: " .. user_data.guest_slot_number)
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
-- AUTH CHECK HANDLER
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
    local user_type_claim = jwt_obj.payload.user_type
    -- Handle guest users differently
    if user_type_claim == "is_guest" or user_type_claim == "guest" then
        -- For guest users, validate against guest session system
        local ok, is_guest = pcall(require, "is_guest")
        if ok and is_guest.validate_guest_session then
            local guest_session, error_msg = is_guest.validate_guest_session(token)
            if guest_session then
                return "is_guest", guest_session.display_username or guest_session.username, guest_session
            else
                ngx.log(ngx.WARN, "Guest session validation failed: " .. (error_msg or "unknown"))
                -- Clear the stale guest cookie
                ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
                return "is_none", nil, nil
            end
        else
            ngx.log(ngx.WARN, "Guest module not available")
            -- Clear the cookie since we can't validate it
            ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
            return "is_none", nil, nil
        end
    end
    -- For regular users, check Redis
    local user_data = get_user(username)
    if not user_data or user_data == "is_none" then
        ngx.log(ngx.WARN, "Valid JWT for non-existent user: " .. username .. " - clearing stale cookie")
        -- Clear the stale cookie
        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        return "is_none", nil, nil
    end
    -- Update user activity
    local red = connect_redis()
    if red then
        red:hset("username:" .. username, "last_active:", os.date("!%Y-%m-%dT%TZ"))
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
    if user_data.user_type == "is_none" then
        return "is_none", "guest", nil
    end
    -- Default fallback
    return "is_none", nil, nil
end
-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    check = check,
    get_user = get_user,
    verify_password = verify_password,
    handle_login = handle_login,
    handle_logout = handle_logout
}