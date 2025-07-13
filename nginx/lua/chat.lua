local redis = require "resty.redis"
local jwt = require "resty.jwt"
local template = require "template"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local MODEL_DISPLAY_NAME = os.getenv("MODEL_DISPLAY_NAME") or "Devstral Small 2505"
local MODEL_DESCRIPTION = os.getenv("MODEL_DESCRIPTION") or "Advanced coding and reasoning model"

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

local function get_user_message_count(red, username)
    -- Get today's date as key
    local today = os.date("%Y-%m-%d")
    local count_key = "user_messages:" .. username .. ":" .. today
    local count = red:get(count_key)
    return count and tonumber(count) or 0
end

local function get_user_last_active(red, username)
    local last_active = red:hget("user:" .. username, "last_active")
    if last_active then
        return last_active
    else
        return "Never"
    end
end

function handle_chat_page()
    local token = ngx.var.cookie_access_token
    if not token then
        return ngx.redirect("/login.html?redirect=chat.html", 302)
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        return ngx.redirect("/login.html?redirect=chat.html", 302)
    end

    local username = jwt_obj.payload.username

    -- Connect to Redis to get user data
    local red = connect_redis()
    
    -- Get user information
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    -- Check if user is approved
    if user.is_approved ~= "true" then
        ngx.status = 403
        ngx.say("User not approved. Please wait for admin approval.")
        ngx.exit(403)
    end

    -- Update last active timestamp
    red:hset(user_key, "last_active", os.date("!%Y-%m-%dT%TZ"))

    -- Get user's message count for today
    local user_message_count = get_user_message_count(red, username)
    
    -- Build model info string
    local model_info = MODEL_DISPLAY_NAME .. " - " .. MODEL_DESCRIPTION

    -- Prepare template data
    local template_data = {
        username = username,
        model_info = model_info,
        user_message_count = tostring(user_message_count),
        user_status = user.is_admin == "true" and "Admin" or "User",
        last_active = get_user_last_active(red, username)
    }

    local html, err = template.render_template("/usr/local/openresty/nginx/html/chat.html", template_data)
    if not html then
        ngx.status = 500
        ngx.say("Template error: " .. (err or "Unknown error"))
        ngx.exit(500)
    end

    send_html(html)
end

return {
    handle_chat_page = handle_chat_page
}