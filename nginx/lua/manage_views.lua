-- =============================================
-- PUBLIC PAGE HANDLERS - USING BASE TEMPLATE
-- =============================================
-- Generate proper navigation buttons with logout functionality
local function get_nav_buttons(display_name)
    return string.format(
        '<a class="nav-link" href="/register">Register</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">End Session</button>'
    )
end

function M.handle_index_page()
    local user_type, username, user_data = auth.check()
    -- FIXED: Use display name instead of internal username
    if user_data.display_username then
        local display_name = (user_data and user_data.display_username) or "guest"
    else
        local display_name = username
    end
    local context = {
        page_title = "ai.junder.uk - Session",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,
        dash_buttons = get_nav_buttons(display_name)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

function M.handle_login_page()
    local display_name = get_guest_display_name()
    
    local context = {
        page_title = "Login - ai.junder.uk (Guest Session Active)",
        username = display_name,  -- FIXED: Show display name
        dash_buttons = get_nav_buttons(display_name),
        auth_title = "Login to Full Account",
        auth_subtitle = "End guest session and login to your full account"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/login.html", context)
end

function M.handle_register_page()
    local display_name = get_guest_display_name()
    
    local context = {
        page_title = "Register - ai.junder.uk (Guest Session Active)",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,  -- FIXED: Show display name
        dash_buttons = get_nav_buttons(display_name),
        auth_title = "Create Full Account",
        auth_subtitle = "End guest session and create a permanent account"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/register.html", context)
end


-- =============================================
-- ERROR PAGE HANDLERS - USING ERROR PARTIALS WITH BASE TEMPLATE
-- =============================================

function M.handle_404_page()
    local template = require "manage_template"
    local context = {
        page_title = "404 - Page Not Found",
        username = "guest",
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/404.html", "is_none", "error", context)
end

function M.handle_429_page()
    local template = require "manage_template"
    local context = {
        page_title = "429 - Guest Slots Full",
        username = "guest", 
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/429.html", "is_none", "error", context)
end

function M.handle_50x_page()
    local template = require "manage_template"
    local context = {
        page_title = "Server Error",
        username = "guest",
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/50x.html", "is_none", "error", context)
end

-- =============================================================================
-- nginx/lua/is_admin_view
-- =============================================================================

function M.handle_chat_page_admin()
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

function M.handle_dash_page_admin()
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

-- =============================================================================
-- nginx/lua/is_approved_view
-- =============================================================================

function M.handle_chat_page_approved()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_approved()
    local context = {
        page_title = "Chat",
        nav = is_who.render_nav("approved", username, nil),
        chat_features = is_who.get_chat_features("approved"),
        chat_placeholder = "Ask anything..."
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat.html", context)
end

function M.handle_dash_page_approved()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_approved()
    
    local context = {
        page_title = "Approved Dashboard - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = username or "guest",  -- Nav context
        dash_buttons = is_who.get_nav_buttons("is_approved", username, nil),  -- Nav context
        dashboard_content = is_who.get_dashboard_content("is_approved", username)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash.html", context)
end

-- =============================================================================
-- nginx/lua/is_pending.lua
-- =============================================================================

function M.handle_chat_page_pending()
end


function M.handle_dash_page_pending()
    local is_who = require "aaa_is_who"
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

-- =============================================
-- PAGE HANDLERS - GUESTS CAN SEE ALL PAGES
-- =============================================

function M.handle_chat_page_guest()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_guest" then
        ngx.log(ngx.WARN, "Non-guest user accessing guest chat: " .. (user_type or "none"))
        return ngx.redirect("/")
    end
    
    -- FIXED: Use display name instead of internal username
    local display_name = (user_data and user_data.display_username) or "guest"
    
    local context = {
        page_title = "Guest Chat - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,  -- FIXED: Show display name
        dash_buttons = get_nav_buttons(display_name),
        chat_features = get_chat_features(),
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 10 minutes)"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat.html", context)
end

function M.handle_dash_page_guest()
end

-- =============================================
-- PAGE HANDLERS - is_none
-- =============================================

function M.handle_chat_page_none()
    -- When is_none users try to access chat, attempt to create guest session
    create_secure_guest_session_with_challenge()
end

function M.handle_dash_page_none()
end

return M