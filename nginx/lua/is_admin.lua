-- =============================================================================
-- nginx/lua/is_admin.lua - ADMIN API HANDLERS ONLY (VIEWS HANDLED BY manage_views.lua)
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- ADMIN API HANDLERS
-- =============================================

local function handle_admin_stats()
    -- Get comprehensive system statistics
    local stats = {
        guest_sessions = {
            active_sessions = 0,
            max_sessions = 2,
            available_slots = 2,
            challenges_active = 0
        },
        sse_sessions = {
            total_sessions = 0,
            max_sessions = 3,
            available_slots = 3,
            by_priority = {
                admin_sessions = 0,
                approved_sessions = 0,
                guest_sessions = 0
            }
        },
        user_counts = {
            total = 0,
            approved = 0,
            pending = 0,
            admin = 0
        },
        registration = {
            registration_health = {
                status = "healthy",
                pending_ratio = 0.0
            }
        },
        ai_engine = "Devstral"
    }
    
    -- Get guest session stats
    local is_guest = require "is_guest"
    if is_guest.get_guest_stats then
        stats.guest_sessions = is_guest.get_guest_stats()
    end
    
    -- Get SSE session stats
    local sse_manager = require "manage_stream_sse"
    if sse_manager.get_sse_stats then
        stats.sse_sessions = sse_manager.get_sse_stats()
    end
    
    -- Get user counts from database
    local red = auth.connect_redis()
    if red then
        local user_keys = red:keys("username:*") or {}
        stats.user_counts.total = #user_keys
        
        for _, key in ipairs(user_keys) do
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    local field_key = user_data[i]
                    if string.sub(field_key, -1) == ":" then
                        field_key = string.sub(field_key, 1, -2)
                    end
                    user[field_key] = user_data[i + 1]
                end
                
                if user.user_type == "is_admin" then
                    stats.user_counts.admin = stats.user_counts.admin + 1
                elseif user.user_type == "is_approved" then
                    stats.user_counts.approved = stats.user_counts.approved + 1
                elseif user.user_type == "is_pending" then
                    stats.user_counts.pending = stats.user_counts.pending + 1
                end
            end
        end
        
        red:close()
    end
    
    -- Calculate registration health
    if stats.user_counts.total > 0 then
        stats.registration.registration_health.pending_ratio = stats.user_counts.pending / stats.user_counts.total
        if stats.registration.registration_health.pending_ratio > 0.5 then
            stats.registration.registration_health.status = "high_pending"
        end
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        stats = stats
    }))
end

local function handle_pending_users()
    local red = auth.connect_redis()
    if not red then
        ngx.status = 503
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Database unavailable"
        }))
        return
    end
    
    local user_keys = red:keys("username:*") or {}
    local pending_users = {}
    local count = 0
    
    for _, key in ipairs(user_keys) do
        local user_data = red:hgetall(key)
        if user_data and #user_data > 0 then
            local user = {}
            for i = 1, #user_data, 2 do
                local field_key = user_data[i]
                if string.sub(field_key, -1) == ":" then
                    field_key = string.sub(field_key, 1, -2)
                end
                user[field_key] = user_data[i + 1]
            end
            
            if user.user_type == "is_pending" then
                table.insert(pending_users, {
                    username = user.username,
                    created_at = user.created_at,
                    created_ip = user.created_ip or "unknown"
                })
                count = count + 1
            end
        end
    end
    
    red:close()
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        pending_users = pending_users,
        count = count,
        max_pending = 2
    }))
end

local function handle_all_users()
    local red = auth.connect_redis()
    if not red then
        ngx.status = 503
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Database unavailable"
        }))
        return
    end
    
    local user_keys = red:keys("username:*") or {}
    local users = {}
    local stats = { total = 0, approved = 0, pending = 0, admin = 0 }
    
    for _, key in ipairs(user_keys) do
        local user_data = red:hgetall(key)
        if user_data and #user_data > 0 then
            local user = {}
            for i = 1, #user_data, 2 do
                local field_key = user_data[i]
                if string.sub(field_key, -1) == ":" then
                    field_key = string.sub(field_key, 1, -2)
                end
                user[field_key] = user_data[i + 1]
            end
            
            table.insert(users, {
                username = user.username,
                user_type = user.user_type,
                created_at = user.created_at,
                last_active = user.last_active,
                created_ip = user.created_ip or "unknown",
                -- Convert to old format for frontend compatibility
                is_admin = user.user_type == "is_admin" and "true" or "false",
                is_approved = (user.user_type == "is_approved" or user.user_type == "is_admin") and "true" or "false"
            })
            
            stats.total = stats.total + 1
            if user.user_type == "is_admin" then
                stats.admin = stats.admin + 1
            elseif user.user_type == "is_approved" then
                stats.approved = stats.approved + 1
            elseif user.user_type == "is_pending" then
                stats.pending = stats.pending + 1
            end
        end
    end
    
    red:close()
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        users = users,
        stats = stats
    }))
end

local function handle_approve_user()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "No request body" }))
        return
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok or not data.username then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "Invalid request data" }))
        return
    end
    
    local red = auth.connect_redis()
    if not red then
        ngx.status = 503
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "Database unavailable" }))
        return
    end
    
    local user_key = "username:" .. data.username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        red:close()
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "User not found" }))
        return
    end
    
    -- Update user type to approved
    red:hset(user_key, "user_type:", "is_approved")
    red:hset(user_key, "approved_at:", os.date("!%Y-%m-%dT%H:%M:%SZ"))
    red:hset(user_key, "approved_by:", "admin")
    
    red:close()
    
    ngx.log(ngx.INFO, "Admin approved user: " .. data.username)
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "User approved successfully",
        username = data.username
    }))
end

local function handle_reject_user()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "No request body" }))
        return
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok or not data.username then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "Invalid request data" }))
        return
    end
    
    local red = auth.connect_redis()
    if not red then
        ngx.status = 503
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "Database unavailable" }))
        return
    end
    
    local user_key = "username:" .. data.username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        red:close()
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "User not found" }))
        return
    end
    
    -- Delete the user completely
    red:del(user_key)
    red:close()
    
    local reason = data.reason or "No reason provided"
    ngx.log(ngx.INFO, "Admin rejected and deleted user: " .. data.username .. " (reason: " .. reason .. ")")
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "User rejected and deleted successfully",
        username = data.username,
        reason = reason
    }))
end

local function handle_clear_guest_sessions()
    local red = auth.connect_redis()
    if not red then
        ngx.status = 503
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ success = false, error = "Database unavailable" }))
        return
    end
    
    local cleared = 0
    
    -- Clear guest session keys
    local guest_keys = red:keys("guest_*") or {}
    for _, key in ipairs(guest_keys) do
        red:del(key)
        cleared = cleared + 1
    end
    
    -- Clear guest user accounts
    for i = 1, 2 do
        local username = "guest_user_" .. i
        red:del("username:" .. username)
        cleared = cleared + 1
    end
    
    red:close()
    
    ngx.log(ngx.INFO, "Admin cleared " .. cleared .. " guest session keys")
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Guest sessions cleared successfully",
        cleared_keys = cleared
    }))
end

-- =============================================
-- ADMIN CHAT STREAMING
-- =============================================

local function handle_ollama_chat_stream()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Admin access required"
        }))
        return ngx.exit(403)
    end
    
    -- Use shared Ollama streaming from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    local stream_context = {
        user_type = "is_admin",
        username = username,
        user_data = user_data,
        include_history = true,
        history_limit = 100,
        default_options = {
            model = os.getenv("MODEL_NAME") or "devstral",
            temperature = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.7,
            max_tokens = tonumber(os.getenv("MODEL_NUM_PREDICT")) or 4096  -- Highest limit for admins
        }
    }
    
    return stream_ollama.handle_chat_stream_common(stream_context)
end

-- =============================================
-- MAIN ADMIN API HANDLER
-- =============================================

function M.handle_admin_api()
    -- Require admin access for all admin API calls
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Admin access required"
        }))
        return ngx.exit(403)
    end
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/admin/stats" and method == "GET" then
        handle_admin_stats()
    elseif uri == "/api/admin/users/pending" and method == "GET" then
        handle_pending_users()
    elseif uri == "/api/admin/users" and method == "GET" then
        handle_all_users()
    elseif uri == "/api/admin/users/approve" and method == "POST" then
        handle_approve_user()
    elseif uri == "/api/admin/users/reject" and method == "POST" then
        handle_reject_user()
    elseif uri == "/api/admin/clear-guest-sessions" and method == "POST" then
        handle_clear_guest_sessions()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Admin API endpoint not found",
            available_endpoints = {
                "GET /api/admin/stats - System statistics",
                "GET /api/admin/users/pending - Pending users",
                "GET /api/admin/users - All users",
                "POST /api/admin/users/approve - Approve user",
                "POST /api/admin/users/reject - Reject user",
                "POST /api/admin/clear-guest-sessions - Clear guest sessions"
            }
        }))
    end
end

-- =============================================
-- ROUTE HANDLER (FOR NON-VIEW ROUTES)
-- =============================================

function M.handle_route(route_type)
    -- This function handles non-view routes for admin users
    -- Views are handled by manage_views.lua
    if route_type == "admin_api" then
        return M.handle_admin_api()
    else
        ngx.status = 404
        return ngx.say("Admin route not found: " .. tostring(route_type))
    end
end

return {
    handle_admin_api = M.handle_admin_api,
    handle_ollama_chat_stream = handle_ollama_chat_stream,
    handle_route = M.handle_route
}