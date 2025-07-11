local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"
local template = require "template"

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
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    if not user_data or #user_data == 0 then
        send_json(401, { error = "Invalid credentials" })
    end

    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    if user.is_approved ~= "true" then
        send_json(403, { error = "User not approved" })
    end

    -- 🔥 Debug logs
    ngx.log(ngx.ERR, "Password hash in Redis: ", user.password_hash)
    local match = verify_password(password, user.password_hash)
    ngx.log(ngx.ERR, "Password match result: ", tostring(match))

    if not match then
        send_json(401, { error = "Invalid credentials" })
    end

    local jwt_token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = {
            username = username,
            exp = ngx.time() + 86400
        }
    })

    ngx.header["Set-Cookie"] = "access_token=" .. jwt_token .. "; Path=/; HttpOnly"
    send_json(200, { token = jwt_token })
end

return {
    handle_login = handle_login
}
