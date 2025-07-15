local function handle_chat_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_approved()
    local template = require "template"
    
    -- Approved Redis data - full chat access
    local is_approved_redis_data = {
        username = username,
        role = "approved",
        permissions = "full_chat_access",
        user_badge = is_public.get_user_badge("approved", nil),
        dash_buttons = is_public.get_nav_buttons("approved", username, nil),
        message_limit = "unlimited",
        storage_type = "redis"
    }
    
    -- Approved content data - extends public shared content
    local is_approved_content_data = is_public.build_content_data("chat", "approved", {
        -- Approved-specific JavaScript (extends base with approved)
        js_files = is_public.shared_content_data.base_js_files .. [[
            <script src="/js/approved.js"></script>
        ]],
        
        -- Approved-specific chat features
        chat_features = is_public.get_chat_features("approved"),
        
        -- Approved-specific content
        history_export = "enabled",
        redis_storage = "enabled"
    })
    
    template.render_and_output("app.html", is_approved_redis_data, is_approved_content_data)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local username = is_who.require_approved()
    local template = require "template"
    
    -- Approved Redis data - personal dashboard
    local is_approved_redis_data = {
        username = username,
        role = "approved",
        permissions = "personal_dashboard",
        user_badge = is_public.get_user_badge("approved", nil),
        dash_buttons = is_public.get_nav_buttons("approved", username, nil),
        personal_stats = "enabled"
    }
    
    -- Approved content data - extends public shared content
    local is_approved_content_data = is_public.build_content_data("dashboard", "approved", {
        -- Approved-specific JavaScript (extends base with approved)
        js_files = is_public.shared_content_data.base_js_files .. [[
            <script src="/js/approved.js"></script>
        ]],
        
        -- Approved-specific dashboard features
        dashboard_content = is_public.get_dashboard_features("approved"),
        
        -- Approved-specific content
        personal_dashboard = "enabled",
        chat_history_access = "enabled"
    })
    
    template.render_and_output("app.html", is_approved_redis_data, is_approved_content_data)
end

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page
}