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

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page
}