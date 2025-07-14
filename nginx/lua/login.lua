-- nginx/lua/login.lua - Authentication handler
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

    -- Get user from Redis
    local user_data = server.get_user(username)
    if not user_data then
        send_json(401, { error = "Invalid credentials" })
    end

    -- Verify password
    local password_hash = hash_password(password)
    if user_data.password_hash ~= password_hash then
        send_json(401, { error = "Invalid credentials" })
    end

    -- Check if user is approved (admins always approved)
    if user_data.is_approved ~= "true" and user_data.is_admin ~= "true" then
        send_json(403, { error = "User not approved" })
    end

    -- Create JWT token
    local jwt_token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = {
            username = username,
            is_admin = user_data.is_admin == "true",
            is_approved = user_data.is_approved == "true",
            exp = ngx.time() + 86400 -- 24 hours
        }
    })

    -- Set cookie
    ngx.header["Set-Cookie"] = "access_token=" .. jwt_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400"

    -- Update last login
    server.update_user_activity(username)

    send_json(200, {
        token = jwt_token,
        username = username,
        is_admin = user_data.is_admin == "true",
        is_approved = user_data.is_approved == "true"
    })
end

local function handle_logout()
    -- Clear cookies
    ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
    ngx.header["Set-Cookie"] = "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"

    send_json(200, { message = "Logged out successfully" })
end

local function handle_me()
    local is_who = require "is_who"
    local user_info = is_who.get_user_info()
    send_json(200, user_info)
end

-- Route handler
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