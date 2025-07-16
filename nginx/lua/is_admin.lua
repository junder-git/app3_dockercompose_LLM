-- =============================================================================
-- nginx/lua/is_admin.lua - FIXED ADMIN SYSTEM WITH PROPER EXPORTS
-- =============================================================================

local function handle_chat_page()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_admin()
    local context = {
        page_title = "Admin Chat - ai.junder.uk",
        nav = is_who.render_nav("admin", username, nil),
        chat_features = is_who.get_chat_features("admin"),
        chat_placeholder = "Admin console ready... "
    }
    template.render_template("/usr/local/openresty/nginx/html/chat_admin.html", context)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_admin()
    -- Get recent activity
    local recent_activity = [[
        <div class="activity-item">
            <i class="bi bi-person-plus me-2"></i>
            <span>New user registered</span>
            <small class="text-muted d-block">2 min ago</small>
        </div>
        <div class="activity-item">
            <i class="bi bi-chat-dots me-2"></i>
            <span>Guest session started</span>
            <small class="text-muted d-block">5 min ago</small>
        </div>
        <div class="activity-item">
            <i class="bi bi-database me-2"></i>
            <span>System backup completed</span>
            <small class="text-muted d-block">1 hour ago</small>
        </div>
        <div class="activity-item">
            <i class="bi bi-trash me-2"></i>
            <span>Admin cleared guest sessions</span>
            <small class="text-muted d-block">2 hours ago</small>
        </div>
    ]]
    local context = {
        page_title = "Admin Dashboard - ai.junder.uk",
        nav = is_who.render_nav("admin", username, nil),
        username = username,
        redis_status = "Connected",
        ollama_status = "Connected", 
        uptime = "idunno yet...",
        version = "OpenResty 1.21.4.1",
        recent_activity = recent_activity
    }
    template.render_template("/usr/local/openresty/nginx/html/dash_admin.html", context)
end

-- =============================================
-- ENHANCED ADMIN API HANDLERS
-- =============================================

local function handle_admin_api()
    local cjson = require "cjson"
    local server = require "server"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    -- Require admin access for all API calls
    local is_who = require "is_who"
    local username = is_who.require_admin()
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "Admin API access: " .. method .. " " .. uri .. " by " .. username)
    
    if uri == "/api/admin/users" and method == "GET" then
        -- Get all users with enhanced details
        local users = server.get_all_users()
        local user_counts = server.get_user_counts()
        
        send_json(200, { 
            success = true, 
            users = users,
            stats = user_counts,
            total_count = #users
        })
        
    elseif uri == "/api/admin/users/pending" and method == "GET" then
        -- Get pending users for approval
        local pending_users = server.get_pending_users()
        
        send_json(200, {
            success = true,
            pending_users = pending_users,
            count = #pending_users,
            max_pending = 2,
            message = #pending_users > 0 and "Pending users found" or "No pending users"
        })
        
    elseif uri == "/api/admin/users/approve" and method == "POST" then
        -- Approve a user
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        
        if not body then
            send_json(400, { error = "Missing request body" })
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            send_json(400, { error = "Invalid JSON" })
        end
        
        local target_username = data.username
        
        if not target_username then
            send_json(400, { error = "Username is required" })
        end
        
        local success, message = server.approve_user(target_username, username)
        
        if success then
            send_json(200, { 
                success = true, 
                message = message,
                approved_user = target_username,
                approved_by = username
            })
        else
            send_json(400, { 
                success = false, 
                error = message,
                attempted_user = target_username
            })
        end
        
    elseif uri == "/api/admin/users/reject" and method == "POST" then
        -- Reject a user
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        
        if not body then
            send_json(400, { error = "Missing request body" })
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            send_json(400, { error = "Invalid JSON" })
        end
        
        local target_username = data.username
        local reason = data.reason or "No reason provided"
        
        if not target_username then
            send_json(400, { error = "Username is required" })
        end
        
        local success, message = server.reject_user(target_username, username, reason)
        
        if success then
            send_json(200, { 
                success = true, 
                message = message,
                rejected_user = target_username,
                rejected_by = username,
                reason = reason
            })
        else
            send_json(400, { 
                success = false, 
                error = message,
                attempted_user = target_username
            })
        end
        
    elseif uri == "/api/admin/stats" and method == "GET" then
        -- Get comprehensive system stats
        local is_guest = require "is_guest"
        local guest_stats = is_guest.get_guest_stats()
        local sse_stats = server.get_sse_stats()
        local user_counts = server.get_user_counts()
        local registration_stats = server.get_registration_stats()
        
        send_json(200, {
            success = true,
            stats = {
                guest_sessions = guest_stats,
                sse_sessions = sse_stats,
                user_counts = user_counts,
                registration = registration_stats,
                system_health = {
                    total_active_sessions = guest_stats.active_sessions + sse_stats.total_sessions,
                    pending_approval_queue = user_counts.pending,
                    registration_load = registration_stats.registration_health.status
                }
            },
            timestamp = os.date("!%Y-%m-%dT%TZ")
        })
        
    elseif uri == "/api/admin/clear-guest-sessions" and method == "POST" then
        -- Clear all guest sessions (for debugging)
        local is_guest = require "is_guest"
        local success, message = is_guest.clear_all_guest_sessions()
        
        if success then
            send_json(200, { success = true, message = message })
        else
            send_json(500, { success = false, error = message })
        end
        
    -- Keep existing endpoints for backward compatibility
    elseif uri == "/api/admin/approve-user" and method == "POST" then
        -- Legacy endpoint - redirect to new one
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        
        if not body then
            send_json(400, { error = "Missing request body" })
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            send_json(400, { error = "Invalid JSON" })
        end
        
        local target_username = data.username
        
        if not target_username then
            send_json(400, { error = "Username is required" })
        end
        
        local success, message = server.approve_user(target_username, username)
        
        if success then
            send_json(200, { 
                success = true, 
                message = message,
                approved_user = target_username,
                approved_by = username
            })
        else
            send_json(400, { 
                success = false, 
                error = message,
                attempted_user = target_username
            })
        end
        
    elseif uri == "/api/admin/delete-user" and method == "POST" then
        -- Legacy endpoint - redirect to reject
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        
        if not body then
            send_json(400, { error = "Missing request body" })
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            send_json(400, { error = "Invalid JSON" })
        end
        
        local target_username = data.username
        
        if not target_username then
            send_json(400, { error = "Username is required" })
        end
        
        if target_username == username then
            send_json(400, { error = "Cannot delete your own account" })
        end
        
        local success, message = server.reject_user(target_username, username, "Deleted by admin")
        
        if success then
            send_json(200, { 
                success = true, 
                message = message,
                deleted_user = target_username,
                deleted_by = username
            })
        else
            send_json(400, { 
                success = false, 
                error = message,
                attempted_user = target_username
            })
        end
        
    elseif uri == "/api/admin/system-info" and method == "GET" then
        -- Get detailed system information
        local system_info = {
            server_info = {
                nginx_version = "OpenResty 1.21.4.1",
                lua_version = "LuaJIT 2.1.0",
                uptime = "idunno yet...",
                load_average = math.random(15, 45) / 10
            },
            configuration = {
                max_sse_sessions = 3,
                session_timeout = 300,
                user_rate_limit = 60,
                admin_rate_limit = 120,
                max_pending_users = 2
            },
            redis_info = {
                status = "Connected",
                host = os.getenv("REDIS_HOST") or "redis",
                port = tonumber(os.getenv("REDIS_PORT")) or 6379
            },
            ollama_info = {
                status = "Connected",
                url = os.getenv("OLLAMA_URL") or "http://ollama:11434",
                model = os.getenv("OLLAMA_MODEL") or "devstral"
            }
        }
        
        send_json(200, { success = true, system_info = system_info })
        
    else
        send_json(404, { 
            error = "Admin API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "GET /api/admin/users - Get all users",
                "GET /api/admin/users/pending - Get pending users",
                "POST /api/admin/users/approve - Approve a user",
                "POST /api/admin/users/reject - Reject a user",
                "GET /api/admin/stats - Get system statistics",
                "GET /api/admin/system-info - Get detailed system information",
                "POST /api/admin/clear-guest-sessions - Clear all guest sessions"
            }
        })
    end
end

-- =============================================
-- CHAT API HANDLERS
-- =============================================

local function handle_chat_api()
    local cjson = require "cjson"
    local server = require "server"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    -- Require admin access for chat API
    local is_who = require "is_who"
    local username = is_who.require_admin()
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        -- Get chat history
        local limit = tonumber(ngx.var.arg_limit) or 50
        local messages = server.get_chat_history(username, limit)
        
        send_json(200, {
            success = true,
            messages = messages,
            user_type = "admin",
            storage_type = "redis"
        })
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        -- Clear chat history
        local success = server.clear_chat_history(username)
        
        if success then
            send_json(200, { success = true, message = "Chat history cleared" })
        else
            send_json(500, { success = false, error = "Failed to clear chat history" })
        end
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        handle_chat_stream() -- Admin-specific implementation
        
    else
        send_json(404, { 
            error = "Admin Chat API endpoint not found",
            requested = method .. " " .. uri
        })
    end
end

-- =============================================================================
-- ADMIN-SPECIFIC STREAMING - FIXED FUNCTION DEFINITION
-- =============================================================================

local function handle_chat_stream()
    local server = require "server"
    local is_who = require "is_who"
    local cjson = require "cjson"
    
    -- Get admin user info
    local username = is_who.require_admin()
    
    -- Admin rate limiting (higher limits)
    local function pre_stream_check(message, request_data)
        local rate_ok, rate_error = server.check_rate_limit(username, true, false)
        if not rate_ok then
            return false, rate_error
        end
        return true, nil
    end
    
    -- Get chat history for admin users
    local function get_history(limit)
        return server.get_chat_history(username, limit)
    end
    
    -- Save user message to Redis
    local function save_user_message(message)
        server.save_message(username, "user", message)
    end
    
    -- Save AI response to Redis
    local function save_ai_response(response)
        server.save_message(username, "assistant", response)
    end
    
    -- Admin logging
    local function post_stream_cleanup(response)
        ngx.log(ngx.INFO, "Admin chat completed: " .. username .. " - " .. 
                string.sub(response or "", 1, 100) .. "...")
    end
    
    -- Admin stream context
    local stream_context = {
        user_type = "is_admin",
        username = username,
        
        -- Admin capabilities
        include_history = true,   -- Admin gets full history
        history_limit = 25,       -- Most history
        get_history = get_history,
        save_user_message = save_user_message,
        save_ai_response = save_ai_response,
        post_stream_cleanup = post_stream_cleanup,
        
        -- Admin-specific checks
        pre_stream_check = pre_stream_check,
        
        -- Admin AI options (highest limits)
        default_options = {
            temperature = 0.7,
            max_tokens = 4096,      -- Highest limit for admin
            num_predict = 4096,
            num_ctx = 2048,         -- Largest context
            priority = 1            -- Highest priority
        }
    }
    
    -- Call common streaming function
    server.handle_chat_stream_common(stream_context)
end

-- =============================================
-- FIXED MODULE EXPORTS - ENSURE ALL FUNCTIONS ARE RETURNED
-- =============================================

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page,
    handle_admin_api = handle_admin_api,
    handle_chat_api = handle_chat_api,
    handle_chat_stream = handle_chat_stream  -- FIXED: This was missing!
}