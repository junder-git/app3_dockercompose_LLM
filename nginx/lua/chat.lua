local cjson = require "cjson"
local jwt = require "resty.jwt"

local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-jwt-key-change-this-in-production-min-32-chars"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function require_auth()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { error = "No token provided" })
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { error = "Invalid token" })
    end

    return jwt_obj.payload.username
end

function handle_chat_message()
    local username = require_auth()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing body" })
    end
    local data = cjson.decode(body)
    local message = data.message or ""
    -- You can implement further logic here, e.g., store or forward message
    send_json(200, { success = true, echo = message, user = username })
end

return {
    handle_chat_message = handle_chat_message
}
