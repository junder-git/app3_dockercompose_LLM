-- nginx/lua/login.lua - SECURE authentication handler - ONLY source of JWT tokens
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

-- SECURE password hashing - server-side only
local function hash_password(password)
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    return hash
end

-- CRITICAL: ONLY way to get a valid JWT token
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

    -- SECURITY: Rate limit login attempts
    local login_key = "login_attempts:" .. (ngx.var.remote_addr or "unknown")
    local attempts = ngx.shared.guest_sessions:get(login_key) or 0
    
    if attempts >= 5 then
        ngx.log(ngx.WARN, "Too many login attempts from " .. (ngx.var.remote_addr or "unknown"))
        send_json(429, { error = "Too many login attempts, please try again later" })
    end

    -- Get user from Redis - ONLY source of truth
    local user_data = server.get_user(username)
    if not user_data then
        -- Increment failed attempts
        ngx.shared.guest_sessions:set(login_key, attempts + 1, 300) -- 5 minute lockout
        ngx.log(ngx.WARN, "Login attempt for non-existent user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end

    -- SECURITY: Verify password hash
    local password_hash = hash_password(password)
    if user_data.password_hash ~= password_hash then
        -- Increment failed attempts
        ngx.shared.guest_sessions:set(login_key, attempts + 1, 300)
        ngx.log(ngx.WARN, "Invalid password for user: " .. username)
        send_json(401, { error = "Invalid credentials" })
    end

    -- SECURITY: Check if user is approved (admins are auto-approved)
    if user_data.is_approved ~= "true" and user_data.is_admin ~= "true" then
        ngx.log(ngx.INFO, "Login attempt by unapproved user: " .. username)
        send_json(403, { 
            error = "User not approved", 
            message = "Your account is pending administrator approval",
            status = "pending"
        })
    end

    -- SECURITY: Clear failed attempts on successful login
    ngx.shared.guest_sessions:delete(login_key)

    -- CRITICAL: Create JWT token - ONLY place where JWT is created
    local jwt_payload = {
        username = username,
        is_admin = user_data.is_admin == "true",
        is_approved = user_data.is_approved == "true",
        issued_at = ngx.time(),
        exp = ngx.time() + 86400, -- 24 hours
        issuer = "ai.junder.uk"
    }
    
    local jwt_token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = jwt_payload
    })

    if not jwt_token then
        ngx.log(ngx.ERR, "Failed to create JWT token for user: " .. username)
        send_json(500, { error = "Authentication system error" })
    end

    -- SECURITY: Set secure cookie - HttpOnly, SameSite
    ngx.header["Set-Cookie"] = "access_token=" .. jwt_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400"

    -- Update last login in Redis
    server.update_user_activity(username)
    server.increment_login_count(username)

    ngx.log(ngx.INFO, "Successful login for " .. (user_data.is_admin == "true" and "admin" or "user") .. ": " .. username)

    -- RESPONSE: Server confirms what permissions user has
    send_json(200, {
        success = true,
        token = jwt_token,
        user = {
            username = username,
            is_admin = user_data.is_admin == "true",
            is_approved = user_data.is_approved == "true",
            user_type = user_data.is_admin == "true" and "admin" or "approved",
            dashboard_url = user_data.is_admin == "true" and "/admin" or "/dashboard",
            permissions = user_data.is_admin == "true" and 
                {"admin", "approved", "chat", "export", "manage_users"} or 
                {"approved", "chat", "export"}
        },
        login_time = os.date("!%Y-%m-%dT%TZ")
    })
end

-- SECURE: Logout clears JWT
local function handle_logout()
    -- Clear all authentication cookies
    ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
    ngx.header["Set-Cookie"] = "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"

    -- Log logout
    local is_who = require "is_who"
    local user_type, username = is_who.check()
    if username then
        ngx.log(ngx.INFO, "User logged out: " .. username)
    end

    send_json(200, { 
        success = true,
        message = "Logged out successfully",
        redirect = "/"
    })
end

-- SECURE: User info based on JWT validation
local function handle_me()
    local is_who = require "is_who"
    local user_info = is_who.get_user_info()
    
    -- Add extra info for authenticated users
    if user_info.success then
        user_info.server_time = os.date("!%Y-%m-%dT%TZ")
        user_info.session_valid = true
    end
    
    send_json(200, user_info)
end

-- SECURE API routing
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