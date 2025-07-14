-- nginx/lua/login.lua - SECURE authentication with JWT creation
local cjson = require "cjson"
local jwt = require "resty.jwt"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function hash_password(password)
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    return hash
end

-- SECURE LOGIN - Only way to get valid JWT
local function handle_login()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username
    local password = data.password

    if not username or not password then
        send_json(400, { error = "Username and password required" })
    end

    -- CRITICAL: Get user from Redis - SERVER IS SOURCE OF TRUTH
    local user_data = server.get_user(username)
    if not user_data then
        ngx.log(ngx.WARN, "Login attempt for non-existent user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end

    -- CRITICAL: Verify password
    local password_hash = hash_password(password)
    if user_data.password_hash ~= password_hash then
        ngx.log(ngx.WARN, "Invalid password for user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end

    -- CRITICAL: Check if user is approved (admins always approved)
    if user_data.is_approved ~= "true" and user_data.is_admin ~= "true" then
        ngx.log(ngx.WARN, "Login attempt by unapproved user: " .. username)
        send_json(403, { 
            error = "User not approved",
            message = "Your account is pending administrator approval"
        })
    end

    -- SECURITY: JWT payload contains MINIMAL data - server re-validates everything
    local jwt_token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = {
            username = username,
            iat = ngx.time(),  -- Issued at
            exp = ngx.time() + 86400, -- 24 hours
            -- DO NOT PUT PERMISSIONS IN JWT - server validates from Redis
            version = 1 -- For token invalidation if needed
        }
    })

    -- SECURITY: HttpOnly cookie prevents XSS
    ngx.header["Set-Cookie"] = "access_token=" .. jwt_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400; Secure=" .. 
        (ngx.var.scheme == "https" and "true" or "false")

    -- Update last login in Redis - FIXED FUNCTION CALLS
    server.update_user_activity(username)
    server.update_user_login(username, ngx.var.remote_addr)

    ngx.log(ngx.INFO, "Successful login for user: " .. username .. " (admin: " .. (user_data.is_admin or "false") .. ")")

    -- RESPONSE: Minimal data - client will call /api/auth/me for full permissions
    send_json(200, {
        success = true,
        token = jwt_token,
        username = username,
        message = "Login successful",
        dashboard_url = user_data.is_admin == "true" and "/admin" or "/dashboard"
    })
end

-- SECURE LOGOUT - Invalidate session
local function handle_logout()
    -- Clear all auth cookies
    ngx.header["Set-Cookie"] = {
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
    }

    ngx.log(ngx.INFO, "User logged out from IP: " .. (ngx.var.remote_addr or "unknown"))

    send_json(200, { 
        success = true,
        message = "Logged out successfully" 
    })
end

-- SECURE USER INFO - Re-validates everything from Redis
local function handle_me()
    local is_who = require "is_who"
    
    -- CRITICAL: Always re-validate from Redis, never trust JWT alone
    local user_info = is_who.get_user_info()
    
    -- Add session info for client
    if user_info.success then
        user_info.session_info = {
            login_time = ngx.time(),
            ip_address = ngx.var.remote_addr,
            user_agent = string.sub(ngx.var.http_user_agent or "", 1, 100)
        }
    end
    
    send_json(200, user_info)
end

-- SECURE API ROUTING - Authentication endpoints
local function handle_auth_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method

    if uri == "/api/auth/login" and method == "POST" then
        handle_login()
    elseif uri == "/api/auth/logout" and method == "POST" then
        handle_logout()
    elseif uri == "/api/auth/me" and method == "GET" then
        handle_me()
    else
        send_json(404, { error = "Auth endpoint not found" })
    end
end

return {
    handle_auth_api = handle_auth_api,
    handle_login = handle_login,
    handle_logout = handle_logout,
    handle_me = handle_me
}