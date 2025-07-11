local cjson = require "cjson"
local jwt = require "resty.jwt"
local redis = require "resty.redis"

local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-jwt-key-change-this-in-production-min-32-chars"
local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379

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

local function require_admin()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { error = "No token provided" })
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { error = "Invalid token" })
    end

    local username = jwt_obj.payload.username

    local red = connect_redis()
    local user_key = "user:" .. username
    local user_data, err = red:hgetall(user_key)
    if not user_data or #user_data == 0 then
        send_json(403, { error = "User not found" })
    end

    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    if user.is_admin ~= "true" then
        send_json(403, { error = "Admin privileges required" })
    end

    return username
end

function handle_admin_panel()
    local username = require_admin()
    send_json(200, { success = true, message = "Welcome, admin " .. username })
end

return {
    handle_admin_panel = handle_admin_panel
}
