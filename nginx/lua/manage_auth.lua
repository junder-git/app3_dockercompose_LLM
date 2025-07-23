-- =============================================================================
-- nginx/lua/manage_auth.lua - FIXED WITH handle_check_auth FUNCTION
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

-- =============================================
-- AUTH CHECK FUNCTION - CORE LOGIC
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