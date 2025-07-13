-- nginx/lua/admin_session_api.lua - Enhanced admin session management
local cjson = require "cjson"
local redis = require "resty.redis"
local unified_auth = require "unified_auth"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379

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
        ngx.log(ngx.WARN, "Redis connection failed: " .. (err or "unknown"))
        return nil, err
    end
    return red, nil
end

local function get_redis_guest_sessions(red)
    -- This would be for any Redis-based guest sessions (legacy)
    -- For now, return empty array since we're using hardcoded tokens
    return {}
end

local function handle_get_sessions()
    local admin_username = ngx.var.auth_username
    
    -- Get hardcoded guest sessions
    local guest_sessions = unified_auth.get_all_guest_sessions()
    local active_count = unified_auth.count_active_guest_sessions()
    
    -- Optionally get Redis-based sessions too
    local red, err = connect_redis()
    local redis_sessions = {}
    if red then
        redis_sessions = get_redis_guest_sessions(red)
    end
    
    -- Combine all sessions
    local all_sessions = {}
    
    -- Add hardcoded guest sessions
    for _, session in ipairs(guest_sessions) do
        session.type = "hardcoded_guest"
        table.insert(all_sessions, session)
    end
    
    -- Add Redis sessions if any
    for _, session in ipairs(redis_sessions) do
        session.type = "redis_guest"
        table.insert(all_sessions, session)
    end
    
    send_json(200, {
        success = true,
        sessions = all_sessions,
        active_count = active_count,
        max_sessions = unified_auth.MAX_CHAT_GUESTS,
        session_duration_minutes = unified_auth.GUEST_SESSION_DURATION / 60,
        hardcoded_sessions = #guest_sessions,
        redis_sessions = #redis_sessions
    })
end

local function handle_kick_session()
    local admin_username = ngx.var.auth_username
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local session_id = data.session_id
    local reason = data.reason or "Manual admin removal"

    if not session_id then
        send_json(400, { error = "Session ID required" })
    end

    local success = false
    
    -- Try to kick hardcoded guest session
    if string.match(session_id, "^guest_slot_") then
        success = unified_auth.kick_guest_session(session_id)
    else
        -- Try to kick Redis-based session (legacy support)
        local red, err = connect_redis()
        if red then
            -- Implementation for Redis-based session kicking would go here
            -- For now, return false since we're not using Redis sessions
            success = false
        end
    end
    
    if success then
        -- Log the action
        ngx.log(ngx.ERR, "Admin ", admin_username, " kicked session ", session_id, " - Reason: ", reason)
        
        send_json(200, { 
            success = true, 
            message = "Session kicked successfully",
            session_id = session_id,
            kicked_by = admin_username,
            reason = reason
        })
    else
        send_json(404, { 
            error = "Session not found or already expired",
            session_id = session_id
        })
    end
end

local function handle_cleanup_sessions()
    local admin_username = ngx.var.auth_username
    
    -- Cleanup hardcoded guest sessions
    local cleaned_hardcoded = unified_auth.cleanup_expired_guest_sessions()
    
    -- Cleanup Redis sessions if needed
    local cleaned_redis = 0
    local red, err = connect_redis()
    if red then
        -- Redis session cleanup would go here
        -- For now, no Redis sessions to clean
        cleaned_redis = 0
    end
    
    local total_cleaned = cleaned_hardcoded + cleaned_redis
    
    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " triggered session cleanup - Cleaned: ", total_cleaned, 
            " (hardcoded: ", cleaned_hardcoded, ", redis: ", cleaned_redis, ")")
    
    send_json(200, {
        success = true,
        message = "Session cleanup completed",
        cleaned_sessions = total_cleaned,
        hardcoded_cleaned = cleaned_hardcoded,
        redis_cleaned = cleaned_redis,
        triggered_by = admin_username
    })
end

local function handle_get_session_stats()
    local admin_username = ngx.var.auth_username
    
    local guest_sessions = unified_auth.get_all_guest_sessions()
    local active_count = unified_auth.count_active_guest_sessions()
    
    -- Calculate statistics
    local total_age = 0
    local oldest_age = 0
    local newest_age = math.huge
    local total_messages = 0
    
    for _, session in ipairs(guest_sessions) do
        total_age = total_age + session.age_seconds
        oldest_age = math.max(oldest_age, session.age_seconds)
        newest_age = math.min(newest_age, session.age_seconds)
        total_messages = total_messages + (session.message_count or 0)
    end
    
    local average_age = #guest_sessions > 0 and (total_age / #guest_sessions) or 0
    local average_messages = #guest_sessions > 0 and (total_messages / #guest_sessions) or 0
    
    send_json(200, {
        success = true,
        stats = {
            active_sessions = active_count,
            max_sessions = unified_auth.MAX_CHAT_GUESTS,
            session_duration_minutes = unified_auth.GUEST_SESSION_DURATION / 60,
            utilization_percent = math.floor((active_count / unified_auth.MAX_CHAT_GUESTS) * 100),
            average_session_age_minutes = math.floor(average_age / 60),
            oldest_session_age_minutes = math.floor(oldest_age / 60),
            newest_session_age_minutes = math.floor(newest_age / 60),
            total_messages_sent = total_messages,
            average_messages_per_session = math.floor(average_messages),
            sessions_can_be_kicked = #guest_sessions,
            message_limit_per_session = unified_auth.GUEST_MESSAGE_LIMIT
        }
    })
end

local function handle_create_guest_session()
    local admin_username = ngx.var.auth_username
    
    -- Admin can manually create a guest session
    local session_data, error_msg, slot_num = unified_auth.create_guest_session()
    
    if not session_data then
        send_json(400, {
            error = "Failed to create guest session",
            message = error_msg
        })
    end
    
    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " manually created guest session for slot ", slot_num)
    
    send_json(200, {
        success = true,
        message = "Guest session created successfully",
        session = session_data,
        created_by = admin_username
    })
end

local function handle_get_guest_limits()
    local slot_num = tonumber(ngx.var.arg_slot)
    
    if not slot_num then
        send_json(400, { error = "Slot number required" })
    end
    
    local limits = unified_auth.get_guest_limits(slot_num)
    
    if not limits then
        send_json(404, { error = "Guest session not found or expired" })
    end
    
    send_json(200, {
        success = true,
        limits = limits
    })
end

-- Route handler function
local function handle_session_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/admin/sessions" and method == "GET" then
        handle_get_sessions()
    elseif uri == "/api/admin/sessions/kick" and method == "POST" then
        handle_kick_session()
    elseif uri == "/api/admin/sessions/cleanup" and method == "POST" then
        handle_cleanup_sessions()
    elseif uri == "/api/admin/sessions/stats" and method == "GET" then
        handle_get_session_stats()
    elseif uri == "/api/admin/sessions/create" and method == "POST" then
        handle_create_guest_session()
    elseif uri == "/api/admin/sessions/limits" and method == "GET" then
        handle_get_guest_limits()
    else
        send_json(404, { error = "Session API endpoint not found" })
    end
end

return {
    handle_session_api = handle_session_api,
    handle_get_sessions = handle_get_sessions,
    handle_kick_session = handle_kick_session,
    handle_cleanup_sessions = handle_cleanup_sessions,
    handle_get_session_stats = handle_get_session_stats,
    handle_create_guest_session = handle_create_guest_session,
    handle_get_guest_limits = handle_get_guest_limits
}