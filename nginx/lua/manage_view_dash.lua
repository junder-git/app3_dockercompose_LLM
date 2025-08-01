-- =============================================================================
-- nginx/lua/manage_view_dash.lua - DASHBOARD PAGE HANDLER
-- =============================================================================

local view_base = require "manage_view_base"

local M = {}

-- =============================================
-- DASHBOARD PAGE HANDLER
-- =============================================

function M.handle(user_type, username, user_data)
    local page_title, dashboard_content
    
    if user_type == "is_admin" then
        page_title = "Admin Dashboard - ai.junder.uk"
        dashboard_content = view_base.get_admin_dashboard_content(username)
    elseif user_type == "is_approved" then
        page_title = "Dashboard - ai.junder.uk"
        dashboard_content = view_base.get_approved_dashboard_content(username)
    elseif user_type == "is_pending" then
        page_title = "Account Pending - ai.junder.uk"
        dashboard_content = view_base.get_pending_dashboard_content(username)
    else
        -- Shouldn't reach here due to access control in router, but handle gracefully
        ngx.redirect("/")
        return
    end
    
    local context = {
        page_title = page_title,
        dashboard_content = dashboard_content,
        user_data = user_data
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/dash.html", user_type, "dashboard", context)
end

return M