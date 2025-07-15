-- =============================================================================
-- nginx/lua/is_public.lua - SHARED/PUBLIC CONTENT AND NAVIGATION
-- =============================================================================

local template = require "template"

local M = {}

-- =============================================
-- SHARED CONTENT DATA - Common across all user types
-- =============================================

M.shared_content_data = {
    app_name = "ai.junder.uk",
    app_description = "Advanced coding model, powered by Devstral",
    brand_icon = '<i class="bi bi-lightning-charge-fill"></i>',
    
    -- Common CSS files (loaded by all pages)
    css_files = [[
        <link href="/css/bootstrap.min.css" rel="stylesheet">
        <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
        <link rel="stylesheet" href="/css/common.css">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    ]],
    
    -- Base JavaScript files (public/guest level only)
    base_js_files = [[
        <script src="/js/lib/jquery.min.js"></script>
        <script src="/js/lib/bootstrap.min.js"></script>
        <script src="/js/guest.js"></script>
    ]],
    
    -- Public-only JavaScript (login/register pages)
    public_js_files = [[
        <script src="/js/lib/jquery.min.js"></script>
        <script src="/js/lib/bootstrap.min.js"></script>
        <script src="/js/public.js"></script>
    ]],
    
    -- Common meta tags
    meta_tags = [[
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="description" content="Advanced coding model, powered by Devstral">
        <meta name="author" content="ai.junder.uk">
    ]],
    
    -- Common footer content
    footer_content = [[
        <footer class="text-center py-3 mt-5">
            <small class="text-muted">© 2024 ai.junder.uk - Powered by Devstral</small>
        </footer>
    ]],
    
    -- Error messages
    error_messages = {
        session_expired = "Your session has expired. Please log in again.",
        access_denied = "Access denied. Insufficient permissions.",
        rate_limit = "Too many requests. Please wait and try again.",
        server_error = "Server error. Please try again later."
    }
}

-- =============================================
-- PUBLIC REDIS DATA - For anonymous/public users
-- =============================================

M.public_redis_data = {
    username = "Anonymous",
    role = "public",
    permissions = "none",
    user_badge = "",
    dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>',
    authenticated = false,
    session_type = "none"
}

-- =============================================
-- NAVIGATION RENDERING - Based on user type
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
        -- Public/anonymous users
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

-- =============================================
-- CONTENT BUILDERS - Generate complete content data
-- =============================================

function M.build_content_data(page_type, user_type, additional_data)
    local content_data = {}
    
    -- Start with shared content
    for k, v in pairs(M.shared_content_data) do
        content_data[k] = v
    end
    
    -- Each user type module handles its own JS files
    -- is_public only provides base_js_files and public_js_files
    if page_type == "login" or page_type == "register" or page_type == "index" then
        content_data.js_files = content_data.public_js_files
    else
        -- For authenticated pages, use base_js_files - each module adds its own extensions
        content_data.js_files = content_data.base_js_files
    end
    
    -- Add page-specific content
    if page_type == "chat" then
        content_data.page_title = user_type == "admin" and "Admin Chat" or 
                                 user_type == "approved" and "Chat" or 
                                 "Guest Chat"
        content_data.chat_placeholder = user_type == "admin" and "Admin console ready..." or
                                      user_type == "approved" and "Ask anything..." or
                                      "Guest question (10 limit)..."
        
    elseif page_type == "dashboard" then
        content_data.page_title = user_type == "admin" and "Admin Dashboard" or "Dashboard"
        
    elseif page_type == "index" then
        content_data.page_title = "ai.junder.uk"
        content_data.hero_title = "ai.junder.uk"
        content_data.hero_subtitle = "Advanced coding model, powered by Devstral."
        content_data.cta_primary = '<a href="/chat" class="btn btn-primary">Start Chatting</a>'
        content_data.cta_secondary = '<a href="/register" class="btn btn-outline-primary">Register</a>'
        
    elseif page_type == "login" then
        content_data.page_title = "Login - ai.junder.uk"
        content_data.auth_title = "Welcome Back"
        content_data.auth_subtitle = "Sign in to access Devstral AI"
        
    elseif page_type == "register" then
        content_data.page_title = "Register - ai.junder.uk"
        content_data.auth_title = "Create Account"
        content_data.auth_subtitle = "Join the Devstral AI community"
    end
    
    -- Merge additional data
    if additional_data then
        for k, v in pairs(additional_data) do
            content_data[k] = v
        end
    end
    
    return content_data
end

-- =============================================
-- PUBLIC PAGE HANDLERS
-- =============================================

function M.handle_index_page()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    local redis_data = user_type == "none" and M.public_redis_data or {
        username = username,
        role = user_type,
        permissions = user_type == "admin" and "full_system_access" or
                     user_type == "approved" and "full_chat_access" or
                     user_type == "guest" and "limited_chat_access" or
                     "none",
        user_badge = M.get_user_badge(user_type, user_data),
        dash_buttons = M.get_nav_buttons(user_type, username, user_data),
        authenticated = user_type ~= "none"
    }
    
    local content_data = M.build_content_data("index", user_type, {
        welcome_message = user_type == "none" and "Welcome to ai.junder.uk" or
                         "Welcome back, " .. username .. "!",
        auth_status = user_type == "none" and "anonymous" or "authenticated"
    })
    
    template.render_and_output("index.html", redis_data, content_data)
end

function M.handle_login_page()
    local content_data = M.build_content_data("login", "none")
    template.render_and_output("login.html", M.public_redis_data, content_data)
end

function M.handle_register_page()
    local content_data = M.build_content_data("register", "none")
    template.render_and_output("register.html", M.public_redis_data, content_data)
end

function M.handle_404_page()
    local content_data = M.build_content_data("404", "none", {
        page_title = "404 - Page Not Found",
        error_code = "404",
        error_message = "Page Not Found",
        error_description = "The page you're looking for doesn't exist or has been moved. Let's get you back on track!"
    })
    
    template.render_and_output("404.html", M.public_redis_data, content_data)
end

function M.handle_50x_page()
    local content_data = M.build_content_data("50x", "none", {
        page_title = "Server Error",
        error_code = "500",
        error_message = "Server Error",
        error_description = "Something went wrong on our servers. We're working to fix this issue. Please try again in a few moments."
    })
    
    template.render_and_output("50x.html", M.public_redis_data, content_data)
end

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================

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

function M.get_dashboard_features(user_type)
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
                    <p>Welcome back, {{ redis.username }}!</p>
                </div>
                <div class="dashboard-content" id="dashboard-content">
                    <!-- Populated by approved.js -->
                </div>
            </div>
        ]]
    end
end

return M