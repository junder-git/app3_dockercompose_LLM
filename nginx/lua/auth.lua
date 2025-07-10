local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-jwt-key-change-this-in-production-min-32-chars"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function connect_redis()
    ngx.log(ngx.ERR, "DEBUG: Connecting to Redis at ", REDIS_HOST, ":", REDIS_PORT)
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        send_json(500, { error = "Internal server error" })
    end
    ngx.log(ngx.ERR, "DEBUG: Successfully connected to Redis")
    return red
end

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

function handle_login()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local data = cjson.decode(body)
    local username = data.username
    local password = data.password

    if not username or not password then
        send_json(400, { error = "Username and password required" })
    end

    local red = connect_redis()
    local user_key = "user:" .. username
    local user_data_raw, err = red:hgetall(user_key)
    if not user_data_raw or #user_data_raw == 0 then
        send_json(401, { error = "Invalid credentials" })
    end

    local user_data = {}
    for i = 1, #user_data_raw, 2 do
        user_data[user_data_raw[i]] = user_data_raw[i + 1]
    end

    ngx.log(ngx.ERR, "DEBUG: User data dump: ", cjson.encode(user_data))

    if not verify_password(password, user_data.password_hash) then
        ngx.log(ngx.ERR, "Password verification failed for user: ", username)
        send_json(401, { error = "Invalid credentials" })
    end

    if user_data.is_approved ~= "true" then
        send_json(403, { error = "User not approved" })
    end

    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = {
            username = username,
            id = user_data.id,
            is_admin = user_data.is_admin,
            exp = ngx.time() + 7 * 24 * 3600
        }
    })

    ngx.header["Set-Cookie"] = "token=" .. token .. "; Path=/; HttpOnly"
    ngx.log(ngx.ERR, "DEBUG: Set-Cookie header set with token")

    send_json(200, { success = true, token = token })
end

function handle_check()
    local token = ngx.var.cookie_token
    if not token then
        send_json(401, { success = false, error = "No token" })
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { success = false, error = "Invalid token" })
    end

    send_json(200, { success = true })
end
