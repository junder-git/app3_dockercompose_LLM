-- nginx/lua/server.lua - CORE SERVER FUNCTIONS (NO DUPLICATION)
local cjson = require "cjson"
local redis = require "resty.redis"
local http = require "resty.http"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local OLLAMA_URL = os.getenv("OLLAMA_URL") or "http://ollama:11434"
local OLLAMA_MODEL = os.getenv("OLLAMA_MODEL") or "devstral"

-- Configuration
local MAX_SSE_SESSIONS = 3
local SESSION_TIMEOUT = 300
local USER_RATE_LIMIT = 60
local ADMIN_RATE_LIMIT = 120

local M = {}

-- HELPER: Safe Redis response handling
local function redis_to_lua(value)
    if value == ngx.null or value == nil then
        return nil
    end
    return value
end

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
-- USER MANAGEMENT
-- =============================================

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
    
    if not user.username or not user.password_hash then
        return nil
    end
    
    return user
end

function M.create_user(username, password_hash, ip_address)
    if not username or not password_hash then
        return false, "Missing required fields"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    
    -- Check if user already exists
    if red:exists(user_key) == 1 then
        red:close()
        return false, "User already exists"
    end
    
    -- Validate username doesn't conflict with guest accounts
    if string.match(username, "^guest_slot_") then
        red:close()
        return false, "Username conflicts with system accounts"
    end
    
    local current_time = os.date("!%Y-%m-%dT%TZ")
    local user_data = {
        username = username,
        password_hash = password_hash,
        is_admin = "false",
        is_approved = "false",  -- Default to pending
        created_at = current_time,
        created_ip = ip_address or "unknown",
        login_count = "0",
        last_active = current_time,
        status = "pending_approval"
    }
    
    -- Store user data
    for k, v in pairs(user_data) do
        red:hset(user_key, k, v)
    end
    
    red:close()
    
    ngx.log(ngx.INFO, "New user created (pending): " .. username .. " from " .. (ip_address or "unknown"))
    return true, "User created successfully"
end

function M.update_user_activity(username)
    if not username then return false end
    
    local red = connect_redis()
    if not red then return false end
    
    red:hset("user:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))
    return true
end

function M.get_all_users()
    local red = connect_redis()
    if not red then return {} end
    
    local user_keys = redis_to_lua(red:keys("user:*")) or {}
    local users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                user.password_hash = nil -- Don't return password hashes
                table.insert(users, user)
            end
        end
    end
    
    return users
end

function M.verify_password(password, stored_hash)
    if not password or not stored_hash then
        return false
    end
    
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    
    return hash == stored_hash
end

-- =============================================
-- ENHANCED USER MANAGEMENT WITH APPROVAL SYSTEM
-- =============================================

-- Get user counts by status (for admin dashboard)
function M.get_user_counts()
    local red = connect_redis()
    if not red then return { total = 0, pending = 0, approved = 0, admin = 0 } end
    
    local user_keys = redis_to_lua(red:keys("user:*")) or {}
    local counts = { total = 0, pending = 0, approved = 0, admin = 0 }
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                
                if user.username then
                    counts.total = counts.total + 1
                    
                    if user.is_admin == "true" then
                        counts.admin = counts.admin + 1
                    elseif user.is_approved == "true" then
                        counts.approved = counts.approved + 1
                    else
                        counts.pending = counts.pending + 1
                    end
                end
            end
        end
    end
    
    red:close()
    return counts
end

-- Get pending users (for admin approval)
function M.get_pending_users()
    local red = connect_redis()
    if not red then return {} end
    
    local user_keys = redis_to_lua(red:keys("user:*")) or {}
    local pending_users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                
                -- Only pending users (not approved, not admin)
                if user.username and user.is_approved == "false" and user.is_admin == "false" then
                    user.password_hash = nil -- Don't return password hash
                    table.insert(pending_users, user)
                end
            end
        end
    end
    
    red:close()
    
    -- Sort by creation date (newest first)
    table.sort(pending_users, function(a, b)
        return (a.created_at or "") > (b.created_at or "")
    end)
    
    return pending_users
end

-- Approve a user (admin function)
function M.approve_user(username, approved_by)
    if not username or not approved_by then
        return false, "Missing required parameters"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    
    -- Check if user exists
    if red:exists(user_key) ~= 1 then
        red:close()
        return false, "User not found"
    end
    
    -- Get current user data
    local user_data = red:hgetall(user_key)
    if not user_data or #user_data == 0 then
        red:close()
        return false, "User data not found"
    end
    
    -- Update user status
    red:hset(user_key, "is_approved", "true")
    red:hset(user_key, "approved_at", os.date("!%Y-%m-%dT%TZ"))
    red:hset(user_key, "approved_by", approved_by)
    red:hset(user_key, "last_active", os.date("!%Y-%m-%dT%TZ"))
    
    red:close()
    
    ngx.log(ngx.INFO, "User approved: " .. username .. " by " .. approved_by)
    return true, "User approved successfully"
end

-- Reject a user (admin function)
function M.reject_user(username, rejected_by, reason)
    if not username or not rejected_by then
        return false, "Missing required parameters"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "user:" .. username
    
    -- Check if user exists
    if red:exists(user_key) ~= 1 then
        red:close()
        return false, "User not found"
    end
    
    -- Log rejection before deletion
    ngx.log(ngx.INFO, "User rejected and deleted: " .. username .. " by " .. rejected_by .. 
            (reason and (" - Reason: " .. reason) or ""))
    
    -- Delete user account
    red:del(user_key)
    
    -- Also clear any related data
    red:del("chat:" .. username)
    red:del("user_messages:" .. username)
    
    red:close()
    
    return true, "User rejected and account deleted"
end

-- Get registration statistics
function M.get_registration_stats()
    local user_counts = M.get_user_counts()
    return {
        total_users = user_counts.total,
        pending_users = user_counts.pending,
        approved_users = user_counts.approved,
        admin_users = user_counts.admin,
        registration_health = {
            pending_ratio = user_counts.total > 0 and (user_counts.pending / user_counts.total) or 0,
            status = user_counts.pending > 5 and "high_pending" or "normal"
        }
    }
end

-- =============================================
-- COMMON STREAMING FUNCTION
-- =============================================

function M.handle_chat_stream_common(stream_context)
    local cjson = require "cjson"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    -- Read request body
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        send_json(400, { error = "No request body" })
    end
    
    local ok, request_data = pcall(cjson.decode, body)
    if not ok then
        send_json(400, { error = "Invalid JSON" })
    end
    
    local message = request_data.message
    if not message or message == "" then
        send_json(400, { error = "Message is required" })
    end
    
    -- Execute pre-stream validation (user-specific)
    if stream_context.pre_stream_check then
        local check_ok, check_error = stream_context.pre_stream_check(message, request_data)
        if not check_ok then
            send_json(429, { error = check_error })
        end
    end
    
    -- Prepare messages for AI
    local messages = {}
    
    -- Add chat history if enabled
    if stream_context.include_history and request_data.include_history then
        local history = stream_context.get_history(stream_context.history_limit or 10)
        for _, msg in ipairs(history) do
            table.insert(messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end
    
    -- Add current user message
    table.insert(messages, {
        role = "user", 
        content = message
    })
    
    -- Save user message if enabled
    if stream_context.save_user_message then
        stream_context.save_user_message(message)
    end
    
    -- Set up SSE headers
    ngx.header.content_type = 'text/event-stream'
    ngx.header.cache_control = 'no-cache'
    ngx.header.connection = 'keep-alive'
    ngx.header.access_control_allow_origin = '*'
    
    -- Merge options with context defaults
    local options = request_data.options or {}
    if stream_context.default_options then
        for k, v in pairs(stream_context.default_options) do
            if options[k] == nil then
                options[k] = v
            end
        end
    end
    
    -- Stream response from Ollama
    local accumulated_response = ""
    
    local success, error_msg = M.call_ollama_streaming(messages, options, function(chunk)
        if chunk.content then
            accumulated_response = accumulated_response .. chunk.content
            
            -- Send chunk to client
            ngx.say("data: " .. cjson.encode({
                content = chunk.content,
                accumulated = chunk.accumulated,
                done = chunk.done
            }))
            ngx.flush(true)
        end
        
        if chunk.done then
            -- Send completion signal
            ngx.say("data: [DONE]")
            ngx.flush(true)
        end
    end)
    
    if not success then
        ngx.say("data: " .. cjson.encode({
            error = error_msg or "AI service unavailable",
            content = "*Error: " .. (error_msg or "AI service unavailable") .. "*",
            done = true
        }))
        ngx.say("data: [DONE]")
        ngx.flush(true)
        accumulated_response = "Error: " .. (error_msg or "AI service unavailable")
    end
    
    -- Save AI response if enabled
    if stream_context.save_ai_response and accumulated_response ~= "" then
        stream_context.save_ai_response(accumulated_response)
    end
    
    -- Execute post-stream cleanup
    if stream_context.post_stream_cleanup then
        stream_context.post_stream_cleanup(accumulated_response)
    end
    
    ngx.exit(200)
end

-- =============================================
-- CHAT HISTORY
-- =============================================

function M.save_message(username, role, content)
    if not username or string.match(username, "^guest_") then
        return false, "Guest users don't have persistent chat storage"
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
    red:ltrim(chat_key, 0, 99)
    red:expire(chat_key, 604800)
    
    return true
end

function M.get_chat_history(username, limit)
    if not username or string.match(username, "^guest_") then
        return {}, "Guest users don't have persistent chat history"
    end
    
    local red = connect_redis()
    if not red then return {} end
    
    limit = math.min(limit or 20, 100)
    local chat_key = "chat:" .. username
    local history = red:lrange(chat_key, 0, limit - 1)
    local messages = {}
    
    for i = #history, 1, -1 do
        local ok, message = pcall(cjson.decode, history[i])
        if ok and message.role and message.content then
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
    if not username or string.match(username, "^guest_") then
        return false, "Guest users don't have persistent chat history"
    end
    
    local red = connect_redis()
    if not red then return false end
    
    red:del("chat:" .. username)
    return true
end

-- =============================================
-- RATE LIMITING
-- =============================================

function M.check_rate_limit(username, is_admin, is_guest)
    if not username then return true end
    
    local red = connect_redis()
    if not red then return true end
    
    local time_window = 3600
    local current_time = ngx.time()
    local window_start = current_time - time_window
    local count_key = "user_messages:" .. username
    
    local limit = is_admin and ADMIN_RATE_LIMIT or USER_RATE_LIMIT
    
    red:zremrangebyscore(count_key, 0, window_start)
    local current_count = red:zcard(count_key)
    
    if current_count >= limit then
        return false, "Rate limit exceeded (" .. current_count .. "/" .. limit .. " messages per hour)"
    end
    
    red:zadd(count_key, current_time, current_time .. ":" .. math.random(1000, 9999))
    red:expire(count_key, time_window + 60)
    
    return true, "OK"
end

-- =============================================
-- SSE SESSION MANAGEMENT
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
                local ok, session = pcall(cjson.decode, session_info)
                if ok and current_time - session.last_activity > SESSION_TIMEOUT then
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
    
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local active_sessions = {}
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local ok, session = pcall(cjson.decode, session_info)
                if ok then
                    table.insert(active_sessions, session)
                    if session.username == username then
                        return false, "User already has active session"
                    end
                end
            end
        end
    end
    
    if #active_sessions < MAX_SSE_SESSIONS then
        return true, "Session allowed"
    end
    
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
    
    return true, session_id
end

function M.update_sse_activity(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false
    end
    
    local ok, session = pcall(cjson.decode, session_info)
    if not ok then
        return false
    end
    
    session.last_activity = ngx.time()
    ngx.shared.sse_sessions:set(session_key, cjson.encode(session), SESSION_TIMEOUT + 60)
    return true
end

function M.end_sse_session(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    ngx.shared.sse_sessions:delete(session_key)
    
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
                local ok, session = pcall(cjson.decode, session_info)
                if ok then
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
    end
    
    stats.total_sessions = active_sessions
    stats.available_slots = MAX_SSE_SESSIONS - active_sessions
    
    return stats
end

-- =============================================
-- OLLAMA INTEGRATION
-- =============================================

function M.call_ollama_streaming(messages, options, callback)
    if not messages or #messages == 0 then
        return nil, "No messages provided"
    end
    
    local httpc = http.new()
    httpc:set_timeout((options.timeout or 300) * 1000)

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
        return nil, "Failed to connect to AI service: " .. (err or "unknown")
    end

    if res.status ~= 200 then
        return nil, "AI service error: HTTP " .. res.status
    end

    local accumulated = ""
    local chunk_count = 0
    
    for line in res.body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            chunk_count = chunk_count + 1
            
            if chunk_count > 1000 then
                break
            end
            
            local ok, data = pcall(cjson.decode, line)
            if ok and data.message and data.message.content then
                accumulated = accumulated .. data.message.content
                
                if #accumulated > 10000 then
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