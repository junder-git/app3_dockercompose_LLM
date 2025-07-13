-- nginx/lua/auth.lua - Secured with proper logout
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST")
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT"))
local JWT_SECRET = os.getenv("JWT_SECRET")

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
        send_json(500, { error = "Internal server error" })
    end
    return red
end

local function verify_password(password, stored_hash)
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local computed_hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    return computed_hash == stored_hash
end

local function get_user_info(red, username)
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    if not user_data or #user_data == 0 then
        return nil
    end

    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end
    
    return user
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

    local red = connect_redis()
    local user = get_user_info(red, username)
    if not user then
        send_json(401, { error = "Invalid credentials" })
    end

    if user.is_approved ~= "true" then
        send_json(403, { error = "User not approved" })
    end

    if not verify_password(password, user.password_hash) then
        send_json(401, { error = "Invalid credentials" })
    end

    -- Update last active timestamp
    red:hset("user:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))

    -- Create JWT with minimal payload - NO sensitive data
    local jwt_token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = {
            username = username,
            exp = ngx.time() + 86400  -- 24 hours
            -- Removed is_admin - server will check this from Redis when needed
        }
    })

    -- Set secure HTTP-only cookie
    ngx.header["Set-Cookie"] = "access_token=" .. jwt_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400"
    
    send_json(200, { 
        token = jwt_token,
        success = true
    })
end

-- Simplified /me endpoint - only returns what client needs
local function handle_me()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { success = false, error = "No token" })
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { success = false, error = "Invalid token" })
    end

    local username = jwt_obj.payload.username
    
    -- Get minimal user info from Redis
    local red = connect_redis()
    local user_key = "user:" .. username
    local is_approved = red:hget(user_key, "is_approved")
    local is_admin = red:hget(user_key, "is_admin")
    
    if is_approved ~= "true" then
        send_json(403, { success = false, error = "User not approved" })
    end

    -- Only send what the client actually needs
    send_json(200, {
        success = true,
        username = username,
        -- Only send admin status for navigation purposes
        -- All actual admin checks are done server-side
        is_admin = is_admin == "true"
    })
end

-- NEW: Proper logout endpoint that clears cookies
local function handle_logout()
    -- Clear the cookie properly on server side
    ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    
    -- Also clear any other auth cookies that might exist
    ngx.header["Set-Cookie"] = {
        "access_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        "session=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        "auth_token=; Path=/; HttpOnly; SameSite=Lax; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
    }
    
    send_json(200, { 
        success = true, 
        message = "Logged out successfully" 
    })
end

return {
    handle_login = handle_login,
    handle_me = handle_me,
    handle_logout = handle_logout
}