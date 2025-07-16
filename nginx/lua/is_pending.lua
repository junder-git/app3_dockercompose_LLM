-- =============================================================================
-- nginx/lua/is_pending.lua - PENDING USER DASHBOARD
-- =============================================================================

local function handle_dash_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local template = require "template"
    
    local user_type, username, user_data = is_who.check()
    
    -- Ensure this is actually a pending user
    if user_type ~= "authenticated" then
        ngx.log(ngx.WARN, "Non-pending user accessing pending dashboard: " .. (user_type or "none"))
        return ngx.redirect("/login")
    end
    
    local context = {
        page_title = "Account Pending - ai.junder.uk",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base,
        nav = is_public.render_nav("authenticated", username, user_data),
        dashboard_content = [[
            <div class="dashboard-container">
                <div class="pending-header text-center">
                    <h2><i class="bi bi-clock-history text-warning"></i> Account Pending Approval</h2>
                    <p class="text-muted">Your account is awaiting administrator approval</p>
                </div>
                
                <div class="pending-content">
                    <div class="row justify-content-center">
                        <div class="col-md-8">
                            <div class="card bg-dark border-warning">
                                <div class="card-body text-center">
                                    <h5 class="card-title text-warning">
                                        <i class="bi bi-person-check"></i> Account Status
                                    </h5>
                                    <p class="card-text">
                                        Welcome <strong>]] .. (username or "User") .. [[</strong>!<br>
                                        Your account has been created but requires administrator approval before you can access the chat system.
                                    </p>
                                    
                                    <div class="mt-4">
                                        <h6>What happens next?</h6>
                                        <ul class="list-unstyled">
                                            <li><i class="bi bi-check text-success"></i> Account created successfully</li>
                                            <li><i class="bi bi-clock text-warning"></i> Awaiting admin approval</li>
                                            <li><i class="bi bi-envelope text-info"></i> You'll be notified when approved</li>
                                        </ul>
                                    </div>
                                    
                                    <div class="mt-4">
                                        <p class="text-muted">
                                            <small>
                                                <i class="bi bi-info-circle"></i> 
                                                Approval typically takes 24-48 hours. You'll be able to access the full chat system once approved.
                                            </small>
                                        </p>
                                    </div>
                                </div>
                            </div>
                            
                            <div class="text-center mt-4">
                                <a href="/login" class="btn btn-primary">
                                    <i class="bi bi-arrow-clockwise"></i> Check Status
                                </a>
                                <button class="btn btn-outline-light ms-2" onclick="logout()">
                                    <i class="bi bi-box-arrow-right"></i> Logout
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        ]]
    }
    
    template.render_template("/usr/local/openresty/nginx/html/dashboard.html", context)
end

return {
    handle_dash_page = handle_dash_page
}