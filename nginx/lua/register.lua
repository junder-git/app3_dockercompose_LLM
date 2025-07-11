local cjson = require "cjson"
local redis = require "resty.redis"

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
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        send_json(500, { error = "Failed to connect to Redis" })
    end
    return red
end

function handle_register()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing body" })
    end

    local data = cjson.decode(body)
    local username = data.username
    local password = data.password

    if not username or not password then
        send_json(400, { error = "Username and password required" })
    end

    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()

    local red = connect_redis()
    local user_key = "user:" .. username

    local exists = red:exists(user_key)
    if exists == 1 then
        send_json(409, { error = "User already exists" })
    end

    local user_data = {
        id = "user:" .. username,
        username = username,
        password_hash = hash,
        is_admin = "false",
        is_approved = "false",
        created_at = os.date("!%Y-%m-%dT%TZ")
    }

    for k, v in pairs(user_data) do
        red:hset(user_key, k, v)
    end

    send_json(200, { success = true, message = "User registered. Wait for admin approval." })
end

return {
    handle_register = handle_register
}
