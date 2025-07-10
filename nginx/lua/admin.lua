local cjson = require "cjson"
local jwt = require "resty.jwt"

local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-jwt-key-change-this-in-production-min-32-chars"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
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

    if not jwt_obj.payload.is_admin then
        send_json(403, { error = "Admin privileges required" })
    end
end

function handle_admin_panel()
    require_admin()
    -- Your admin logic here, e.g. listing pending users, logs, etc.
    send_json(200, { success = true, message = "Welcome, admin!" })
end

return {
    handle_admin_panel = handle_admin_panel
}
