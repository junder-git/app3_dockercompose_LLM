local function handle_chat_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_admin()
    local template = require "template"
    
    local context = {
        page_title = "Admin Chat",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base .. [[
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]],
        nav = is_public.render_nav("admin", username, nil),
        chat_features = is_public.get_chat_features("admin"),
        chat_placeholder = "Admin console ready..."
    }
    
    template.render_template("/usr/local/openresty/nginx/html/chat.html", context)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_admin()
    local template = require "template"
    
    local context = {
        page_title = "Admin Dashboard",
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
        -- Handle streaming chat (placeholder)
        send_json(501, { error = "Streaming chat not implemented yet" })
        
    else
        send_json(404, { 
            error = "Chat API endpoint not found",
            requested = method .. " " .. uri
        })
    end
end

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page,
    handle_admin_api = handle_admin_api,
    handle_chat_api = handle_chat_api
}