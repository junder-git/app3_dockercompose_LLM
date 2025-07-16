-- =============================================================================
-- nginx/lua/is_admin.lua - COMPLETE ADMIN SYSTEM WITH DASHBOARD TEMPLATE
-- =============================================================================

local function handle_chat_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_admin()
    local template = require "template"
    
    local context = {
        page_title = "Admin Chat - ai.junder.uk",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base .. [[
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]],
        nav = is_public.render_nav("admin", username, nil),
        chat_features = is_public.get_chat_features("admin"),
        chat_placeholder = "Admin console ready... (Unlimited access)"
    }
    
    template.render_template("/usr/local/openresty/nginx/html/chat.html", context)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local server = require "server"
    local username = is_who.require_admin()
    local template = require "template"
    
    -- Get system information for template
    local system_load = math.random(15, 45) -- Mock system load
    local redis_status = "Connected"
    local ollama_status = "Connected"
    local uptime = "3 days, 12 hours"
    local version = "OpenResty 1.21.4.1"
    
    -- Get recent activity
    local recent_activity = [[
        <div class="activity-item">
            <i class="fas fa-user-plus me-2"></i>
            <span>New user registered</span>
            <small class="text-muted d-block">2 min ago</small>
        </div>
        <div class="activity-item">
            <i class="fas fa-sign-in-alt me-2"></i>
            <span>Guest session started</span>
            <small class="text-muted d-block">5 min ago</small>
        </div>
        <div class="activity-item">
            <i class="fas fa-database me-2"></i>
            <span>System backup completed</span>
            <small class="text-muted d-block">1 hour ago</small>
        </div>
        <div class="activity-item">
            <i class="fas fa-broom me-2"></i>
            <span>Admin cleared guest sessions</span>
            <small class="text-muted d-block">2 hours ago</small>
        </div>
    ]]
    
    -- Get system alerts
    local system_alerts = [[
        <div class="text-muted">No active alerts</div>
    ]]
    
    -- Get system info
    local system_info = [[
        <div class="row">
            <div class="col-md-6">
                <h6 class="text-primary">Server Information</h6>
                <p>Nginx Version: OpenResty 1.21.4.1<br>
                Lua Version: LuaJIT 2.1.0<br>
                Redis: Connected<br>
                Ollama: Connected</p>
            </div>
            <div class="col-md-6">
                <h6 class="text-primary">Configuration</h6>
                <p>Max SSE Sessions: 3<br>
                Session Timeout: 300s<br>
                Rate Limit: 60/hour<br>
                Admin Rate Limit: 120/hour</p>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Admin Dashboard - ai.junder.uk",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base .. [[
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]],
        nav = is_public.render_nav("admin", username, nil),
        username = username,
        system_load = system_load,
        redis_status = redis_status,
        ollama_status = ollama_status,
        uptime = uptime,
        version = version,
        recent_activity = recent_activity,
        system_alerts = system_alerts,
        system_info = system_info
    }
    
    template.render_template("/usr/local/openresty/nginx/html/dashboard_admin.html", context)
end

-- =============================================
-- ADMIN API HANDLERS
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
        -- Get all users
        local users = server.get_all_users()
        send_json(200, { success = true, users = users })
        
    elseif uri == "/api/admin/stats" and method == "GET" then
        -- Get system stats
        local is_guest = require "is_guest"
        local guest_stats = is_guest.get_guest_stats()
        local sse_stats = server.get_sse_stats()
        
        send_json(200, {
            success = true,
            stats = {
                guest_sessions = guest_stats,
                sse_sessions = sse_stats,
                timestamp = os.date("!%Y-%m-%dT%TZ")
            }
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
        
    elseif uri == "/api/admin/approve-user" and method == "POST" then
        -- Approve a user
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        local ok, request_data = pcall(cjson.decode, body)
        
        if not ok or not request_data.username then
            send_json(400, { success = false, error = "Invalid request data" })
        end
        
        local red = require "resty.redis"
        local redis_client = red:new()
        redis_client:set_timeout(1000)
        
        local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
        local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
        
        local ok, err = redis_client:connect(REDIS_HOST, REDIS_PORT)
        if not ok then
            send_json(500, { success = false, error = "Redis connection failed" })
        end
        
        local user_key = "user:" .. request_data.username
        local exists = redis_client:exists(user_key)
        
        if exists == 0 then
            send_json(404, { success = false, error = "User not found" })
        end
        
        redis_client:hset(user_key, "is_approved", "true")
        
        ngx.log(ngx.INFO, "User " .. request_data.username .. " approved by admin " .. username)
        send_json(200, { success = true, message = "User approved successfully" })
        
    elseif uri == "/api/admin/delete-user" and method == "POST" then
        -- Delete a user
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        local ok, request_data = pcall(cjson.decode, body)
        
        if not ok or not request_data.username then
            send_json(400, { success = false, error = "Invalid request data" })
        end
        
        if request_data.username == username then
            send_json(400, { success = false, error = "Cannot delete your own account" })
        end
        
        local red = require "resty.redis"
        local redis_client = red:new()
        redis_client:set_timeout(1000)
        
        local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
        local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
        
        local ok, err = redis_client:connect(REDIS_HOST, REDIS_PORT)
        if not ok then
            send_json(500, { success = false, error = "Redis connection failed" })
        end
        
        local user_key = "user:" .. request_data.username
        local chat_key = "chat:" .. request_data.username
        
        redis_client:del(user_key)
        redis_client:del(chat_key)
        
        ngx.log(ngx.INFO, "User " .. request_data.username .. " deleted by admin " .. username)
        send_json(200, { success = true, message = "User deleted successfully" })
        
    elseif uri == "/api/admin/system-info" and method == "GET" then
        -- Get detailed system information
        local system_info = {
            server_info = {
                nginx_version = "OpenResty 1.21.4.1",
                lua_version = "LuaJIT 2.1.0",
                uptime = "3 days, 12 hours",
                load_average = math.random(15, 45) / 10
            },
            configuration = {
                max_sse_sessions = 3,
                session_timeout = 300,
                user_rate_limit = 60,
                admin_rate_limit = 120
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
                "GET /api/admin/stats - Get system statistics",
                "GET /api/admin/system-info - Get detailed system information",
                "POST /api/admin/clear-guest-sessions - Clear all guest sessions",
                "POST /api/admin/approve-user - Approve a user",
                "POST /api/admin/delete-user - Delete a user"
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
-- ADMIN-SPECIFIC STREAMING
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
        user_type = "admin",
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

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page,
    handle_admin_api = handle_admin_api,
    handle_chat_api = handle_chat_api,
    handle_chat_stream = handle_chat_stream
}