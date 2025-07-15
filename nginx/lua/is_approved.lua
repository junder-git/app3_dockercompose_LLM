local function handle_chat_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_approved()
    local template = require "template"
    
    local context = {
        page_title = "Chat",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base .. [[
            <script src="/js/approved.js"></script>
        ]],
        nav = is_public.render_nav("approved", username, nil),
        chat_features = is_public.get_chat_features("approved"),
        chat_placeholder = "Ask anything..."
    }
    
    template.render_template("/usr/local/openresty/nginx/html/chat.html", context)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_approved()
    local template = require "template"
    
    local context = {
        page_title = "Dashboard",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base .. [[
            <script src="/js/approved.js"></script>
        ]],
        nav = is_public.render_nav("approved", username, nil),
        dashboard_content = is_public.get_dashboard_content("approved", username)
    }
    
    template.render_template("/usr/local/openresty/nginx/html/dashboard.html", context)
end

-- =============================================
-- APPROVED USER CHAT API HANDLERS
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
    
    -- Require approved access for chat API
    local is_who = require "is_who"
    local username = is_who.require_approved()
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        -- Get chat history
        local limit = tonumber(ngx.var.arg_limit) or 50
        local messages = server.get_chat_history(username, limit)
        
        send_json(200, {
            success = true,
            messages = messages,
            user_type = "approved",
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
    handle_chat_api = handle_chat_api
}