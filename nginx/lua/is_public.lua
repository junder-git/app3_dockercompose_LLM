-- =============================================================================
-- nginx/lua/is_public.lua - SIMPLE TEMPLATE SYSTEM
-- =============================================================================

local template = require "template"

local M = {}

-- =============================================
-- SHARED CONTENT - Common CSS/JS
-- =============================================

M.common_css = [[
    <link href="/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
    <link rel="stylesheet" href="/css/common.css">
]]

M.common_js_base = [[
    <script src="/js/lib/jquery.min.js"></script>
    <script src="/js/lib/bootstrap.min.js"></script>
    <script src="/js/guest.js"></script>
]]

M.public_js = [[
    <script src="/js/lib/jquery.min.js"></script>
    <script src="/js/lib/bootstrap.min.js"></script>
    <script src="/js/public.js"></script>
]]

-- =============================================
-- NAVIGATION BUILDERS
-- =============================================

function M.get_nav_buttons(user_type, username, user_data)
    if user_type == "admin" then
        return '<a class="nav-link" href="/chat">Chat</a><a class="nav-link" href="/dash">Admin Dashboard</a><button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>'
    elseif user_type == "approved" then
        return '<a class="nav-link" href="/chat">Chat</a><a class="nav-link" href="/dash">Dashboard</a><button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>'
    elseif user_type == "guest" then
        return '<a class="nav-link" href="/chat">Guest Chat</a><a class="nav-link" href="/register">Register</a>'
    elseif user_type == "authenticated" then
        return '<a class="nav-link" href="/pending">Status</a><button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>'
    else
        return '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    end
end

function M.get_user_badge(user_type, user_data)
    if user_type == "admin" then
        return '<span class="badge bg-danger ms-2">Admin</span>'
    elseif user_type == "approved" then
        return '<span class="badge bg-success ms-2">Approved</span>'
    elseif user_type == "guest" then
        local slot_info = ""
        if user_data and user_data.slot_number then
            slot_info = ' [Slot ' .. user_data.slot_number .. ']'
        end
        return '<span class="badge bg-warning ms-2">Guest' .. slot_info .. '</span>'
    elseif user_type == "authenticated" then
        return '<span class="badge bg-secondary ms-2">Pending</span>'
    else
        return ""
    end
end

function M.get_chat_features(user_type)
    if user_type == "admin" then
        return [[
            <div class="user-features admin-features">
                <h6><i class="bi bi-shield-check text-danger"></i> Admin Chat Access</h6>
                <p>Full system access • Unlimited messages • All features</p>
            </div>
        ]]
    elseif user_type == "approved" then
        return [[
            <div class="user-features approved-features">
                <h6><i class="bi bi-check-circle text-success"></i> Full Chat Access</h6>
                <p>Unlimited messages • Redis storage • Export history</p>
            </div>
        ]]
    else
        return [[
            <div class="user-features guest-features">
                <h6><i class="bi bi-clock-history text-warning"></i> Guest Chat</h6>
                <p>10 messages • 30 minutes • localStorage only</p>
                <a href="/register" class="btn btn-warning btn-sm">Register for unlimited</a>
            </div>
        ]]
    end
end

function M.get_dashboard_content(user_type, username)
    if user_type == "admin" then
        return [[
            <div class="dashboard-container">
                <div class="admin-header">
                    <h2><i class="bi bi-shield-check text-danger"></i> Admin Dashboard</h2>
                    <p>System administration and user management</p>
                </div>
                <div class="admin-content" id="admin-content">
                    <!-- Populated by admin.js -->
                </div>
            </div>
        ]]
    else
        return [[
            <div class="dashboard-container">
                <div class="dashboard-header">
                    <h2><i class="bi bi-speedometer2"></i> Dashboard</h2>
                    <p>Welcome back, ]] .. (username or "User") .. [[!</p>
                </div>
                <div class="dashboard-content" id="dashboard-content">
                    <!-- Populated by approved.js -->
                </div>
            </div>
        ]]
    end
end

-- =============================================
-- RENDER NAV FROM FILE
-- =============================================

function M.render_nav(user_type, username, user_data)
    local nav_content = template.read_file("/usr/local/openresty/nginx/html/nav.html")
    
    -- Simple variable replacement
    nav_content = nav_content:gsub("{{%s*username%s*}}", username or "Anonymous")
    nav_content = nav_content:gsub("{{%s*user_badge%s*}}", M.get_user_badge(user_type, user_data))
    nav_content = nav_content:gsub("{{%s*dash_buttons%s*}}", M.get_nav_buttons(user_type, username, user_data))
    
    return nav_content
end

-- =============================================
-- PAGE HANDLERS
-- =============================================

function M.handle_index_page()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type == "none" then
        user_type = "public"
        username = "Anonymous"
    end
    
    local context = {
        page_title = "ai.junder.uk",
        hero_title = "ai.junder.uk",
        hero_subtitle = "Advanced coding model, powered by Devstral.",
        css_files = M.common_css,
        js_files = M.public_js,
        nav = M.render_nav(user_type, username, user_data)
    }
    
    template.render_template("/usr/local/openresty/nginx/html/index.html", context)
end

function M.handle_login_page()
    local context = {
        page_title = "Login - ai.junder.uk",
        auth_title = "Welcome Back",
        auth_subtitle = "Sign in to access Devstral AI",
        css_files = M.common_css,
        js_files = M.public_js,
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/html/login.html", context)
end

function M.handle_register_page()
    local context = {
        page_title = "Register - ai.junder.uk",
        auth_title = "Create Account",
        auth_subtitle = "Join the Devstral AI community",
        css_files = M.common_css,
        js_files = M.public_js,
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/html/register.html", context)
end

function M.handle_404_page()
    local context = {
        page_title = "404 - Page Not Found",
        css_files = M.common_css,
        js_files = M.public_js,
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/html/404.html", context)
end

function M.handle_50x_page()
    local context = {
        page_title = "Server Error",
        css_files = M.common_css,
        js_files = M.public_js,
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/html/50x.html", context)
end

return M