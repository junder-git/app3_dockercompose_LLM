-- =============================================
-- DASHBOARD PAGE HANDLER
-- =============================================

function M.handle(user_type, username, user_data)
    local page_title, dashboard_content, body_class
    
    if user_type == "is_admin" then
        page_title = "Admin Dashboard - ai.junder.uk"
        dashboard_content = view_base.get_admin_dashboard_content(username)
        body_class = "dashboard-page admin-dashboard"
    elseif user_type == "is_approved" then
        page_title = "Dashboard - ai.junder.uk"
        dashboard_content = view_base.get_approved_dashboard_content(username)
        body_class = "dashboard-page approved-dashboard"
    elseif user_type == "is_pending" then
        page_title = "Account Pending - ai.junder.uk"
        dashboard_content = view_base.get_pending_dashboard_content(username)
        body_class = "dashboard-page pending-dashboard"
    else
        -- Shouldn't reach here due to access control in router, but handle gracefully
        ngx.redirect("/")
        return
    end
    
    local context = {
        page_title = page_title,
        body_class = body_class,
        dashboard_content = dashboard_content,
        user_data = user_data
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/dash.html", user_type, "dashboard", context)
end

return M