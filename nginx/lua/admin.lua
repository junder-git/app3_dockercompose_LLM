local redis = require "resty.redis"
local jwt = require "resty.jwt"
local template = require "template"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Environment variables for dynamic display
local MODEL_DISPLAY_NAME = os.getenv("MODEL_DISPLAY_NAME") or "Devstral Small 2505"
local OLLAMA_GPU_LAYERS = os.getenv("OLLAMA_GPU_LAYERS") or "20"
local OLLAMA_CONTEXT_SIZE = os.getenv("OLLAMA_CONTEXT_SIZE") or "8192"
local MODEL_TEMPERATURE = os.getenv("MODEL_TEMPERATURE") or "0.7"
local RATE_LIMIT_MESSAGES_PER_MINUTE = os.getenv("RATE_LIMIT_MESSAGES_PER_MINUTE") or "8"
local MAX_CHATS_PER_USER = os.getenv("MAX_CHATS_PER_USER") or "1"
local MAX_PENDING_USERS = os.getenv("MAX_PENDING_USERS") or "2"

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

local function get_all_user_keys(red)
    local keys = red:keys("user:*")
    return keys
end

local function count_users_by_status(red)
    local user_keys = get_all_user_keys(red)
    local total = 0
    local approved = 0
    local pending = 0
    local admins = 0

    for _, key in ipairs(user_keys) do
        if key ~= "user:" then -- Skip empty key
            total = total + 1
            local user_data = red:hgetall(key)
            local user = {}
            for i = 1, #user_data, 2 do
                user[user_data[i]] = user_data[i + 1]
            end
            
            if user.is_approved == "true" then
                approved = approved + 1
            else
                pending = pending + 1
            end
            
            if user.is_admin == "true" then
                admins = admins + 1
            end
        end
    end

    return total, approved, pending, admins
end

local function get_messages_count_today(red)
    local today = os.date("%Y-%m-%d")
    local pattern = "user_messages:*:" .. today
    local keys = red:keys(pattern)
    local total = 0
    
    for _, key in ipairs(keys) do
        local count = red:get(key)
        if count then
            total = total + tonumber(count)
        end
    end
    
    return total
end

local function generate_users_table_rows(red)
    local user_keys = get_all_user_keys(red)
    local rows = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then -- Skip empty key
            local user_data = red:hgetall(key)
            local user = {}
            for i = 1, #user_data, 2 do
                user[user_data[i]] = user_data[i + 1]
            end
            
            local username = user.username or "Unknown"
            local status_class = user.is_approved == "true" and "status-approved" or "status-pending"
            local status_text = user.is_approved == "true" and "Approved" or "Pending"
            local role_class = user.is_admin == "true" and "status-admin" or "status-approved"
            local role_text = user.is_admin == "true" and "Admin" or "User"
            local created_at = user.created_at or "Unknown"
            local last_active = user.last_active or "Never"
            
            -- Format dates
            if created_at ~= "Unknown" then
                created_at = created_at:sub(1, 10) -- Just the date part
            end
            if last_active ~= "Never" then
                last_active = last_active:sub(1, 16):gsub("T", " ") -- Date and time, formatted
            end
            
            local actions = ""
            if user.is_approved ~= "true" then
                actions = actions .. '<button class="btn btn-success btn-sm me-1" onclick="approveUser(\'' .. username .. '\')">' ..
                         '<i class="bi bi-check"></i></button>'
            end
            if user.is_admin ~= "true" then
                actions = actions .. '<button class="btn btn-info btn-sm me-1" onclick="toggleUserAdmin(\'' .. username .. '\')" title="Make Admin">' ..
                         '<i class="bi bi-shield-plus"></i></button>'
            else
                actions = actions .. '<button class="btn btn-secondary btn-sm me-1" onclick="toggleUserAdmin(\'' .. username .. '\')" title="Remove Admin">' ..
                         '<i class="bi bi-shield-minus"></i></button>'
            end
            actions = actions .. '<button class="btn btn-danger btn-sm" onclick="deleteUser(\'' .. username .. '\')">' ..
                     '<i class="bi bi-trash"></i></button>'
            
            local row = string.format([[
                <tr>
                    <td><strong>%s</strong></td>
                    <td><span class="status-badge %s">%s</span></td>