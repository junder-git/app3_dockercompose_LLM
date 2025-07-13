-- nginx/lua/unified_auth.lua - Handles both logged-in users and guest sessions
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Guest session configuration
local MAX_CHAT_GUESTS = 5  -- Maximum concurrent guest sessions
local GUEST_SESSION_DURATION = 1800  -- 30 minutes in seconds
local GUEST_MESSAGE_LIMIT = 10  -- Maximum messages per guest session

local M = {}
M.MAX_CHAT_GUESTS = MAX_CHAT_GUESTS
M.GUEST_SESSION_DURATION = GUEST_SESSION_DURATION

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        return nil, "Redis connection failed: " .. (err or "unknown")
    end
    return red, nil
end

local function generate_guest_username()
    local adjectives = {"Quick", "Bright", "Swift", "Smart", "Code", "Dev", "Tech", "Data", "Web", "AI"}
    local nouns = {"Coder", "Developer", "Builder", "Maker", "Hacker", "Programmer", "Engineer", "Architect", "Designer", "Creator"}
    
    local adj = adjectives[math.random(#adjectives)]
    local noun = nouns[math.random(#nouns)]
    local num = math.random(100, 999)
    
    return "Guest" .. adj .. noun .. num
end

local function create_guest_session(red)
    local current_time = ngx.time()
    local session_id = ngx.var.remote_addr .. ":" .. current_time .. ":" .. math.random(1000, 9999)
    local username = generate_guest_username()
    
    local session_data = {
        session_id = session_id,
        username = username,
        ip_address = ngx.var.remote_addr,
        created_at = current_time,
        expires_at = current_time + GUEST_SESSION_DURATION,
        message_count = 0,
        last_active = current_time
    }
    
    -- Store session
    local session_key = "guest_session:" .. session_id
    red:hmset(session_key, 
        "session_id", session_id,
        "username", username,
        "ip_address", ngx.var.remote_addr,
        "created_at", current_time,
        "expires_at", current_time + GUEST_SESSION_DURATION,
        "message_count", 0,
        "last_active", current_time
    )
    red:expire(session_key, GUEST_SESSION_DURATION + 60)
    
    -- Add to active sessions list
    red:zadd("active_guest_sessions", current_time + GUEST_SESSION_DURATION, session_id)
    
    return session_data
end

local function get_guest_session(red, session_id)
    if not session_id then
        return nil
    end
    
    local session_key = "guest_session:" .. session_id
    local session_data = red:hgetall(session_key)
    
    if not session_data or #session_data == 0 then
        return nil
    end
    
    local session = {}
    for i = 1, #session_data, 2 do
        session[session_data[i]] = session_data[i + 1]
    end
    
    -- Check if session is expired
    if tonumber(session.expires_at) < ngx.time() then
        red:del(session_key)
        red:zrem("active_guest_sessions", session_id)
        return nil
    end
    
    return session
end

local function count_active_chat_sessions(red)
    -- Clean expired sessions first
    local current_time = ngx.time()
    red:zremrangebyscore("active_guest_sessions", 0, current_time)
    
    -- Count remaining active sessions
    return red:zcard("active_guest_sessions")
end

local function get_all_chat_sessions(red)
    local current_time = ngx.time()
    local session_ids = red:zrangebyscore("active_guest_sessions", current_time, "+inf")
    local sessions = {}
    
    for _, session_id in ipairs(session_ids) do
        local session = get_guest_session(red, session_id)
        if session then
            -- Add calculated fields
            session.age_seconds = current_time - tonumber(session.created_at)
            session.remaining_seconds = tonumber(session.expires_at) - current_time
            table.insert(sessions, session)
        end
    end
    
    return sessions
end

local function kick_chat_session(red, session_id)
    local session_key = "guest_session:" .. session_id
    local exists = red:exists(session_key)
    
    if exists == 1 then
        red:del(session_key)
        red:zrem("active_guest_sessions", session_id)
        return true
    end
    
    return false
end

local function cleanup_expired_sessions(red)
    local current_time = ngx.time()
    
    -- Get expired session IDs
    local expired_ids = red:zrangebyscore("active_guest_sessions", 0, current_time)
    local cleaned_count = 0
    
    for _, session_id in ipairs(expired_ids) do
        local session_key = "guest_session:" .. session_id
        red:del(session_key)
        cleaned_count = cleaned_count + 1
    end
    
    -- Remove from active sessions list
    red:zremrangebyscore("active_guest_sessions", 0, current_time)
    
    return cleaned_count
end

function M.check_user_access()
    local red, err = connect_redis()
    if not red then
        return nil, nil, "Redis connection failed"
    end
    
    -- Check for JWT token first (logged-in user)
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local username = jwt_obj.payload.username
            local user_key = "user:" .. username
            local is_approved = red:hget(user_key, "is_approved")
            
            if is_approved == "true" then
                return "user", username, nil
            else
                return nil, nil, "User not approved"
            end
        end
    end
    
    -- Check for guest session
    local guest_session_id = ngx.var.cookie_guest_session
    if guest_session_id then
        local session = get_guest_session(red, guest_session_id)
        if session then
            -- Update last active
            red:hset("guest_session:" .. guest_session_id, "last_active", ngx.time())
            return "guest", session.username, nil
        end
    end
    
    -- No valid session found
    return nil, nil, "No valid session"
end

function M.create_guest_chat_session()
    local red, err = connect_redis()
    if not red then
        return nil, "Redis connection failed"
    end
    
    -- Check if chat is full
    local active_count = count_active_chat_sessions(red)
    if active_count >= MAX_CHAT_GUESTS then
        return nil, "Chat is full"
    end
    
    -- Create new guest session
    local session = create_guest_session(red)
    
    -- Set cookie
    ngx.header["Set-Cookie"] = "guest_session=" .. session.session_id .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    return session, nil
end

function M.get_guest_limits(session_id)
    if not session_id then
        return nil
    end
    
    local red, err = connect_redis()
    if not red then
        return nil
    end
    
    local session = get_guest_session(red, session_id)
    if not session then
        return nil
    end
    
    local current_time = ngx.time()
    return {
        max_messages = GUEST_MESSAGE_LIMIT,
        used_messages = tonumber(session.message_count) or 0,
        remaining_messages = GUEST_MESSAGE_LIMIT - (tonumber(session.message_count) or 0),
        session_remaining = tonumber(session.expires_at) - current_time,
        session_duration = GUEST_SESSION_DURATION
    }
end

function M.increment_guest_message_count(session_id)
    if not session_id then
        return false
    end
    
    local red, err = connect_redis()
    if not red then
        return false
    end
    
    local session_key = "guest_session:" .. session_id
    local current_count = tonumber(red:hget(session_key, "message_count") or 0)
    
    if current_count >= GUEST_MESSAGE_LIMIT then
        return false  -- Message limit exceeded
    end
    
    red:hincrby(session_key, "message_count", 1)
    red:hset(session_key, "last_active", ngx.time())
    
    return true
end

-- Export functions for admin use
M.get_all_chat_sessions = get_all_chat_sessions
M.count_active_chat_sessions = count_active_chat_sessions
M.kick_chat_session = kick_chat_session
M.cleanup_expired_sessions = cleanup_expired_sessions

return M