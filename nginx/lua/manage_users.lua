-- =============================================================================
-- nginx/lua/user_manager.lua - User management functions
-- =============================================================================

local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Rate limiting configuration
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
-- BASIC USER MANAGEMENT
-- =============================================

function M.get_user(username)
    if not username or username == "" then
        return "is_none"
    end
    
    local red = connect_redis()
    if not red then return nil end
    
    local user_key = "username:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        return "is_none"
    end
    
    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end
    
    if not user.username or not user.password_hash then
        return "is_none"
    end
    
    return user
end

function M.create_user(username, password_hash, ip_address)
    if not username or not password_hash then
        return false, "Missing required fields"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "username:" .. username
    
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
        user_type = "is_pending",
        created_at = current_time,
        created_ip = ip_address or "unknown",
        login_count = "0",
        last_active = current_time
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
    
    red:hset("username:" .. username, "last_active", os.date("!%Y-%m-%dT%TZ"))
    return true
end

function M.get_all_users()
    local red = connect_redis()
    if not red then return {} end
    
    local user_keys = redis_to_lua(red:keys("username:*")) or {}
    local users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "username:" then
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

function M.get_user_counts()
    local red = connect_redis()
    if not red then return { total = 0, pending = 0, approved = 0, admin = 0 } end
    
    local user_keys = redis_to_lua(red:keys("username:*")) or {}
    local counts = { total = 0, guest = 0, pending = 0, approved = 0, admin = 0 }
    
    for _, key in ipairs(user_keys) do
        if key ~= "username:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                
                if user.username then
                    counts.total = counts.total + 1
                    if user.user_type == "is_admin" then
                        counts.admin = counts.admin + 1
                    end
                    if user.user_type == "is_approved" then
                        counts.approved = counts.approved + 1
                    end
                    if user.user_type == "is_pending" then
                        counts.pending = counts.pending + 1
                    end
                    if user.user_type == "is_guest" then
                        counts.guest = counts.guest + 1
                    end
                end
            end
        end
    end
    
    red:close()
    return counts
end

function M.get_pending_users()
    local red = connect_redis()
    if not red then return {} end
    
    local user_keys = redis_to_lua(red:keys("username:*")) or {}
    local pending_users = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "username:" then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    user[user_data[i]] = user_data[i + 1]
                end
                
                if user.username and user.user_type == "is_pending" then
                    user.password_hash = nil
                    table.insert(pending_users, user)
                end
            end
        end
    end
    
    red:close()
    
    table.sort(pending_users, function(a, b)
        return (a.created_at or "") > (b.created_at or "")
    end)
    
    return pending_users
end

function M.approve_user(username, approved_by)
    if not username or not approved_by then
        return false, "Missing required parameters"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "username:" .. username
    
    if red:exists(user_key) ~= 1 then
        red:close()
        return false, "User not found"
    end
    
    red:hset(user_key, "user_type:", "is_approved")
    red:hset(user_key, "approved_at:", os.date("!%Y-%m-%dT%TZ"))
    red:hset(user_key, "approved_by:", approved_by)
    red:hset(user_key, "last_active:", os.date("!%Y-%m-%dT%TZ"))
    
    red:close()
    
    ngx.log(ngx.INFO, "User approved: " .. username .. " by " .. approved_by)
    return true, "User approved successfully"
end

function M.reject_user(username, rejected_by, reason)
    if not username or not rejected_by then
        return false, "Missing required parameters"
    end
    
    local red = connect_redis()
    if not red then return false, "Service unavailable" end
    
    local user_key = "username:" .. username
    
    if red:exists(user_key) ~= 1 then
        red:close()
        return false, "User not found"
    end
    
    ngx.log(ngx.INFO, "User rejected and deleted: " .. username .. " by " .. rejected_by .. 
            (reason and (" - Reason: " .. reason) or ""))
    
    red:del(user_key)
    red:del("chat:" .. username)
    red:del("user_messages:" .. username)
    
    red:close()
    
    return true, "User rejected and account deleted"
end

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

return M