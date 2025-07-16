-- =============================================================================
-- nginx/lua/is_public.lua - SIMPLE TEMPLATE SYSTEM - CORRECTED
-- =============================================================================

local template = require "template"

local M = {}

-- =============================================
-- SHARED CONTENT - Common CSS/JS - UPDATED
-- =============================================

M.common_css = [[
    <link href="/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
    <link rel="stylesheet" href="/css/common.css">
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
]]

-- FIXED: Common JS base now includes public.js for logout and global functions
M.common_js_base = [[
    <script src="/js/lib/jquery.min.js"></script>
    <script src="/js/lib/bootstrap.min.js"></script>
    <script src="/js/public.js"></script>
    <script src="/js/guest.js"></script>
]]

-- Public-only JS (for login/register pages) - No source map requests
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
        return '<a class="nav-link" href="/chat">Guest Chat</a><a class="nav-link" href="/register">Register</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">End Session</button>'
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
                <div class="alert alert-info">
                    <h6><i class="bi bi-shield-check text-danger"></i> Admin Chat Access</h6>
                    <p class="mb-0">Full system access • Unlimited messages • All features</p>
                </div>
            </div>
        ]]
    elseif user_type == "approved" then
        return [[
            <div class="user-features approved-features">
                <div class="alert alert-success">
                    <h6><i class="bi bi-check-circle text-success"></i> Full Chat Access</h6>
                    <p class="mb-0">Unlimited messages • Redis storage • Export history</p>
                </div>
            </div>
        ]]
    else
        return [[
            <div class="user-features guest-features">
                <div class="alert alert-warning">
                    <h6><i class="bi bi-clock-history text-warning"></i> Guest Chat</h6>
                    <p class="mb-1">10 messages • 30 minutes • localStorage only</p>
                    <a href="/register" class="btn btn-warning btn-sm">Register for unlimited</a>
                </div>
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
                    <div class="row">
                        <div class="col-md-12">
                            <div class="card">
                                <div class="card-header">
                                    <h5><i class="bi bi-gear"></i> Admin Controls</h5>
                                </div>
                                <div class="card-body">
                                    <button class="btn btn-primary me-2" onclick="window.location.href='/chat'">
                                        <i class="bi bi-chat-dots"></i> Admin Chat
                                    </button>
                                    <button class="btn btn-info me-2" onclick="exportAdminChats()">
                                        <i class="bi bi-download"></i> Export Chats
                                    </button>
                                    <button class="btn btn-secondary" onclick="viewSystemLogs()">
                                        <i class="bi bi-journal-text"></i> View Logs
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
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
                    <div class="row">
                        <div class="col-md-12">
                            <div class="card">
                                <div class="card-header">
                                    <h5><i class="bi bi-person-check"></i> User Controls</h5>
                                </div>
                                <div class="card-body">
                                    <button class="btn btn-primary me-2" onclick="window.location.href='/chat'">
                                        <i class="bi bi-chat-dots"></i> Start Chat
                                    </button>
                                    <button class="btn btn-info me-2" onclick="exportChats()">
                                        <i class="bi bi-download"></i> Export History
                                    </button>
                                    <button class="btn btn-warning" onclick="clearHistory()">
                                        <i class="bi bi-trash"></i> Clear History
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
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
-- SAFE GUEST STATS HELPER - USING is_guest MODULE
-- =============================================

local function get_safe_guest_stats()
    -- Use the proper is_guest module
    local ok, is_guest = pcall(require, "is_guest")
    if not ok then
        ngx.log(ngx.WARN, "Failed to load is_guest module: " .. tostring(is_guest))
        return {
            active_sessions = 0,
            max_sessions = 2,
            available_slots = 2
        }
    end
    
    -- Try to get guest stats from is_guest module
    local guest_stats, err = nil, nil
    local ok_stats, result = pcall(function()
        return is_guest.get_guest_stats()
    end)
    
    if ok_stats and result then
        guest_stats, err = result, nil
    else
        err = tostring(result or "Unknown error")
    end
    
    if not guest_stats then
        ngx.log(ngx.WARN, "Failed to get guest stats from is_guest: " .. tostring(err))
        -- Return safe defaults
        guest_stats = {
            active_sessions = 0,
            max_sessions = 2,
            available_slots = 2
        }
    end
    
    return guest_stats
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

function M.handle_dash_page_with_guest_info()
    -- Check if user came from failed guest session creation
    local guest_unavailable = ngx.var.arg_guest_unavailable
    
    -- FIXED: Use safe guest stats function with proper is_guest module
    local guest_stats = get_safe_guest_stats()
    
    local dashboard_content = [[
        <div class="dashboard-container">
            <div class="dashboard-header text-center">
                <h2><i class="bi bi-speedometer2"></i> Welcome to ai.junder.uk</h2>
                <p>Advanced coding model, powered by Devstral</p>
            </div>
            
            <div class="dashboard-content">
                <div class="row justify-content-center">
                    <div class="col-md-8">
    ]]
    
    if guest_unavailable then
        dashboard_content = dashboard_content .. [[
                        <div class="alert alert-warning" role="alert">
                            <h5><i class="bi bi-exclamation-triangle"></i> Guest Chat Unavailable</h5>
                            <p>All guest chat sessions are currently occupied. Please try again later or create an account for guaranteed access.</p>
                        </div>
        ]]
    end
    
    dashboard_content = dashboard_content .. [[
                        <div class="card bg-dark border-primary mb-4">
                            <div class="card-body">
                                <h5 class="card-title text-primary">
                                    <i class="bi bi-chat-dots"></i> Guest Chat Status
                                </h5>
                                <div class="row">
                                    <div class="col-md-6">
                                        <p><strong>Active Sessions:</strong> ]] .. guest_stats.active_sessions .. [[/]] .. guest_stats.max_sessions .. [[</p>
                                        <p><strong>Available Slots:</strong> ]] .. guest_stats.available_slots .. [[</p>
                                    </div>
                                    <div class="col-md-6">
                                        <p><strong>Session Duration:</strong> 30 minutes</p>
                                        <p><strong>Message Limit:</strong> 10 messages</p>
                                    </div>
                                </div>
                                
                                <div class="mt-3">
    ]]
    
    if guest_stats.available_slots > 0 then
        dashboard_content = dashboard_content .. [[
                                    <button class="btn btn-success" onclick="startGuestSession()">
                                        <i class="bi bi-chat-square-dots"></i> Start Guest Chat
                                    </button>
        ]]
    else
        dashboard_content = dashboard_content .. [[
                                    <button class="btn btn-secondary" disabled>
                                        <i class="bi bi-chat-square-dots"></i> Guest Chat Full
                                    </button>
                                    <small class="text-muted ms-2">Try again in a few minutes</small>
        ]]
    end
    
    dashboard_content = dashboard_content .. [[
                                </div>
                            </div>
                        </div>
                        
                        <div class="card bg-dark border-success">
                            <div class="card-body">
                                <h5 class="card-title text-success">
                                    <i class="bi bi-person-plus"></i> Get Full Access
                                </h5>
                                <p>Create an account for unlimited chat access and persistent history.</p>
                                
                                <div class="mt-3">
                                    <a href="/register" class="btn btn-success me-2">
                                        <i class="bi bi-person-plus"></i> Create Account
                                    </a>
                                    <a href="/login" class="btn btn-outline-primary">
                                        <i class="bi bi-box-arrow-in-right"></i> Login
                                    </a>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Dashboard - ai.junder.uk",
        css_files = M.common_css,
        js_files = M.public_js,
        nav = M.render_nav("public", "Anonymous", nil),
        dashboard_content = dashboard_content
    }
    
    template.render_template("/usr/local/openresty/nginx/html/dashboard.html", context)
end

return M