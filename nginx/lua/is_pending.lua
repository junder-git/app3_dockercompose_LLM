-- =============================================================================
-- nginx/lua/is_pending.lua - PENDING USER DASHBOARD
-- =============================================================================

local function handle_dash_page()
    local is_who = require "is_who"
    local template = require "template"
    
    local user_type, username, user_data = is_who.check()
    
    -- Ensure this is actually a pending user
    if user_type ~= "is_pending" then
        ngx.log(ngx.WARN, "Non-pending user accessing pending dashboard: " .. (user_type or "none"))
        return ngx.redirect("/login")
    end
    
    local context = {
        page_title = "Account Pending - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = username or "guest",  -- Nav context
        dash_buttons = is_who.get_nav_buttons("is_pending", username, user_data),  -- Nav context
        dashboard_content = [[
            <div class="dashboard-container">
                <div class="pending-header text-center">
                    <h2><i class="bi bi-clock-history text-warning"></i> Account Pending Approval</h2>
                    <p class="text-muted">Your account is awaiting administrator approval</p>
                </div>
                <!-- ... rest of pending content ... -->
            </div>
        ]]
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dashboard.html", context)
end

return {
    handle_dash_page = handle_dash_page
}