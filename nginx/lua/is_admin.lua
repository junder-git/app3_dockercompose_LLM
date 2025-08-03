-- =============================================================================
-- nginx/lua/manage_admin.lua - ADMIN SYSTEM MANAGEMENT FUNCTIONS
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- USER MANAGEMENT FUNCTIONS
-- =============================================

-- Get all users from Redis
function M.get_all_users()
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local user_keys = red:keys("username:*")
    local users = {}
    
    for _, key in ipairs(user_keys) do
        local username = string.match(key, "username:(.+)")
        if username then
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    local field = user_data[i]
                    local value = auth.redis_to_lua(user_data[i + 1])
                    user[field] = value
                end
                user.key = key
                table.insert(users, user)
            end
        end
    end
    
    red:close()
    return users, nil
end

-- Get pending users only
function M.get_pending_users()
    local all_users, err = M.get_all_users()
    if err then
        return {}, err
    end
    
    local pending_users = {}
    for _, user in ipairs(all_users) do
        if user.user_type == "pending" then
            table.insert(pending_users, user)
        end
    end
    
    return pending_users, nil
end

-- Approve a user
function M.approve_user(username)
    if not username then
        return false, "Username required"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    local result = red:hset(user_key, "user_type", "approved")
    red:close()
    
    if result then
        ngx.log(ngx.INFO, "User approved: " .. username)
        return true, "User approved successfully"
    else
        return false, "Failed to approve user"
    end
end

-- Reject/delete a user
function M.reject_user(username)
    if not username then
        return false, "Username required"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    local result = red:del(user_key)
    red:close()
    
    if result and result > 0 then
        ngx.log(ngx.INFO, "User rejected/deleted: " .. username)
        return true, "User rejected successfully"
    else
        return false, "Failed to reject user or user not found"
    end
end

-- Change user type
function M.change_user_type(username, new_type)
    if not username or not new_type then
        return false, "Username and new type required"
    end
    
    local valid_types = {admin = true, approved = true, pending = true, guest = true}
    if not valid_types[new_type] then
        return false, "Invalid user type"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local user_key = "username:" .. username
    local result = red:hset(user_key, "user_type", new_type)
    red:close()
    
    if result then
        ngx.log(ngx.INFO, "User type changed: " .. username .. " -> " .. new_type)
        return true, "User type changed successfully"
    else
        return false, "Failed to change user type"
    end
end

-- =============================================
-- SYSTEM STATISTICS
-- =============================================

function M.get_system_stats()
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    -- Get user counts by type
    local user_keys = red:keys("username:*")
    local stats = {
        total_users = 0,
        admin_users = 0,
        approved_users = 0,
        pending_users = 0,
        guest_users = 0,
        chat_histories = 0,
        guest_sessions = 0
    }
    
    -- Count users by type
    for _, key in ipairs(user_keys) do
        local user_type = red:hget(key, "user_type")
        if user_type then
            stats.total_users = stats.total_users + 1
            if user_type == "admin" then
                stats.admin_users = stats.admin_users + 1
            elseif user_type == "approved" then
                stats.approved_users = stats.approved_users + 1
            elseif user_type == "pending" then
                stats.pending_users = stats.pending_users + 1
            elseif user_type == "guest" then
                stats.guest_users = stats.guest_users + 1
            end
        end
    end
    
    -- Count chat histories
    local chat_keys = red:keys("chat_history:*")
    stats.chat_histories = #chat_keys
    
    -- Count guest sessions (if stored in Redis)
    local guest_session_keys = red:keys("guest_session:*")
    stats.guest_sessions = #guest_session_keys
    
    red:close()
    return stats, nil
end

-- =============================================
-- GUEST SESSION MANAGEMENT
-- =============================================

function M.clear_guest_sessions()
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    -- Clear guest users
    local guest_user_keys = red:keys("username:guest_user_*")
    local cleared_users = 0
    
    for _, key in ipairs(guest_user_keys) do
        red:del(key)
        cleared_users = cleared_users + 1
    end
    
    -- Clear guest sessions (if stored in Redis)
    local guest_session_keys = red:keys("guest_session:*")
    for _, key in ipairs(guest_session_keys) do
        red:del(key)
    end
    
    red:close()
    
    ngx.log(ngx.INFO, "Cleared " .. cleared_users .. " guest sessions")
    return true, "Cleared " .. cleared_users .. " guest sessions"
end

-- =============================================
-- ADMIN API HANDLERS
-- =============================================

function M.handle_get_all_users()
    local users, err = M.get_all_users()
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        users = users,
        count = #users
    }))
end

function M.handle_get_pending_users()
    local users, err = M.get_pending_users()
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        pending_users = users,
        count = #users
    }))
end

function M.handle_approve_user()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({error = "No request body"}))
        return
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok or not data.username then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({error = "Username required"}))
        return
    end
    
    local success, message = M.approve_user(data.username)
    ngx.status = success and 200 or 500
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = success,
        message = message,
        username = data.username
    }))
end

function M.handle_reject_user()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({error = "No request body"}))
        return
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok or not data.username then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({error = "Username required"}))
        return
    end
    
    local success, message = M.reject_user(data.username)
    ngx.status = success and 200 or 500
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = success,
        message = message,
        username = data.username
    }))
end

function M.handle_system_stats()
    local stats, err = M.get_system_stats()
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        stats = stats
    }))
end

function M.handle_clear_guest_sessions()
    local success, message = M.clear_guest_sessions()
    ngx.status = success and 200 or 500
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = success,
        message = message
    }))
end

return M