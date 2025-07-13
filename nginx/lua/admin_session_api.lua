-- nginx/lua/admin_session_api.lua - Admin session management endpoints
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

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
        send_json(500, { error = "Internal server error", details = "Redis connection failed" })
    end
    return red
end

local function verify_admin_token()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { error = "Authentication required" })
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { error = "Invalid token" })
    end

    local username = jwt_obj.payload.username
    
    -- Get user info from Redis to verify admin status
    local red = connect_redis()
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        send_json(401, { error = "User not found" })
    end

    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    if user.is_admin ~= "true" then
        send_json(403, { error = "Admin privileges required" })
    end

    return username, red
end

local function handle_get_sessions()
    local admin_username, red = verify_admin_token()
    
    local unified_auth = require "unified_auth"
    local sessions = unified_auth.get_all_chat_sessions(red)
    local active_count = unified_auth.count_active_chat_sessions(red)
    
    send_json(200, {
        success = true,
        sessions = sessions,
        active_count = active_count,
        max_sessions = unified_auth.MAX_CHAT_GUESTS,
        session_duration_minutes = unified_auth.GUEST_SESSION_DURATION / 60
    })
end

local function handle_kick_session()
    local admin_username, red = verify_admin_token()
    
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

    local unified_auth = require "unified_auth"
    local success = unified_auth.kick_chat_session(red, session_id)
    
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
    local admin_username, red = verify_admin_token()
    
    local unified_auth = require "unified_auth"
    local cleaned = unified_auth.cleanup_expired_sessions(red)
    
    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " triggered session cleanup - Cleaned: ", cleaned)
    
    send_json(200, {
        success = true,
        message = "Session cleanup completed",
        cleaned_sessions = cleaned,
        triggered_by = admin_username
    })
end

local function handle_get_session_stats()
    local admin_username, red = verify_admin_token()
    
    local unified_auth = require "unified_auth"
    local active_count = unified_auth.count_active_chat_sessions(red)
    local sessions = unified_auth.get_all_chat_sessions(red)
    
    -- Calculate statistics
    local total_age = 0
    local oldest_age = 0
    local newest_age = math.huge
    
    for _, session in ipairs(sessions) do
        total_age = total_age + session.age_seconds
        oldest_age = math.max(oldest_age, session.age_seconds)
        newest_age = math.min(newest_age, session.age_seconds)
    end
    
    local average_age = #sessions > 0 and (total_age / #sessions) or 0
    
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
            sessions_can_be_kicked = #sessions
        }
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
    else
        send_json(404, { error = "Session API endpoint not found" })
    end
end

return {
    handle_session_api = handle_session_api,
    handle_get_sessions = handle_get_sessions,
    handle_kick_session = handle_kick_session,
    handle_cleanup_sessions = handle_cleanup_sessions,
    handle_get_session_stats = handle_get_session_stats
}