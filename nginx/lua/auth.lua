local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

-- Config
local REDIS_HOST = os.getenv("REDIS_HOST") or "127.0.0.1"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-key"

-- Utility function to send JSON and exit
local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- Connect to Redis
local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)

    ngx.log(ngx.ERR, "DEBUG: Connecting to Redis at ", REDIS_HOST, ":", REDIS_PORT)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)

    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        send_json(500, { error = "Internal server error" })
    else
        ngx.log(ngx.ERR, "Successfully connected to Redis")
    end

    return red
end

-- Verify password
local function verify_password(password, stored_hash)
    local combined = password .. JWT_SECRET
    local hash_cmd = string.format("printf '%%s' '%s' | openssl dgst -sha256 -hex | awk '{print $2}'", combined)
    local handle = io.popen(hash_cmd)
    local computed_hash = handle:read("*a"):gsub("\n", "")
    handle:close()

    ngx.log(ngx.ERR, "DEBUG: Computed hash: ", computed_hash)
    ngx.log(ngx.ERR, "DEBUG: Stored hash: ", stored_hash)

    return computed_hash == stored_hash
end

-- Generate JWT
local function generate_jwt(id, username)
    local jwt_obj = jwt:sign(
        JWT_SECRET,
        {
            header = { typ = "JWT", alg = "HS256" },
            payload = {
                id = id,
                username = username,
                exp = ngx.time() + 86400  -- 1 day expiry
            }
        }
    )
    return jwt_obj
end

-- Login handler
local function handle_login()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local body = cjson.decode(data or "{}")

    local username = body.username
    local password = body.password

    if not username or not password then
        ngx.log(ngx.ERR, "Missing username or password")
        send_json(400, { error = "Missing credentials" })
    end

    local red = connect_redis()
    local user_key = "user:" .. username

    local user, err = red:hgetall(user_key)
    if not user or #user == 0 then
        ngx.log(ngx.ERR, "User not found: ", username)
        send_json(401, { error = "Invalid credentials" })
    end

    -- Convert flat list to table
    local user_data = {}
    for i = 1, #user, 2 do
        user_data[user[i]] = user[i + 1]
    end

    ngx.log(ngx.ERR, "DEBUG: User data dump: ", cjson.encode(user_data))

    if user_data.is_approved ~= "true" then
        ngx.log(ngx.ERR, "User not approved")
        send_json(403, { error = "User not approved" })
    end

    if not verify_password(password, user_data.password_hash) then
        ngx.log(ngx.ERR, "Password verification failed for user: ", username)
        send_json(401, { error = "Invalid credentials" })
    end

    local token = generate_jwt(user_data.id or "unknown", username)

    ngx.header["Set-Cookie"] = "token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax"
    ngx.log(ngx.ERR, "DEBUG: Set-Cookie header set with token")

    send_json(200, { success = true, token = token })
end

-- Call login handler if needed
handle_login()
