-- nginx/lua/chat.lua - Updated with guest session support
local template = require "template"
local redis = require "resty.redis"
local jwt = require "resty.jwt"
local unified_auth = require "unified_auth"
local cjson = require "cjson"

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

local function handle_chat()
    local red = redis:new()
    red:set_timeout(1000)
    red:connect(os.getenv("REDIS_HOST") or "redis", tonumber(os.getenv("REDIS_PORT")) or 6379)
    
    -- Check user access (logged-in user or guest)
    local user_type, username, error_msg = unified_auth.check_user_access()
    
    local template_data = {
        username = "Guest",
        is_guest = "false",
        is_placeholder = "false",
        chat_full = "false",
        guest_limits = "null",
        navigation = "",
        admin_link = ""
    }
    
    if user_type == "user" then
        -- Logged-in user
        local user_key = "user:" .. username
        local is_admin = red:hget(user_key, "is_admin")
        local nav_html = load_nav(username, is_admin)
        
        template_data.username = username
        template_data.is_guest = "false"
        template_data.navigation = nav_html
        template_data.admin_link = is_admin == "true" and '<li class="nav-item"><a class="nav-link" href="/admin.html"><i class="bi bi-gear"></i> Admin</a></li>' or ""
        
    elseif user_type == "guest" then
        -- Active guest session
        local guest_session_id = ngx.var.cookie_guest_session
        local guest_limits = unified_auth.get_guest_limits(guest_session_id)
        
        template_data.username = username
        template_data.is_guest = "true"
        template_data.guest_limits = cjson.encode(guest_limits)
        
        -- Create basic nav for guests
        local nav_html = [[
<nav class="navbar navbar-expand-lg navbar-dark">
    <div class="container-fluid">
        <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
        <div class="navbar-nav ms-auto">
            <span class="navbar-text me-3">]] .. username .. [[ (Guest Session)</span>
            <a class="nav-link" href="/register.html"><i class="bi bi-person-plus"></i> Register</a>
        </div>
    </div>
</nav>
]]
        template_data.navigation = nav_html
        
    else
        -- No valid session - show placeholder or handle guest session creation
        local active_count = unified_auth.count_active_chat_sessions(red)
        
        if active_count >= unified_auth.MAX_CHAT_GUESTS then
            -- Chat is full
            template_data.chat_full = "true"
            template_data.is_placeholder = "true"
        else
            -- Show placeholder with option to start guest session
            template_data.is_placeholder = "true"
        end
        
        -- Create basic nav for non-authenticated users
        local nav_html = [[
<nav class="navbar navbar-expand-lg navbar-dark">
    <div class="container-fluid">
        <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
        <div class="navbar-nav ms-auto">
            <a class="nav-link" href="/login.html"><i class="bi bi-box-arrow-in-right"></i> Login</a>
            <a class="nav-link" href="/register.html"><i class="bi bi-person-plus"></i> Register</a>
        </div>
    </div>
</nav>
]]
        template_data.navigation = nav_html
    end
    
    template.render_template("/usr/local/openresty/nginx/html/chat.html", template_data)
end

return {
    handle_chat = handle_chat
}