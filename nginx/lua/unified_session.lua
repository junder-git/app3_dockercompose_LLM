-- nginx/lua/unified_session_manager.lua - Complete session management system
local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Global configuration
local MAX_SSE_SESSIONS = 5
local SESSION_TIMEOUT = 300  -- 5 minutes timeout for inactive sessions
local GUEST_SESSION_DURATION = 1800  -- 30 minutes for guest sessions
local GUEST_MESSAGE_LIMIT = 10

local M = {}
M.MAX_SSE_SESSIONS = MAX_SSE_SESSIONS
M.SESSION_TIMEOUT = SESSION_TIMEOUT
M.GUEST_SESSION_DURATION = GUEST_SESSION_DURATION
M.GUEST_MESSAGE_LIMIT = GUEST_MESSAGE_LIMIT

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

-- Priority levels: 1 = Admin (highest), 2 = Approved User, 3 = Guest (lowest)
local function get_user_priority(user_type, is_admin)
    if user_type == "admin" or is_admin then
        return 1, "admin"
    elseif user_type == "user" then
        return 2, "user"
    elseif user_type == "guest" then
        return 3, "guest"
    else
        return 4, "unknown"
    end
end

-- Get all active SSE sessions from shared memory
local function get_active_sse_sessions()
    local sessions = {}
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                table.insert(sessions, session)
            end
        end
    end
    
    -- Sort by priority (lower number = higher priority), then by creation time
    table.sort(sessions, function(a, b)
        if a.priority == b.priority then
            return a.created_at < b.created_at
        end
        return a.priority < b.priority
    end)
    
    return sessions
end

-- Clean up expired sessions
local function cleanup_expired_sessions()
    local current_time = ngx.time()
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local cleaned = 0
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                if current_time - session.last_activity > SESSION_TIMEOUT then
                    ngx.shared.sse_sessions:delete(key)
                    cleaned = cleaned + 1
                    ngx.log(ngx.INFO, "Cleaned expired SSE session: " .. session.session_id)
                end
            end
        end
    end
    
    return cleaned
end

-- Check user authentication and get user info
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
                        return "admin", username, nil, true
                    end
                    
                    -- Approved user gets access
                    if user.is_approved == "true" then
                        return "user", username, nil, false
                    end
                    
                    return nil, nil, "User not approved", false
                end
            else
                ngx.log(ngx.WARN, "Redis down for user check: " .. username)
                return nil, nil, "Service unavailable", false
            end
        end
    end
    
    -- Check for guest token (simple hardcoded tokens for demo)
    local guest_token = ngx.var.cookie_guest_token
    if guest_token and string.match(guest_token, "^guest_") then
        -- Extract guest username from token
        local guest_username = string.gsub(guest_token, "guest_token_", "guest_")
        
        -- Check if guest session is still valid
        local guest_key = "guest_session:" .. guest_username
        local guest_data = ngx.shared.guest_sessions:get(guest_key)
        
        if guest_data then
            local session = cjson.decode(guest_data)
            if ngx.time() < session.expires_at then
                return "guest", guest_username, nil, false
            else
                -- Guest session expired
                ngx.shared.guest_sessions:delete(guest_key)
                return nil, nil, "Guest session expired", false
            end
        end
    end
    
    return nil, nil, "No valid session", false
end

-- Check if user already has an active SSE session
local function user_has_active_session(username)
    local sessions = get_active_sse_sessions()
    
    for _, session in ipairs(sessions) do
        if session.username == username then
            return true, session
        end
    end
    
    return false, nil
end

-- Kick lowest priority session to make room
local function kick_lowest_priority_session(requesting_priority)
    local sessions = get_active_sse_sessions()
    
    if #sessions == 0 then
        return false, "No sessions to kick"
    end
    
    -- Find kickable sessions (lower or equal priority, but not admin)
    local kickable_sessions = {}
    for _, session in ipairs(sessions) do
        if session.priority > requesting_priority or (session.priority == requesting_priority and requesting_priority > 1) then
            table.insert(kickable_sessions, session)
        end
    end
    
    if #kickable_sessions == 0 then
        return false, "No kickable sessions found"
    end
    
    -- Sort kickable sessions by priority (highest priority number = lowest actual priority)
    table.sort(kickable_sessions, function(a, b)
        if a.priority == b.priority then
            return a.created_at < b.created_at  -- Kick oldest first
        end
        return a.priority > b.priority  -- Kick lower priority first
    end)
    
    local victim_session = kickable_sessions[1]
    local session_key = "sse:" .. victim_session.session_id
    ngx.shared.sse_sessions:delete(session_key)
    
    ngx.log(ngx.WARN, "Kicked SSE session due to capacity: " .. victim_session.session_id .. 
            " (user: " .. victim_session.username .. ", priority: " .. victim_session.priority .. ")")
    
    return true, victim_session
end

-- Check if user can start SSE session
function M.can_start_sse_session(user_type, username, is_admin)
    -- Clean up expired sessions first
    cleanup_expired_sessions()
    
    local priority, user_category = get_user_priority(user_type, is_admin)
    local active_sessions = get_active_sse_sessions()
    local active_count = #active_sessions
    
    -- Check if user already has an active session
    local has_session, existing_session = user_has_active_session(username)
    if has_session then
        return false, "User already has an active SSE session: " .. existing_session.session_id, nil
    end
    
    -- If under limit, allow
    if active_count < MAX_SSE_SESSIONS then
        return true, "Session allowed (slots available: " .. (MAX_SSE_SESSIONS - active_count) .. ")", priority
    end
    
    -- If at limit, check if we can kick someone
    local can_kick, kicked = kick_lowest_priority_session(priority)
    if can_kick then
        return true, "Session granted (kicked: " .. (kicked.username or "unknown") .. ")", priority
    else
        return false, "SSE sessions at capacity, cannot kick any sessions for priority " .. priority, nil
    end
end

-- Start SSE session
function M.start_sse_session(user_type, username, is_admin)
    local can_start, message, priority = M.can_start_sse_session(user_type, username, is_admin)
    
    if not can_start then
        return false, message, nil
    end
    
    local session_id = username .. "_sse_" .. ngx.time() .. "_" .. math.random(1000, 9999)
    local current_time = ngx.time()
    
    local session = {
        session_id = session_id,
        username = username,
        user_type = user_type,
        priority = priority,
        is_admin = is_admin,
        created_at = current_time,
        last_activity = current_time,
        remote_addr = ngx.var.remote_addr or "unknown",
        user_agent = ngx.var.http_user_agent or "unknown"
    }
    
    local session_key = "sse:" .. session_id
    ngx.shared.sse_sessions:set(session_key, cjson.encode(session), SESSION_TIMEOUT + 60)
    
    ngx.log(ngx.INFO, "Started SSE session: " .. session_id .. " (user: " .. username .. 
            ", type: " .. user_type .. ", priority: " .. priority .. ")")
    
    return true, message, session_id
end

-- Update session activity
function M.update_session_activity(session_id)
    if not session_id then
        return false, "No session ID provided"
    end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false, "Session not found"
    end
    
    local session = cjson.decode(session_info)
    session.last_activity = ngx.time()
    
    ngx.shared.sse_sessions:set(session_key, cjson.encode(session), SESSION_TIMEOUT + 60)
    return true, "Activity updated"
end

-- End SSE session
function M.end_sse_session(session_id)
    if not session_id then
        return false, "No session ID provided"
    end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if session_info then
        local session = cjson.decode(session_info)
        ngx.shared.sse_sessions:delete(session_key)
        ngx.log(ngx.INFO, "Ended SSE session: " .. session_id .. " (user: " .. (session.username or "unknown") .. ")")
        return true, "Session ended"
    end
    
    return false, "Session not found"
end

-- Check if session exists and is valid
function M.is_session_valid(session_id)
    if not session_id then
        return false, "No session ID provided"
    end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false, "Session not found"
    end
    
    local session = cjson.decode(session_info)
    local current_time = ngx.time()
    
    if current_time - session.last_activity > SESSION_TIMEOUT then
        ngx.shared.sse_sessions:delete(session_key)
        return false, "Session expired"
    end
    
    return true, session
end

-- Guest session management (simplified)
function M.create_guest_session()
    local guest_username = "guest_" .. ngx.time() .. "_" .. math.random(100, 999)
    local guest_token = "guest_token_" .. guest_username
    local expires_at = ngx.time() + GUEST_SESSION_DURATION
    
    local session_data = {
        username = guest_username,
        token = guest_token,
        expires_at = expires_at,
        created_at = ngx.time(),
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT
    }
    
    -- Store in shared memory
    local guest_key = "guest_session:" .. guest_username
    ngx.shared.guest_sessions:set(guest_key, cjson.encode(session_data), GUEST_SESSION_DURATION)
    
    -- Set cookie
    ngx.header["Set-Cookie"] = "guest_token=" .. guest_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    return session_data, nil
end

function M.use_guest_message(username)
    local guest_key = "guest_session:" .. username
    local guest_data = ngx.shared.guest_sessions:get(guest_key)
    
    if not guest_data then
        return false, "Guest session not found"
    end
    
    local session = cjson.decode(guest_data)
    
    if session.message_count >= session.max_messages then
        return false, "Message limit exceeded"
    end
    
    session.message_count = session.message_count + 1
    ngx.shared.guest_sessions:set(guest_key, cjson.encode(session), GUEST_SESSION_DURATION)
    
    return true, "Message allowed"
end

function M.get_guest_limits(username)
    local guest_key = "guest_session:" .. username
    local guest_data = ngx.shared.guest_sessions:get(guest_key)
    
    if not guest_data then
        return nil
    end
    
    local session = cjson.decode(guest_data)
    local remaining_time = session.expires_at - ngx.time()
    
    if remaining_time <= 0 then
        ngx.shared.guest_sessions:delete(guest_key)
        return nil
    end
    
    return {
        max_messages = session.max_messages,
        used_messages = session.message_count,
        remaining_messages = session.max_messages - session.message_count,
        session_remaining = remaining_time,
        expires_at = session.expires_at
    }
end

-- Admin functions
function M.get_all_sse_sessions()
    cleanup_expired_sessions()
    local sessions = get_active_sse_sessions()
    
    local result = {
        sessions = {},
        count = #sessions,
        max_sessions = MAX_SSE_SESSIONS,
        utilization = math.floor((#sessions / MAX_SSE_SESSIONS) * 100)
    }
    
    for _, session in ipairs(sessions) do
        local priority_name = "unknown"
        if session.priority == 1 then priority_name = "admin"
        elseif session.priority == 2 then priority_name = "user"
        elseif session.priority == 3 then priority_name = "guest"
        end
        
        table.insert(result.sessions, {
            session_id = session.session_id,
            username = session.username,
            user_type = session.user_type,
            priority = session.priority,
            priority_name = priority_name,
            is_admin = session.is_admin,
            created_at = session.created_at,
            last_activity = session.last_activity,
            age_seconds = ngx.time() - session.created_at,
            inactive_seconds = ngx.time() - session.last_activity,
            remote_addr = session.remote_addr,
            user_agent = session.user_agent
        })
    end
    
    return result
end

function M.admin_kick_session(session_id, admin_username, reason)
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false, "Session not found"
    end
    
    local session = cjson.decode(session_info)
    
    -- Don't allow kicking admin sessions
    if session.priority == 1 then
        ngx.log(ngx.WARN, "Admin attempted to kick admin session: " .. admin_username .. " -> " .. session_id)
        return false, "Cannot kick admin session"
    end
    
    ngx.shared.sse_sessions:delete(session_key)
    
    ngx.log(ngx.WARN, "Admin kicked SSE session: " .. admin_username .. " kicked " .. session_id .. 
            " (user: " .. session.username .. ") - Reason: " .. (reason or "Manual removal"))
    
    return true, "Session kicked successfully"
end

function M.get_session_stats()
    cleanup_expired_sessions()
    local sessions = get_active_sse_sessions()
    
    local stats = {
        total_sessions = #sessions,
        max_sessions = MAX_SSE_SESSIONS,
        available_slots = MAX_SSE_SESSIONS - #sessions,
        utilization_percent = math.floor((#sessions / MAX_SSE_SESSIONS) * 100),
        by_priority = {
            admin_sessions = 0,
            user_sessions = 0,
            guest_sessions = 0
        },
        oldest_session_age = 0,
        average_session_age = 0
    }
    
    local total_age = 0
    local current_time = ngx.time()
    
    for _, session in ipairs(sessions) do
        local age = current_time - session.created_at
        total_age = total_age + age
        stats.oldest_session_age = math.max(stats.oldest_session_age, age)
        
        if session.priority == 1 then
            stats.by_priority.admin_sessions = stats.by_priority.admin_sessions + 1
        elseif session.priority == 2 then
            stats.by_priority.user_sessions = stats.by_priority.user_sessions + 1
        elseif session.priority == 3 then
            stats.by_priority.guest_sessions = stats.by_priority.guest_sessions + 1
        end
    end
    
    if #sessions > 0 then
        stats.average_session_age = math.floor(total_age / #sessions)
    end
    
    return stats
end

return M