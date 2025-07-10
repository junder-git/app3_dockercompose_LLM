local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

-- Config
local REDIS_HOST = os.getenv("REDIS_HOST") or "127.0.0.1"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-jwt-key-change-this-in-production-min-32-chars"

-- Utility
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
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        send_json(500, { error = "Internal server error" })
    end
    return red
end

local function validate_username(username)
    if not username or #username < 3 then
        return false, "Invalid username"
    end
    return true, username
end

local function validate_password(password)
    local min_len = tonumber(os.getenv("MIN_PASSWORD_LENGTH")) or 6
    if not password or #password < min_len then
        return false, "Password must be at least " .. min_len .. " characters"
    end
    return true, password
end

local function verify_password(password, stored_hash)
    if not password or not stored_hash then
        return false
    end

    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
        password:gsub("'", "'\"'\"'"), JWT_SECRET:gsub("'", "'\"'\"'"))

    local handle = io.popen(hash_cmd)
    local computed_hash = handle:read("*a"):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
    handle:close()

    ngx.log(ngx.ERR, "DEBUG: Computed hash: " .. computed_hash)
    ngx.log(ngx.ERR, "DEBUG: Stored hash: " .. stored_hash)

    return computed_hash == stored_hash
end

local function generate_jwt(user_id, username)
    local jwt_token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = {
            user_id = user_id,
            username = username,
            exp = ngx.time() + 7 * 24 * 3600  -- 7 days
        }
    })
    return jwt_token
end

local function handle_login()
    ngx.req.read_body()
    local data = cjson.decode(ngx.var.request_body or "{}")

    local valid_username, username = validate_username(data.username)
    if not valid_username then
        send_json(400, { error = username })
        return
    end

    local valid_password, password = validate_password(data.password)
    if not valid_password then
        send_json(400, { error = password })
        return
    end

    local red = connect_redis()
    local res, err = red:hgetall("user:" .. username)
    if not res or #res == 0 then
        send_json(401, { error = "Invalid credentials" })
        return
    end

    local user = {}
    for i = 1, #res, 2 do
        user[res[i]] = res[i + 1]
    end

    if not user.username or user.username ~= username then
        send_json(401, { error = "Invalid credentials" })
        return
    end

    if user.is_approved ~= "true" then
        send_json(403, { error = "Account pending approval" })
        return
    end

    if not verify_password(password, user.password_hash) then
        send_json(401, { error = "Invalid credentials" })
        return
    end

    local token = generate_jwt(user.id or "unknown", username)
    send_json(200, { success = true, token = token })
end

-- Entry point dispatcher
local action = ngx.var.uri:match("/api/auth/(%w+)$")
if action == "login" then
    handle_login()
else
    send_json(404, { error = "Not found" })
end
