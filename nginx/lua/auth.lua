-- =============================================================================
-- nginx/lua/auth.lua - LOGIN/LOGOUT WITH JWT BLACKLISTING
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local redis = require "resty.redis"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- Server-side JWT verification with enhanced guest validation
local function check()
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local username = jwt_obj.payload.username
            local user_type_claim = jwt_obj.payload.user_type
            
            local user_data = server.get_user(username)
            
            if user_data then
                if user_data.is_guest_account == "true" or user_type_claim == "guest" then
                    local is_guest = require "is_guest"
                    local guest_session, error_msg = is_guest.validate_guest_session(token)
                    if guest_session then
                        return "guest", guest_session.display_username or guest_session.username, guest_session
                    else
                        ngx.log(ngx.WARN, "Guest session validation failed: " .. (error_msg or "unknown"))
                        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
                        return "none", nil, nil
                    end
                else
                    server.update_user_activity(username)
                    
                    if user_data.is_admin == "true" then
                        return "admin", username, user_data
                    elseif user_data.is_approved == "true" then
                        return "approved", username, user_data
                    else
                        return "authenticated", username, user_data
                    end
                end
            else
                ngx.log(ngx.WARN, "Valid JWT for non-existent user: " .. username)
                return "none", nil, nil
            end
        else
            ngx.log(ngx.WARN, "Invalid JWT token: " .. (jwt_obj.reason or "unknown"))
        end
    end
    
    return "none", nil, nil
end

-- =============================================
-- JWT BLACKLISTING FUNCTIONS
-- =============================================

-- Blacklist JWT for 5 seconds to prevent logout race condition
local function blacklist_jwt_token(token)
    if not token then 
        return false, "No token provided"
    end
    
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.log(ngx.WARN, "Failed to connect to Redis for JWT blacklisting: " .. (err or "unknown"))
        return false, "Redis connection failed"
    end
    
    -- Create a hash of the token (don't store full JWT for security)
    local token_hash = ngx.md5(token)
    local blacklist_key = "blacklisted_jwt:" .. token_hash
    
    -- Store in Redis with 5 second TTL (just to prevent race condition)
    red:set(blacklist_key, cjson.encode({
        blacklisted_at = ngx.time(),
        reason = "logout_race_prevention"
    }))
    red:expire(blacklist_key, 5)  -- 5 seconds only
    
    red:close()
    ngx.log(ngx.INFO, "Blacklisted JWT for 5 seconds to prevent logout race condition")
    return true, "JWT blacklisted for 5 seconds"
end

-- =============================================
-- LOGIN/LOGOUT HANDLERS
-- =============================================

local function handle_login()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        send_json(400, { error = "No request body" })
    end
    
    local data = cjson.decode(body)
    local username = data.username
    local password = data.password
    
    if not username or not password then
        send_json(400, { error = "Username and password required" })
    end
    
    -- Validate credentials
    local user_data = server.get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "Login attempt for non-existent user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    local valid = server.verify_password(password, user_data.password_hash)
    if not valid then
        ngx.log(ngx.WARN, "Invalid password for user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end
    
    -- Update login activity
    server.update_user_activity(username)
    
    -- Generate JWT
    local payload = {
        username = username,
        iat = ngx.time(),
        exp = ngx.time() + 86400 * 7  -- 7 days
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    -- Set secure cookie
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800"
    
    ngx.log(ngx.INFO, "User logged in successfully: " .. username .. ".")
    
    send_json(200, {
        success = true,
        message = "Login successful",
        username = username
    })
end

local function handle_logout()
    ngx.log(ngx.INFO, "=== LOGOUT START ===")
    
    local user_type, username, user_data = check()
    
    ngx.log(ngx.INFO, "Logging out user: " .. (username or "unknown") .. " (type: " .. (user_type or "none") .. ")")
    
    -- BLACKLIST THE JWT TOKEN IMMEDIATELY (5 seconds to prevent race condition)
    local token = ngx.var.cookie_access_token
    if token then
        local ok, err = pcall(function()
            blacklist_jwt_token(token)
        end)
        if not ok then
            ngx.log(ngx.WARN, "Failed to blacklist JWT: " .. tostring(err))
        end
    end
    
    -- Clear cookies with multiple approaches
    local cookie_headers = {
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        "guest_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    }
    ngx.header["Set-Cookie"] = cookie_headers
    
    -- Anti-cache headers
    ngx.header["Cache-Control"] = "no-cache, no-store, must-revalidate"
    ngx.header["Pragma"] = "no-cache"
    ngx.header["Expires"] = "0"
    
    -- Guest session cleanup
    if user_type == "guest" and user_data and user_data.slot_number then
        local ok, err = pcall(function()
            local is_guest = require "is_guest"
            if is_guest.cleanup_guest_session then
                is_guest.cleanup_guest_session(user_data.slot_number)
                ngx.log(ngx.INFO, "Guest session cleaned up for slot: " .. user_data.slot_number)
            end
        end)
        if not ok then
            ngx.log(ngx.WARN, "Failed to cleanup guest session: " .. tostring(err))
        end
    end
    
    local logout_user = username or "guest"
    local logout_type = user_type or "none"
    
    ngx.log(ngx.INFO, "=== LOGOUT COMPLETE ===")
    ngx.log(ngx.INFO, "User logged out successfully: " .. logout_user .. " (type: " .. logout_type .. ")")
    
    send_json(200, {
        success = true,
        message = "Logout successful",
        redirect = "/",
        logged_out_user = logout_user,
        logged_out_type = logout_type,
        timestamp = os.date("!%Y-%m-%dT%TZ"),
        jwt_blacklisted = (token ~= nil)
    })
end

local function handle_check_auth()
    local user_type, username, user_data = check()
    
    if user_type == "none" then
        send_json(200, { 
            success = false, 
            user_type = "is_none", 
            authenticated = false, 
            message = "Not authenticated" 
        })
    end
    
    local response = {
        success = true,
        username = username,
        user_type = user_type,
        authenticated = true
    }
    
    if user_type == "guest" and user_data then
        response.message_limit = user_data.max_messages or 10
        response.messages_used = user_data.message_count or 0
        response.messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
        response.session_remaining = (user_data.expires_at or 0) - ngx.time()
        response.slot_number = user_data.slot_number
        response.priority = user_data.priority or 3
    end
    
    send_json(200, response)
end

local function handle_check_auth()
    local user_type, username, user_data = check()
    
    if user_type == "none" then
        send_json(200, { 
            success = false, 
            user_type = "is_none", 
            authenticated = false, 
            message = "Not authenticated" 
        })
    end
    
    local response = {
        success = true,
        username = username,
        user_type = user_type,
        authenticated = true
    }
    
    if user_type == "guest" and user_data then
        response.message_limit = user_data.max_messages or 10
        response.messages_used = user_data.message_count or 0
        response.messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
        response.session_remaining = (user_data.expires_at or 0) - ngx.time()
        response.slot_number = user_data.slot_number
        response.priority = user_data.priority or 3
    end
    
    send_json(200, response)
end

local function handle_check_auth()
    local user_type, username, user_data = check()
    
    if user_type == "none" then
        send_json(200, { 
            success = false, 
            user_type = "is_none", 
            authenticated = false, 
            message = "Not authenticated" 
        })
    end
    
    local response = {
        success = true,
        username = username,
        user_type = user_type,
        authenticated = true
    }
    
    if user_type == "guest" and user_data then
        response.message_limit = user_data.max_messages or 10
        response.messages_used = user_data.message_count or 0
        response.messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
        response.session_remaining = (user_data.expires_at or 0) - ngx.time()
        response.slot_number = user_data.slot_number
        response.priority = user_data.priority or 3
    end
    
    send_json(200, response)
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    check = check,
    handle_login = handle_login,
    handle_logout = handle_logout,
    handle_check_auth = handle_check_auth,
    blacklist_jwt_token = blacklist_jwt_token
}