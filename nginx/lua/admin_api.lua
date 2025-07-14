-- nginx/lua/admin_users_api.lua - Real admin API for user management
local cjson = require "cjson"
local redis = require "resty.redis"
local session_manager = require "unified_session_manager"

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
        send_json(500, { error = "Internal server error", details = "Redis connection failed" })
    end
    return red
end

-- Get all users from Redis
local function handle_get_users()
    local admin_username = ngx.var.auth_username
    local red = connect_redis()
    
    local user_keys = red:keys("user:*")
    local users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" and key ~= "user:admin" then -- Skip invalid keys
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                
                -- Format user data for frontend
                table.insert(users, {
                    id = user.id or key,
                    username = user.username,
                    isApproved = user.is_approved == "true",
                    isAdmin = user.is_admin == "true",
                    createdAt = user.created_at or "Unknown",
                    lastActive = user.last_active or nil,
                    lastLogin = user.last_login or nil,
                    approvedBy = user.approved_by or nil,
                    approvedAt = user.approved_at or nil
                })
            end
        end
    end
    
    -- Sort users by creation date (newest first)
    table.sort(users, function(a, b)
        if a.createdAt == "Unknown" then return false end
        if b.createdAt == "Unknown" then return true end
        return a.createdAt > b.createdAt
    end)
    
    send_json(200, {
        success = true,
        users = users,
        count = #users,
        admin_user = admin_username
    })
end

-- Get user statistics
local function handle_get_stats()
    local admin_username = ngx.var.auth_username
    local red = connect_redis()
    
    local user_keys = red:keys("user:*")
    local stats = {
        totalUsers = 0,
        pendingUsers = 0,
        approvedUsers = 0,
        adminUsers = 0,
        activeToday = 0,
        messagesTotal = 0
    }
    
    local today = os.date("%Y-%m-%d")
    local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                
                stats.totalUsers = stats.totalUsers + 1
                
                if user.is_admin == "true" then
                    stats.adminUsers = stats.adminUsers + 1
                elseif user.is_approved == "true" then
                    stats.approvedUsers = stats.approvedUsers + 1
                else
                    stats.pendingUsers = stats.pendingUsers + 1
                end
                
                -- Check if active today
                if user.last_active then
                    local last_active_date = string.sub(user.last_active, 1, 10)
                    if last_active_date == today then
                        stats.activeToday = stats.activeToday + 1
                    end
                end
                
                -- Count messages (approximate)
                local message_keys = red:keys("user_messages:" .. user.username .. ":*")
                stats.messagesTotal = stats.messagesTotal + #message_keys
            end
        end
    end
    
    -- Get SSE session stats
    local sse_stats = session_manager.get_session_stats()
    
    send_json(200, {
        success = true,
        stats = stats,
        sse_sessions = sse_stats,
        admin_user = admin_username
    })
end

-- Approve user
local function handle_approve_user()
    local admin_username = ngx.var.auth_username
    local red = connect_redis()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username

    if not username then
        send_json(400, { error = "Username required" })
    end

    local user_key = "user:" .. username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        send_json(404, { error = "User not found" })
    end

    -- Update user approval status
    red:hset(user_key, "is_approved", "true")
    red:hset(user_key, "approved_by", admin_username)
    red:hset(user_key, "approved_at", os.date("!%Y-%m-%dT%TZ"))

    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " approved user ", username)

    send_json(200, { 
        success = true, 
        message = "User approved successfully",
        username = username,
        approved_by = admin_username
    })
end

-- Toggle admin status
local function handle_toggle_admin()
    local admin_username = ngx.var.auth_username
    local red = connect_redis()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username

    if not username then
        send_json(400, { error = "Username required" })
    end

    -- Prevent admin from removing their own admin status
    if username == admin_username then
        send_json(400, { error = "Cannot modify your own admin status" })
    end

    local user_key = "user:" .. username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        send_json(404, { error = "User not found" })
    end

    -- Get current admin status
    local current_admin_status = red:hget(user_key, "is_admin")
    local new_admin_status = (current_admin_status == "true") and "false" or "true"
    
    -- Update admin status
    red:hset(user_key, "is_admin", new_admin_status)
    red:hset(user_key, "admin_modified_by", admin_username)
    red:hset(user_key, "admin_modified_at", os.date("!%Y-%m-%dT%TZ"))

    -- If removing admin status, also ensure user is approved
    if new_admin_status == "false" then
        red:hset(user_key, "is_approved", "true")
    end

    local action = (new_admin_status == "true") and "granted" or "revoked"
    
    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " ", action, " admin privileges for user ", username)

    send_json(200, { 
        success = true, 
        message = "Admin status " .. action .. " successfully",
        username = username,
        is_admin = new_admin_status == "true",
        modified_by = admin_username
    })
end

-- Delete user
local function handle_delete_user()
    local admin_username = ngx.var.auth_username
    local red = connect_redis()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username

    if not username then
        send_json(400, { error = "Username required" })
    end

    -- Prevent admin from deleting themselves
    if username == admin_username then
        send_json(400, { error = "Cannot delete your own account" })
    end

    local user_key = "user:" .. username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        send_json(404, { error = "User not found" })
    end

    -- Delete user and related data
    red:del(user_key)
    
    -- Delete user chat history
    local chat_key = "chat:" .. username
    red:del(chat_key)
    
    -- Delete user message counts and related data
    local message_keys = red:keys("user_messages:" .. username .. ":*")
    for _, key in ipairs(message_keys) do
        red:del(key)
    end
    
    -- Delete any user-specific rate limiting data
    local rate_limit_key = "user_messages:" .. username
    red:del(rate_limit_key)

    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " deleted user ", username)

    send_json(200, { 
        success = true, 
        message = "User deleted successfully",
        username = username,
        deleted_by = admin_username
    })
end

-- Bulk approve all pending users
local function handle_approve_all()
    local admin_username = ngx.var.auth_username
    local red = connect_redis()
    
    local user_keys = red:keys("user:*")
    local approved_count = 0
    local approved_users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                
                if user.is_approved ~= "true" and user.is_admin ~= "true" then
                    red:hset(key, "is_approved", "true")
                    red:hset(key, "approved_by", admin_username)
                    red:hset(key, "approved_at", os.date("!%Y-%m-%dT%TZ"))
                    approved_count = approved_count + 1
                    table.insert(approved_users, user.username)
                end
            end
        end
    end

    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " bulk approved ", approved_count, " users: ", table.concat(approved_users, ", "))

    send_json(200, { 
        success = true, 
        message = approved_count .. " users approved successfully",
        count = approved_count,
        users = approved_users,
        approved_by = admin_username
    })
end

-- Get user activity/sessions
local function handle_get_user_activity()
    local admin_username = ngx.var.auth_username
    
    -- Get SSE session data
    local sse_data = session_manager.get_all_sse_sessions()
    
    -- Get guest session data (simplified)
    local guest_sessions = {}
    local guest_keys = ngx.shared.guest_sessions:get_keys(0)
    
    for _, key in ipairs(guest_keys) do
        if string.match(key, "^guest_session:") then
            local guest_data = ngx.shared.guest_sessions:get(key)
            if guest_data then
                local session = cjson.decode(guest_data)
                local remaining = session.expires_at - ngx.time()
                if remaining > 0 then
                    table.insert(guest_sessions, {
                        username = session.username,
                        session_type = "guest",
                        created_at = session.created_at,
                        expires_at = session.expires_at,
                        remaining_seconds = remaining,
                        message_count = session.message_count,
                        max_messages = session.max_messages
                    })
                end
            end
        end
    end
    
    send_json(200, {
        success = true,
        sse_sessions = sse_data,
        guest_sessions = guest_sessions,
        total_active_sessions = sse_data.count + #guest_sessions,
        capacity = {
            max_sse_sessions = session_manager.MAX_SSE_SESSIONS,
            current_sse_sessions = sse_data.count,
            available_sse_slots = session_manager.MAX_SSE_SESSIONS - sse_data.count
        },
        admin_user = admin_username
    })
end

-- Main API router
local function handle_admin_users_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/admin/users" and method == "GET" then
        handle_get_users()
    elseif uri == "/api/admin/stats" and method == "GET" then
        handle_get_stats()
    elseif uri == "/api/admin/approve-user" and method == "POST" then
        handle_approve_user()
    elseif uri == "/api/admin/toggle-admin" and method == "POST" then
        handle_toggle_admin()
    elseif uri == "/api/admin/delete-user" and method == "DELETE" then
        handle_delete_user()
    elseif uri == "/api/admin/approve-all" and method == "POST" then
        handle_approve_all()
    elseif uri == "/api/admin/activity" and method == "GET" then
        handle_get_user_activity()
    elseif string.match(uri, "^/api/admin/sse") then
        -- Delegate SSE session management to separate module
        local sse_api = require "admin_sse_api"
        sse_api.handle_admin_session_api()
    else
        send_json(404, { error = "Admin API endpoint not found" })
    end
end

return {
    handle_admin_users_api = handle_admin_users_api,
    handle_get_users = handle_get_users,
    handle_get_stats = handle_get_stats,
    handle_approve_user = handle_approve_user,
    handle_toggle_admin = handle_toggle_admin,
    handle_delete_user = handle_delete_user,
    handle_approve_all = handle_approve_all,
    handle_get_user_activity = handle_get_user_activity
}