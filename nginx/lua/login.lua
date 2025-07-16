-- =============================================================================
-- nginx/lua/login.lua - LOGIN/LOGOUT WITH JWT BLACKLISTING
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
-- NAV RENDERING FUNCTION - Uses is_public
-- =============================================

local function render_nav_for_user(user_type, username, user_data)
    local is_public = require "is_public"
    return is_public.render_nav(user_type or "public", username or "Anonymous", user_data)
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
    
    -- Determine user type for nav rendering
    local user_type
    if user_data.is_admin == "true" then
        user_type = "admin"
    elseif user_data.is_approved == "true" then
        user_type = "approved"
    else
        user_type = "authenticated"
    end
    
    -- Render nav for the logged-in user
    local nav_html = render_nav_for_user(user_type, username, user_data)
    
    ngx.log(ngx.INFO, "User logged in successfully: " .. username .. " (type: " .. user_type .. ")")
    
    send_json(200, {
        success = true,
        message = "Login successful",
        user = {
            username = username,
            user_type = user_type,
            is_admin = (user_type == "admin"),
            is_approved = (user_type == "approved" or user_type == "admin"),
            is_pending = (user_type == "authenticated")
        },
        nav_html = nav_html,
        redirect = user_type == "authenticated" and "/pending" or "/chat"
    })
end

local function handle_logout()
    ngx.log(ngx.INFO, "=== LOGOUT START ===")
    
    -- Get current user info before logout for logging
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
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
    
    -- Render nav for anonymous user
    local nav_html = render_nav_for_user("none", "Anonymous", nil)
    
    local logout_user = username or "anonymous"
    local logout_type = user_type or "none"
    
    ngx.log(ngx.INFO, "=== LOGOUT COMPLETE ===")
    ngx.log(ngx.INFO, "User logged out successfully: " .. logout_user .. " (type: " .. logout_type .. ")")
    
    send_json(200, {
        success = true,
        message = "Logout successful",
        nav_html = nav_html,
        redirect = "/",
        logged_out_user = logout_user,
        logged_out_type = logout_type,
        timestamp = os.date("!%Y-%m-%dT%TZ"),
        jwt_blacklisted = (token ~= nil)
    })
end

local function handle_check_auth()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type == "none" then
        -- Return nav for anonymous user
        local nav_html = render_nav_for_user("none", "Anonymous", nil)
        send_json(200, {
            authenticated = false,
            user_type = "none",
            nav_html = nav_html,
            message = "Not authenticated"
        })
    else
        -- Return nav for authenticated user
        local nav_html = render_nav_for_user(user_type, username, user_data)
        send_json(200, {
            authenticated = true,
            username = username,
            user_type = user_type,
            is_admin = (user_type == "admin"),
            is_approved = (user_type == "approved" or user_type == "admin"),
            is_guest = (user_type == "guest"),
            is_pending = (user_type == "authenticated"),
            nav_html = nav_html,
            message = "Authenticated as " .. user_type
        })
    end
end

-- Handle nav refresh endpoint
local function handle_nav_refresh()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    local nav_html = render_nav_for_user(user_type or "none", username or "Anonymous", user_data)
    
    send_json(200, {
        success = true,
        nav_html = nav_html,
        user_type = user_type or "none",
        username = username or "Anonymous",
        timestamp = os.date("!%Y-%m-%dT%TZ")
    })
end

-- =============================================
-- API ROUTING
-- =============================================

local function handle_auth_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/auth/login" and method == "POST" then
        handle_login()
    elseif uri == "/api/auth/logout" and method == "POST" then
        handle_logout()
    elseif uri == "/api/auth/check" and method == "GET" then
        handle_check_auth()
    elseif uri == "/api/auth/nav" and method == "GET" then
        handle_nav_refresh()
    else
        send_json(404, { 
            error = "Auth endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/auth/login - User login",
                "POST /api/auth/logout - User logout", 
                "GET /api/auth/check - Check authentication status",
                "GET /api/auth/nav - Refresh navigation"
            }
        })
    end
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    handle_auth_api = handle_auth_api,
    handle_login = handle_login,
    handle_logout = handle_logout,
    handle_check_auth = handle_check_auth,
    handle_nav_refresh = handle_nav_refresh,
    render_nav_for_user = render_nav_for_user,
    blacklist_jwt_token = blacklist_jwt_token
}