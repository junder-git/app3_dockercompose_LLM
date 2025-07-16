-- =============================================================================
-- nginx/lua/is_admin.lua - COMPLETE ADMIN SYSTEM WITH ALL REQUIRED FUNCTIONS
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
    local username = is_who.require_admin()
    local template = require "template"
    
    local context = {
        page_title = "Admin Dashboard - ai.junder.uk",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base .. [[
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]],
        nav = is_public.render_nav("admin", username, nil),
        dashboard_content = is_public.get_dashboard_content("admin", username)
    }
    
    template.render_template("/usr/local/openresty/nginx/html/dashboard.html", context)
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
        
    else
        send_json(404, { 
            error = "Admin API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "GET /api/admin/users - Get all users",
                "GET /api/admin/stats - Get system statistics",
                "POST /api/admin/clear-guest-sessions - Clear all guest sessions (debug)"
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