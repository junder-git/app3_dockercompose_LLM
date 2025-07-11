local redis = require "resty.redis"
local jwt = require "resty.jwt"
local template = require "template"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local function send_html(content)
    ngx.status = 200
    ngx.header.content_type = "text/html"
    ngx.say(content)
    ngx.exit(200)
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.status = 500
        ngx.say("Failed to connect to Redis")
        ngx.exit(500)
    end
    return red
end

function handle_admin_page()
    local token = ngx.var.cookie_access_token
    if not token then
        return ngx.redirect("/login.html?redirect=admin.html", 302)
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        return ngx.redirect("/login.html?redirect=admin.html", 302)
    end

    local username = jwt_obj.payload.username

    local red = connect_redis()
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    if user.is_admin ~= "true" then
        return ngx.redirect("/login.html?redirect=admin.html", 302)
    end

    local html, err = template.render_template("/usr/local/openresty/nginx/html/admin.html", {
        username = username
    })
    if not html then
        ngx.status = 500
        ngx.say("Template error: " .. err)
        ngx.exit(500)
    end

    send_html(html)
end

return {
    handle_admin_page = handle_admin_page
}
