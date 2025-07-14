-- nginx/lua/server.lua - SECURE Redis operations and SSE session management
local cjson = require "cjson"
local redis = require "resty.redis"
local http = require "resty.http"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434"
local OLLAMA_MODEL = os.getenv("OLLAMA_MODEL") or "devstral"

-- Configuration
local MAX_SSE_SESSIONS = 5
local SESSION_TIMEOUT = 300  -- 5 minutes
local GUEST_SESSION_DURATION = 1800  -- 30 minutes
local GUEST_MESSAGE_LIMIT = 10
local USER_RATE_LIMIT = 60  -- messages per hour
local ADMIN_RATE_LIMIT = 120  -- higher limit for admins

local M = {}

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection failed: " .. (err or "unknown"))
        return nil
    end
    return red
end

-- =============================================
-- SECURE USER MANAGEMENT (Redis)
-- =============================================

-- SECURE: Get user with validation
function M.get_user(username)
    if not username or username == "" then
        return nil
    end
    
    local red = connect_redis()
    if not red then return nil end
    
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        return nil
    end
    
    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end
    
    -- SECURITY: Validate required fields exist
    if not user.username or not user.password_hash then
        ngx.log(ngx.WARN, "Invalid user data structure for: " .. username)
        return nil
    end
    
    return user
end

-- SECURE: Create user with enhanced validation
function M.create_user(username, password_hash, ip_address)
    if not username or not password_hash then
        return false, "Missing required fields"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    
    -- SECURITY: Check if user exists
    if red:exists(user_key) == 1 then
        return false, "User already exists"
    end
    
    -- SECURITY: Create user with audit trail
    local user_data = {
        username = username,
        password_hash = password_hash,
        is_admin = "false",
        is_approved = "false",  -- CRITICAL: Default to pending approval
        created_at = os.date("!%Y-%m-%dT%TZ"),
        created_ip = ip_address or "unknown",
        login_count = "0",
        last_active = os.date("!%Y-%m-%dT%TZ")
    }
    
    for k, v in pairs(user_data) do
        red:hset(user_key, k, v)
    end
    
    ngx.log(ngx.INFO, "User created: " .. username .. " from IP: " .. (ip_address or "unknown"))
    return true, "User created"
end

-- SECURE: Update user activity with audit
function M.update_user_activity(username)
    if not username then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    red:hset("user:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))
    return true
end

-- SECURE: Update login info with security tracking
function M.update_user_login(username, ip_address)
    if not username then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    local user_key = "user:" .. username
    local login_count = tonumber(red:hget(user_key, "login_count") or "0") + 1
    
    red:hset(user_key, "login_count", tostring(login_count))
    red:hset(user_key, "last_login", os.date("!%Y-%m-%dT%TZ"))
    red:hset(user_key, "last_ip", ip_address or "unknown")
    
    return true
end

-- SECURE: Get all users (admin only operation)
function M.get_all_users()
    local red = connect_redis()
    if not red then return {} end
    
    local user_keys = red:keys("user:*")
    local users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                -- SECURITY: Don't return password hashes
                user.password_hash = nil
                table.insert(users, user)
            end
        end
    end
    
    return users
end

-- SECURE: Approve user with audit trail
function M.approve_user(username, admin_username)
    if not username or not admin_username then
        return false, "Missing required parameters"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    if red:exists(user_key) == 0 then
        return false, "User not found"
    end
    
    red:hset(user_key, "is_approved", "true")
    red:hset(user_key, "approved_by", admin_username)
    red:hset(user_key, "approved_at", os.date("!%Y-%m-%dT%TZ"))
    
    ngx.log(ngx.INFO, "User approved: " .. username .. " by admin: " .. admin_username)
    return true, "User approved"
end

-- SECURE: Toggle admin with validation
function M.toggle_admin(username, admin_username)
    if not username or not admin_username then
        return false, "Missing required parameters"
    end
    
    if username == admin_username then
        return false, "Cannot modify own admin status"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    if red:exists(user_key) == 0 then
        return false, "User not found"
    end
    
    local current_status = red:hget(user_key, "is_admin")
    local new_status = (current_status == "true") and "false" or "true"
    
    red:hset(user_key, "is_admin", new_status)
    red:hset(user_key, "admin_modified_by", admin_username)
    red:hset(user_key, "admin_modified_at", os.date("!%Y-%m-%dT%TZ"))
    
    -- SECURITY: If promoting to admin, ensure they're also approved
    if new_status == "true" then
        red:hset(user_key, "is_approved", "true")
        if not red:hget(user_key, "approved_by") then
            red:hset(user_key, "approved_by", admin_username)
            red:hset(user_key, "approved_at", os.date("!%Y-%m-%dT%TZ"))
        end
    end
    
    ngx.log(ngx.INFO, "Admin status changed for " .. username .. " to " .. new_status .. " by " .. admin_username)
    return true, "Admin status updated", new_status == "true"
end

-- SECURE: Delete user with audit
function M.delete_user(username)
    if not username then
        return false, "Username required"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    if red:exists(user_key) == 0 then
        return false, "User not found"
    end
    
    -- SECURITY: Archive user data before deletion
    local user_data = red:hgetall(user_key)
    if user_data and #user_data > 0 then
        local archive_key = "deleted_user:" .. username .. ":" .. ngx.time()
        for i = 1, #user_data, 2 do
            red:hset(archive_key, user_data[i], user_data[i + 1])
        end
        red:hset(archive_key, "deleted_at", os.date("!%Y-%m-%dT%TZ"))
        red:expire(archive_key, 2592000) -- Keep for 30 days
    end
    
    -- Delete user and related data
    red:del(user_key)
    red:del("chat:" .. username)
    
    local message_keys = red:keys("user_messages:" .. username .. ":*")
    for _, key in ipairs(message_keys) do
        red:del(key)
    end
    
    ngx.log(ngx.INFO, "User deleted: " .. username)
    return true, "User deleted"
end

-- =============================================
-- SECURE CHAT HISTORY (Redis for approved only)
-- =============================================

function M.save_message(username, role, content)
    if not username or not role or not content then
        return false
    end
    
    local red = connect_redis()
    if not red then return false end
    
    local chat_key = "chat:" .. username
    local message = {
        role = role,
        content = content,
        timestamp = os.date("!%Y-%m-%dT%TZ"),
        ip = ngx.var.remote_addr or "unknown"
    }
    
    red:lpush(chat_key, cjson.encode(message))
    red:ltrim(chat_key, 0, 99) -- Keep last 100 messages
    red:expire(chat_key, 604800) -- 1 week
    
    return true
end

function M.get_chat_history(username, limit)
    if not username then return {} end
    
    local red = connect_redis()
    if not red then return {} end
    
    limit = math.min(limit or 20, 100)
    local chat_key = "chat:" .. username
    local history = red:lrange(chat_key, 0, limit - 1)
    local messages = {}
    
    for i = #history, 1, -1 do
        local ok, message = pcall(cjson.decode, history[i])
        if ok and message.role and message.content then
            -- SECURITY: Don't return IP addresses to client
            table.insert(messages, {
                role = message.role,
                content = message.content,
                timestamp = message.timestamp
            })
        end
    end
    
    return messages
end

function M.clear_chat_history(username)
    if not username then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    red:del("chat:" .. username)
    ngx.log(ngx.INFO, "Chat history cleared for user: " .. username)
    return true
end

-- =============================================
-- SECURE RATE LIMITING (Redis)
-- =============================================

function M.check_rate_limit(username, is_admin)
    if not username then return true end
    
    local red = connect_redis()
    if not red then return true end -- Allow if Redis down
    
    local time_window = 3600 -- 1 hour
    local current_time = ngx.time()
    local window_start = current_time - time_window
    local count_key = "user_messages:" .. username
    
    -- SECURITY: Different limits for admins vs users
    local limit = is_admin and ADMIN_RATE_LIMIT or USER_RATE_LIMIT
    
    -- Clean old entries and count current window
    red:zremrangebyscore(count_key, 0, window_start)
    local current_count = red:zcard(count_key)
    
    if current_count >= limit then
        ngx.log(ngx.WARN, "Rate limit exceeded for user: " .. username .. " (" .. current_count .. "/" .. limit .. ")")
        return false, "Rate limit exceeded (" .. current_count .. "/" .. limit .. " messages per hour)"
    end
    
    -- Add current message
    red:zadd(count_key, current_time, current_time .. ":" .. math.random(1000, 9999))
    red:expire(count_key, time_window + 60)
    
    return true, "OK"
end

-- =============================================
-- SECURE SSE SESSION MANAGEMENT 
-- =============================================

local function get_user_priority(user_type)
    if user_type == "admin" then return 1 end
    if user_type == "approved" then return 2 end
    if user_type == "guest" then return 3 end
    return 4
end

local function cleanup_expired_sse_sessions()
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
                end
            end
        end
    end
    
    return cleaned
end

function M.can_start_sse_session(user_type, username)
    if not user_type or not username then
        return false, "Missing parameters"
    end
    
    cleanup_expired_sse_sessions()
    
    local priority = get_user_priority(user_type)
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local active_sessions = {}
    
    -- Count active sessions and check for duplicates
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                table.insert(active_sessions, session)
                
                -- SECURITY: Prevent multiple sessions per user
                if session.username == username then
                    return false, "User already has active session"
                end
            end
        end
    end
    
    -- Check capacity
    if #active_sessions < MAX_SSE_SESSIONS then
        return true, "Session allowed"
    end
    
    -- SECURITY: Admins can kick lower priority sessions
    if user_type == "admin" then
        return true, "Admin session granted"
    end
    
    return false, "No available slots"
end

function M.start_sse_session(user_type, username)
    local can_start, message = M.can_start_sse_session(user_type, username)
    if not can_start then
        return false, message
    end
    
    local session_id = username .. "_sse_" .. ngx.time() .. "_" .. math.random(1000, 9999)
    local session = {
        session_id = session_id,
        username = username,
        user_type = user_type,
        priority = get_user_priority(user_type),
        created_at = ngx.time(),
        last_activity = ngx.time(),
        remote_addr = ngx.var.remote_addr or "unknown"
    }
    
    ngx.shared.sse_sessions:set("sse:" .. session_id, cjson.encode(session), SESSION_TIMEOUT + 60)
    
    ngx.log(ngx.INFO, "Started SSE session: " .. session_id .. " (user: " .. username .. ", type: " .. user_type .. ")")
    
    return true, session_id
end

function M.update_sse_activity(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false
    end
    
    local session = cjson.decode(session_info)
    session.last_activity = ngx.time()
    
    ngx.shared.sse_sessions:set(session_key, cjson.encode(session), SESSION_TIMEOUT + 60)
    return true
end

function M.end_sse_session(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    ngx.shared.sse_sessions:delete(session_key)
    
    ngx.log(ngx.INFO, "Ended SSE session: " .. session_id)
    return true
end

function M.get_sse_stats()
    cleanup_expired_sse_sessions()
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local active_sessions = 0
    
    local stats = {
        total_sessions = 0,
        max_sessions = MAX_SSE_SESSIONS,
        available_slots = 0,
        by_priority = {
            admin_sessions = 0,
            approved_sessions = 0,
            guest_sessions = 0
        }
    }
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                active_sessions = active_sessions + 1
                
                if session.priority == 1 then
                    stats.by_priority.admin_sessions = stats.by_priority.admin_sessions + 1
                elseif session.priority == 2 then
                    stats.by_priority.approved_sessions = stats.by_priority.approved_sessions + 1
                elseif session.priority == 3 then
                    stats.by_priority.guest_sessions = stats.by_priority.guest_sessions + 1
                end
            end
        end
    end
    
    stats.total_sessions = active_sessions
    stats.available_slots = MAX_SSE_SESSIONS - active_sessions
    
    return stats
end

function M.get_all_sse_sessions()
    cleanup_expired_sse_sessions()
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local sessions = {}
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local session = cjson.decode(session_info)
                table.insert(sessions, {
                    session_id = session.session_id,
                    username = session.username,
                    user_type = session.user_type,
                    priority = session.priority,
                    created_at = session.created_at,
                    last_activity = session.last_activity,
                    age_seconds = ngx.time() - session.created_at,
                    inactive_seconds = ngx.time() - session.last_activity,
                    remote_addr = session.remote_addr
                })
            end
        end
    end
    
    -- Sort by priority then age
    table.sort(sessions, function(a, b)
        if a.priority == b.priority then
            return a.created_at < b.created_at
        end
        return a.priority < b.priority
    end)
    
    return sessions, #sessions, MAX_SSE_SESSIONS
end

function M.kick_sse_session(session_id, admin_username)
    if not session_id or not admin_username then
        return false, "Missing parameters"
    end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false, "Session not found"
    end
    
    local session = cjson.decode(session_info)
    
    -- SECURITY: Don't kick admin sessions unless by admin
    if session.priority == 1 then
        return false, "Cannot kick admin session"
    end
    
    ngx.shared.sse_sessions:delete(session_key)
    
    ngx.log(ngx.WARN, "Admin " .. admin_username .. " kicked SSE session: " .. session_id .. " (user: " .. session.username .. ")")
    
    return true, "Session kicked"
end

-- =============================================
-- SECURE GUEST SESSION MANAGEMENT
-- =============================================

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
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = ngx.var.remote_addr or "unknown"
    }
    
    -- Store in shared memory
    local guest_key = "guest_session:" .. guest_username
    ngx.shared.guest_sessions:set(guest_key, cjson.encode(session_data), GUEST_SESSION_DURATION)
    
    -- SECURITY: HttpOnly cookie
    ngx.header["Set-Cookie"] = "guest_token=" .. guest_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    ngx.log(ngx.INFO, "Guest session created: " .. guest_username .. " from IP: " .. (ngx.var.remote_addr or "unknown"))
    
    return session_data
end

function M.get_guest_session(username)
    if not username then return nil end
    
    local guest_key = "guest_session:" .. username
    local guest_data = ngx.shared.guest_sessions:get(guest_key)
    
    if not guest_data then
        return nil
    end
    
    local session = cjson.decode(guest_data)
    if ngx.time() >= session.expires_at then
        ngx.shared.guest_sessions:delete(guest_key)
        return nil
    end
    
    return session
end

function M.get_guest_limits(username)
    local session = M.get_guest_session(username)
    if not session then
        return nil
    end
    
    return {
        max_messages = session.max_messages,
        used_messages = session.message_count,
        remaining_messages = session.max_messages - session.message_count,
        session_remaining = session.expires_at - ngx.time()
    }
end

function M.use_guest_message(username)
    if not username then
        return false, "Username required"
    end
    
    local guest_key = "guest_session:" .. username
    local guest_data = ngx.shared.guest_sessions:get(guest_key)
    
    if not guest_data then
        return false, "Session not found"
    end
    
    local session = cjson.decode(guest_data)
    
    if session.message_count >= session.max_messages then
        return false, "Message limit exceeded"
    end
    
    session.message_count = session.message_count + 1
    session.last_used = ngx.time()
    ngx.shared.guest_sessions:set(guest_key, cjson.encode(session), GUEST_SESSION_DURATION)
    
    return true, "Message allowed"
end

-- =============================================
-- SECURE OLLAMA INTEGRATION
-- =============================================

function M.call_ollama_streaming(messages, options, callback)
    if not messages or #messages == 0 then
        return nil, "No messages provided"
    end
    
    local httpc = http.new()
    httpc:set_timeout((options.timeout or 300) * 1000)

    -- SECURITY: Validate and sanitize options
    local safe_options = {
        temperature = math.min(math.max(options.temperature or 0.7, 0), 1),
        num_predict = math.min(options.max_tokens or 2048, 4096),
        num_ctx = tonumber(os.getenv("OLLAMA_CONTEXT_SIZE")) or 1024,
        num_gpu = tonumber(os.getenv("OLLAMA_GPU_LAYERS")) or 8,
        num_thread = tonumber(os.getenv("OLLAMA_NUM_THREAD")) or 6,
        num_batch = tonumber(os.getenv("OLLAMA_BATCH_SIZE")) or 64,
        use_mmap = false,
        use_mlock = true
    }

    local payload = {
        model = OLLAMA_MODEL,
        messages = messages,
        stream = true,
        options = safe_options
    }

    local res, err = httpc:request_uri(OLLAMA_URL .. "/api/chat", {
        method = "POST",
        body = cjson.encode(payload),
        headers = { 
            ["Content-Type"] = "application/json",
            ["Accept"] = "text/event-stream",
            ["User-Agent"] = "nginx-lua-client"
        }
    })

    if not res then
        ngx.log(ngx.ERR, "Ollama connection failed: " .. (err or "unknown"))
        return nil, "Failed to connect to AI service: " .. (err or "unknown")
    end

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Ollama HTTP error: " .. res.status)
        return nil, "AI service error: HTTP " .. res.status
    end

    local accumulated = ""
    local chunk_count = 0
    
    -- SECURITY: Process response line by line with limits
    for line in res.body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            chunk_count = chunk_count + 1
            
            -- SECURITY: Prevent excessive chunks
            if chunk_count > 1000 then
                ngx.log(ngx.WARN, "Ollama response chunk limit exceeded")
                break
            end
            
            local ok, data = pcall(cjson.decode, line)
            if ok and data.message and data.message.content then
                accumulated = accumulated .. data.message.content
                
                -- SECURITY: Prevent excessive response length
                if #accumulated > 10000 then
                    ngx.log(ngx.WARN, "Ollama response length limit exceeded")
                    callback({
                        content = "\n\n[Response truncated - too long]",
                        accumulated = accumulated .. "\n\n[Response truncated - too long]",
                        done = true
                    })
                    break
                end
                
                callback({
                    content = data.message.content,
                    accumulated = accumulated,
                    done = data.done or false
                })
                
                if data.done then
                    break
                end
            end
        end
    end

    httpc:close()
    return accumulated, nil
end

return M