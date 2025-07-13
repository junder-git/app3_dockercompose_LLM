-- nginx/lua/auth.lua - Enhanced auth module
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"
local unified_auth = require "unified_auth"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        return nil, "Redis connection failed: " .. (err or "unknown")
    end
    return red, nil
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

    local red, err = connect_redis()
    if not red then
        send_json(500, { error = "Service temporarily unavailable" })
    end

    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)

    if not user_data or #user_data == 0 then
        send_json(401, { error = "Invalid credentials" })
    end

    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    -- Verify password
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()

    if user.password_hash ~= hash then
        send_json(401, { error = "Invalid credentials" })
    end

    -- Check if user is approved (admins always approved)
    if user.is_approved ~= "true" and user.is_admin ~= "true" then
        send_json(403, { error = "User not approved" })
    end

    -- Create JWT token
    local jwt_token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = {
            username = username,
            is_admin = user.is_admin == "true",
            is_approved = user.is_approved == "true",
            exp = ngx.time() + 86400 -- 24 hours
        }
    })

    -- Set cookie
    ngx.header["Set-Cookie"] = "access_token=" .. jwt_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400"

    -- Update last login
    red:hset(user_key, "last_login", os.date("!%Y-%m-%dT%TZ"))

    send_json(200, {
        token = jwt_token,
        username = username,
        is_admin = user.is_admin == "true",
        is_approved = user.is_approved == "true"
    })
end

local function handle_logout()
    -- Clear the access token cookie
    ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
    
    -- Also clear guest token if present
    ngx.header["Set-Cookie"] = "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"

    send_json(200, { message = "Logged out successfully" })
end

local function handle_me()
    -- Use unified auth to check current user status
    local user_type, username, slot_num = unified_auth.check_user_access()
    
    if user_type == "admin" then
        send_json(200, {
            success = true,
            username = username,
            user_type = "admin",
            is_admin = true,
            is_approved = true
        })
    elseif user_type == "user" then
        send_json(200, {
            success = true,
            username = username,
            user_type = "user",
            is_admin = false,
            is_approved = true
        })
    elseif user_type == "guest" then
        local limits = unified_auth.get_guest_limits(slot_num)
        send_json(200, {
            success = true,
            username = username,
            user_type = "guest",
            is_guest = true,
            slot_num = slot_num,
            limits = limits
        })
    else
        send_json(401, {
            success = false,
            error = "Not authenticated"
        })
    end
end

-- Access control functions for use in nginx access_by_lua_block
local function check_admin_user()
    local is_admin, username = unified_auth.check_admin_access()
    
    if not is_admin then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Admin access required"}')
        ngx.exit(403)
    end
    
    ngx.var.auth_username = username
    return username
end

local function check_approved_user()
    local is_approved, username = unified_auth.check_approved_user()
    
    if not is_approved then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "User access required"}')
        ngx.exit(403)
    end
    
    ngx.var.auth_username = username
    return username
end

return {
    handle_login = handle_login,
    handle_logout = handle_logout,
    handle_me = handle_me,
    check_admin_user = check_admin_user,
    check_approved_user = check_approved_user
}