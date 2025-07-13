-- nginx/lua/unified_auth.lua - Enhanced with hardcoded guest tokens
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Guest session configuration
local MAX_CHAT_GUESTS = 5
local GUEST_SESSION_DURATION = 1800  -- 30 minutes
local GUEST_MESSAGE_LIMIT = 10

-- Pre-generated guest tokens (hardcoded for simplicity)
local GUEST_TOKENS = {
    "guest_token_1_" .. string.sub(JWT_SECRET, 1, 8),
    "guest_token_2_" .. string.sub(JWT_SECRET, 1, 8),
    "guest_token_3_" .. string.sub(JWT_SECRET, 1, 8),
    "guest_token_4_" .. string.sub(JWT_SECRET, 1, 8),
    "guest_token_5_" .. string.sub(JWT_SECRET, 1, 8)
}

local GUEST_USERNAMES = {
    "GuestCoder001", "GuestDev002", "GuestHacker003", 
    "GuestBuilder004", "GuestMaker005"
}

local M = {}
M.MAX_CHAT_GUESTS = MAX_CHAT_GUESTS
M.GUEST_SESSION_DURATION = GUEST_SESSION_DURATION
M.GUEST_MESSAGE_LIMIT = GUEST_MESSAGE_LIMIT

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.log(ngx.WARN, "Redis connection failed: " .. (err or "unknown"))
        return nil, "Redis connection failed"
    end
    return red, nil
end

local function get_guest_slot_from_token(token)
    for i, guest_token in ipairs(GUEST_TOKENS) do
        if token == guest_token then
            return i
        end
    end
    return nil
end

local function is_guest_slot_active(slot_num)
    -- Check if this guest slot is currently active
    local guest_key = "guest_active:" .. slot_num
    local active_until = tonumber(ngx.shared.guest_sessions:get(guest_key) or 0)
    return ngx.time() < active_until
end

local function activate_guest_slot(slot_num)
    local guest_key = "guest_active:" .. slot_num
    local expires_at = ngx.time() + GUEST_SESSION_DURATION
    ngx.shared.guest_sessions:set(guest_key, expires_at, GUEST_SESSION_DURATION)
    
    -- Track message count
    local msg_key = "guest_messages:" .. slot_num
    ngx.shared.guest_sessions:set(msg_key, 0, GUEST_SESSION_DURATION)
    
    return expires_at
end

local function get_guest_message_count(slot_num)
    local msg_key = "guest_messages:" .. slot_num
    return tonumber(ngx.shared.guest_sessions:get(msg_key) or 0)
end

local function increment_guest_message_count(slot_num)
    local msg_key = "guest_messages:" .. slot_num
    local current = tonumber(ngx.shared.guest_sessions:get(msg_key) or 0)
    
    if current >= GUEST_MESSAGE_LIMIT then
        return false  -- Limit exceeded
    end
    
    ngx.shared.guest_sessions:set(msg_key, current + 1, GUEST_SESSION_DURATION)
    return true
end

local function get_active_guest_count()
    local count = 0
    for i = 1, MAX_CHAT_GUESTS do
        if is_guest_slot_active(i) then
            count = count + 1
        end
    end
    return count
end

local function find_available_guest_slot()
    for i = 1, MAX_CHAT_GUESTS do
        if not is_guest_slot_active(i) then
            return i
        end
    end
    return nil
end

local function kick_guest_slot(slot_num)
    local guest_key = "guest_active:" .. slot_num
    local msg_key = "guest_messages:" .. slot_num
    
    ngx.shared.guest_sessions:delete(guest_key)
    ngx.shared.guest_sessions:delete(msg_key)
    
    return true
end

function M.check_user_access()
    -- First, try to check for regular JWT token (logged-in users)
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local username = jwt_obj.payload.username
            
            -- Try to connect to Redis to check user status
            local red, err = connect_redis()
            if red then
                local user_key = "user:" .. username
                local user_data = red:hgetall(user_key)
                
                if user_data and #user_data > 0 then
                    local user = {}
                    for i = 1, #user_data, 2 do
                        user[user_data[i]] = user_data[i + 1]
                    end
                    
                    -- Admin always gets access
                    if user.is_admin == "true" then
                        return "admin", username, nil
                    end
                    
                    -- Approved user gets access
                    if user.is_approved == "true" then
                        return "user", username, nil
                    end
                    
                    return nil, nil, "User not approved"
                end
            else
                -- Redis is down, but if admin user, allow anyway
                ngx.log(ngx.WARN, "Redis down, checking if admin user: " .. username)
                -- You could have a hardcoded admin list here if needed
            end
        end
    end
    
    -- Check for guest token
    local guest_token = ngx.var.cookie_guest_token
    if guest_token then
        local slot_num = get_guest_slot_from_token(guest_token)
        if slot_num then
            if is_guest_slot_active(slot_num) then
                return "guest", GUEST_USERNAMES[slot_num], slot_num
            else
                -- Guest session expired
                return nil, nil, "Guest session expired"
            end
        end
    end
    
    return nil, nil, "No valid session"
end

function M.create_guest_session()
    -- Check if chat is full
    local active_count = get_active_guest_count()
    if active_count >= MAX_CHAT_GUESTS then
        return nil, "Chat is full", nil
    end
    
    -- Find available slot
    local slot_num = find_available_guest_slot()
    if not slot_num then
        return nil, "No available slots", nil
    end
    
    -- Activate the slot
    local expires_at = activate_guest_slot(slot_num)
    
    -- Set guest token cookie
    local guest_token = GUEST_TOKENS[slot_num]
    ngx.header["Set-Cookie"] = "guest_token=" .. guest_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    local session_data = {
        slot_num = slot_num,
        username = GUEST_USERNAMES[slot_num],
        token = guest_token,
        expires_at = expires_at,
        message_limit = GUEST_MESSAGE_LIMIT,
        session_duration = GUEST_SESSION_DURATION
    }
    
    return session_data, nil, slot_num
end

function M.get_guest_limits(slot_num)
    if not slot_num then
        return nil
    end
    
    local guest_key = "guest_active:" .. slot_num
    local expires_at = tonumber(ngx.shared.guest_sessions:get(guest_key) or 0)
    local message_count = get_guest_message_count(slot_num)
    
    if ngx.time() >= expires_at then
        return nil  -- Session expired
    end
    
    return {
        max_messages = GUEST_MESSAGE_LIMIT,
        used_messages = message_count,
        remaining_messages = GUEST_MESSAGE_LIMIT - message_count,
        session_remaining = expires_at - ngx.time(),
        session_duration = GUEST_SESSION_DURATION,
        slot_num = slot_num
    }
end

function M.use_guest_message(slot_num)
    if not slot_num then
        return false
    end
    
    return increment_guest_message_count(slot_num)
end

function M.get_all_guest_sessions()
    local sessions = {}
    
    for i = 1, MAX_CHAT_GUESTS do
        if is_guest_slot_active(i) then
            local guest_key = "guest_active:" .. i
            local expires_at = tonumber(ngx.shared.guest_sessions:get(guest_key) or 0)
            local message_count = get_guest_message_count(i)
            local current_time = ngx.time()
            
            table.insert(sessions, {
                id = "guest_slot_" .. i,
                slot_num = i,
                username = GUEST_USERNAMES[i],
                ip_address = "N/A",  -- We don't track this for hardcoded sessions
                created_at = current_time - (GUEST_SESSION_DURATION - (expires_at - current_time)),
                age_seconds = GUEST_SESSION_DURATION - (expires_at - current_time),
                remaining_seconds = expires_at - current_time,
                last_active = "N/A",
                message_count = message_count
            })
        end
    end
    
    return sessions
end

function M.kick_guest_session(session_id)
    -- Extract slot number from session_id
    local slot_num = tonumber(string.match(session_id, "guest_slot_(%d+)"))
    if slot_num then
        return kick_guest_slot(slot_num)
    end
    return false
end

function M.cleanup_expired_guest_sessions()
    local cleaned = 0
    local current_time = ngx.time()
    
    for i = 1, MAX_CHAT_GUESTS do
        local guest_key = "guest_active:" .. i
        local expires_at = tonumber(ngx.shared.guest_sessions:get(guest_key) or 0)
        
        if current_time >= expires_at then
            kick_guest_slot(i)
            cleaned = cleaned + 1
        end
    end
    
    return cleaned
end

function M.count_active_guest_sessions()
    return get_active_guest_count()
end

-- Admin check function
function M.check_admin_access()
    local token = ngx.var.cookie_access_token
    if not token then
        return false, "No token"
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        return false, "Invalid token"
    end
    
    local username = jwt_obj.payload.username
    
    -- Try Redis first
    local red, err = connect_redis()
    if red then
        local user_key = "user:" .. username
        local is_admin = red:hget(user_key, "is_admin")
        if is_admin == "true" then
            return true, username
        end
    else
        -- Redis is down - you could have hardcoded admin users here
        ngx.log(ngx.WARN, "Redis down for admin check: " .. username)
        
        -- Hardcoded admin fallback (optional)
        local HARDCODED_ADMINS = {
            [os.getenv("ADMIN_USERNAME") or "admin"] = true
        }
        
        if HARDCODED_ADMINS[username] then
            ngx.log(ngx.INFO, "Hardcoded admin access granted: " .. username)
            return true, username
        end
    end
    
    return false, "Not admin"
end

-- Check if user is approved (for regular users)
function M.check_approved_user()
    local token = ngx.var.cookie_access_token
    if not token then
        return false, "No token"
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        return false, "Invalid token"
    end
    
    local username = jwt_obj.payload.username
    
    local red, err = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        return false, "User not found"
    end
    
    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end
    
    if user.is_approved == "true" then
        return true, username
    end
    
    return false, "User not approved"
end

return M