local function handle_chat_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_admin()
    local template = require "template"
    
    -- Admin Redis data - full system access
    local is_admin_redis_data = {
        username = username,
        role = "admin",
        permissions = "full_system_access",
        user_badge = is_public.get_user_badge("admin", nil),
        dash_buttons = is_public.get_nav_buttons("admin", username, nil),
        system_access = "enabled",
        message_limit = "unlimited",
        storage_type = "redis"
    }
    
    -- Admin content data - extends public shared content
    local is_admin_content_data = is_public.build_content_data("chat", "admin", {
        -- Admin-specific JavaScript (extends base with approved + admin)
        js_files = is_public.shared_content_data.base_js_files .. [[
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]],
        
        -- Admin-specific chat features
        chat_features = is_public.get_chat_features("admin"),
        
        -- Admin-specific content
        admin_features = "enabled",
        priority_access = "highest"
    })
    
    template.render_and_output("app.html", is_admin_redis_data, is_admin_content_data)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_admin()
    local template = require "template"
    
    -- Admin Redis data - system administration
    local is_admin_redis_data = {
        username = username,
        role = "admin",
        permissions = "system_administration",
        user_badge = is_public.get_user_badge("admin", nil),
        dash_buttons = is_public.get_nav_buttons("admin", username, nil),
        system_access = "enabled",
        user_management = "enabled"
    }
    
    -- Admin content data - extends public shared content
    local is_admin_content_data = is_public.build_content_data("dashboard", "admin", {
        -- Admin-specific JavaScript (extends base with approved + admin)
        js_files = is_public.shared_content_data.base_js_files .. [[
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]],
        
        -- Admin-specific dashboard features
        dashboard_content = is_public.get_dashboard_features("admin"),
        
        -- Admin-specific content
        admin_panel = "enabled",
        user_management_panel = "enabled"
    })
    
    template.render_and_output("app.html", is_admin_redis_data, is_admin_content_data)
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
        local guest_stats = server.get_guest_stats()
        local sse_stats = server.get_sse_stats()
        
        send_json(200, {
            success = true,
            stats = {
                guest_sessions = guest_stats,
                sse_sessions = sse_stats,
                timestamp = os.date("!%Y-%m-%dT%TZ")
            }
        })
        
    else
        send_json(404, { 
            error = "Admin API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "GET /api/admin/users - Get all users",
                "GET /api/admin/stats - Get system statistics"
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