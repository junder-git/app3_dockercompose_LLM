-- =============================================================================
-- nginx/lua/is_admin.lua
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
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat.html", context)
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
        vllm_status = "Connected", 
        uptime = "idunno yet...",
        version = "OpenResty 1.21.4.1",
        recent_activity = recent_activity
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash.html", context)
end

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page
}