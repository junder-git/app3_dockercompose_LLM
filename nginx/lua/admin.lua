local template = require "template"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local function load_nav(username, is_admin)
    local file = io.open("/usr/local/openresty/nginx/html/nav.html", "r")
    local nav_content = file:read("*a")
    file:close()

    if is_admin == "true" then
        nav_content = nav_content:gsub("{{admin_link}}", '<li class="nav-item"><a class="nav-link" href="/admin.html"><i class="bi bi-gear"></i> Admin</a></li>')
    else
        nav_content = nav_content:gsub("{{admin_link}}", "")
    end

    nav_content = nav_content:gsub("{{username}}", username)
    return nav_content
end

local function handle_admin()
    local token = ngx.var.cookie_access_token
    if not token then
        return ngx.redirect("/login.html")
    end

    local jwt_obj = jwt:verify(os.getenv("JWT_SECRET"), token)
    if not jwt_obj.verified then
        return ngx.redirect("/login.html")
    end

    local username = jwt_obj.payload.username
    local red = redis:new()
    red:set_timeout(1000)
    red:connect(os.getenv("REDIS_HOST") or "redis", tonumber(os.getenv("REDIS_PORT")) or 6379)

    local user_key = "user:" .. username
    local is_admin = red:hget(user_key, "is_admin")

    if is_admin ~= "true" then
        return ngx.redirect("/chat.html")
    end

    local nav_html = load_nav(username, is_admin)

    local template_data = {
        navigation = nav_html,
        username = username,
        admin_link = '<li class="nav-item"><a class="nav-link" href="/admin.html"><i class="bi bi-gear"></i> Admin</a></li>'
    }

    template.render_template("/usr/local/openresty/nginx/html/admin.html", template_data)
end

return {
    handle_admin = handle_admin
}
