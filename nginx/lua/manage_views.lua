-- =============================================================================
-- nginx/lua/manage_views.lua - COMPLETE VIEW HANDLERS WITH PROPER TEMPLATING
-- =============================================================================

local template = require "manage_template"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- HELPER FUNCTIONS
-- =============================================

-- Generate navigation buttons based on user type
local function get_nav_buttons(user_type, username, user_data)
    if user_type == "is_admin" then
        return '<a class="nav-link" href="/dash">Dashboard</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">Logout</button>'
    elseif user_type == "is_approved" then
        return '<a class="nav-link" href="/dash">Dashboard</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">Logout</button>'
    elseif user_type == "is_pending" then
        return '<button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">Logout</button>'
    elseif user_type == "is_guest" then
        local display_name = (user_data and user_data.display_username) or username or "guest"
        return '<a class="nav-link" href="/register">Register</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">End Session</button>'
    else -- is_none
        return '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    end
end

-- Get display username (for guests, use display_username; for others, use username)
local function get_display_username(user_type, username, user_data)
    if user_type == "is_guest" and user_data and user_data.display_username then
        return user_data.display_username
    end
    return username or "guest"
end

-- =============================================
-- INDEX PAGE HANDLERS
-- =============================================

function M.handle_index_page()
    local user_type, username, user_data = auth.check()
    local display_name = get_display_username(user_type, username, user_data)
    
    local context = {
        page_title = "ai.junder.uk - Advanced AI Chat",
        username = display_name,
        dash_buttons = get_nav_buttons(user_type, username, user_data)
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/index.html", user_type, "index", context)
end

-- =============================================
-- CHAT PAGE HANDLERS
-- =============================================

function M.handle_chat_page_admin()
    local user_type, username, user_data = auth.check()
    
    -- Admin chat features
    local chat_features = [[
        <div class="user-features admin-features">
            <div class="alert alert-danger">
                <h6><i class="bi bi-shield-check text-danger"></i> Admin Console</h6>
                <p class="mb-1">Unlimited messages • Full system access • Redis storage</p>
                <div class="admin-actions">
                    <button class="btn btn-danger btn-sm me-2" onclick="manageUsers()">Manage Users</button>
                    <button class="btn btn-secondary btn-sm me-2" onclick="viewSystemLogs()">System Logs</button>
                    <button class="btn btn-outline-light btn-sm" onclick="exportAdminChats()">Export Chats</button>
                </div>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Admin Chat - ai.junder.uk",
        username = username,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        chat_features = chat_features,
        chat_placeholder = "Admin console ready..."
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/chat.html", user_type, "chat", context)
end

function M.handle_chat_page_approved()
    local user_type, username, user_data = auth.check()
    
    -- Approved user chat features
    local chat_features = [[
        <div class="user-features approved-features">
            <div class="alert alert-success">
                <h6><i class="bi bi-person-check text-success"></i> Approved User</h6>
                <p class="mb-1">Unlimited messages • Redis storage • Full features</p>
                <div class="approved-actions">
                    <button class="btn btn-success btn-sm me-2" onclick="exportChats()">Export History</button>
                    <button class="btn btn-outline-light btn-sm" onclick="clearHistory()">Clear History</button>
                </div>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Chat - ai.junder.uk",
        username = username,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        chat_features = chat_features,
        chat_placeholder = "Ask anything..."
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/chat.html", user_type, "chat", context)
end

function M.handle_chat_page_guest()
    local user_type, username, user_data = auth.check()
    local display_name = get_display_username(user_type, username, user_data)
    
    -- Guest chat features
    local chat_features = [[
        <div class="user-features guest-features">
            <div class="alert alert-warning">
                <h6><i class="bi bi-clock-history text-warning"></i> Guest Chat</h6>
                <p class="mb-1">10 messages • 10 minutes • localStorage only</p>
                <div class="guest-actions">
                    <a href="/register" class="btn btn-warning btn-sm me-2">Register for unlimited</a>
                    <button class="btn btn-outline-light btn-sm" onclick="downloadGuestHistory()">Download History</button>
                </div>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Guest Chat - ai.junder.uk",
        username = display_name,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        chat_features = chat_features,
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 10 minutes)"
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/chat.html", user_type, "chat", context)
end

-- =============================================
-- DASHBOARD PAGE HANDLERS
-- =============================================

function M.handle_dash_page_admin()
    local user_type, username, user_data = auth.check()
    
    -- Admin dashboard content
    local dashboard_content = [[
        <div class="dashboard-container">
            <div class="dashboard-header">
                <h2><i class="bi bi-shield-check text-danger"></i> Admin Dashboard</h2>
                <p class="text-muted">System administration and user management</p>
            </div>
            
            <div class="row">
                <div class="col-md-6">
                    <div class="card bg-dark border-danger mb-4">
                        <div class="card-body">
                            <h5 class="card-title text-danger">
                                <i class="bi bi-people"></i> User Management
                            </h5>
                            <div class="mb-3">
                                <button class="btn btn-danger me-2" onclick="loadPendingUsers()">Pending Users</button>
                                <button class="btn btn-outline-danger" onclick="loadAllUsers()">All Users</button>
                            </div>
                            <div id="user-management-content">
                                <p class="text-muted">Click above to load user data</p>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="col-md-6">
                    <div class="card bg-dark border-info mb-4">
                        <div class="card-body">
                            <h5 class="card-title text-info">
                                <i class="bi bi-graph-up"></i> System Stats
                            </h5>
                            <button class="btn btn-info btn-sm mb-3" onclick="refreshSystemStats()">
                                <i class="bi bi-arrow-clockwise"></i> Refresh
                            </button>
                            <div id="system-stats">
                                <p class="text-muted">Loading system statistics...</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="row">
                <div class="col-12">
                    <div class="card bg-dark border-warning">
                        <div class="card-body">
                            <h5 class="card-title text-warning">
                                <i class="bi bi-tools"></i> Admin Actions
                            </h5>
                            <button class="btn btn-warning me-2" onclick="clearGuestSessions()">
                                <i class="bi bi-trash"></i> Clear Guest Sessions
                            </button>
                            <button class="btn btn-outline-warning me-2" onclick="exportAdminChats()">
                                <i class="bi bi-download"></i> Export Admin Chats
                            </button>
                            <button class="btn btn-outline-secondary" onclick="viewSystemLogs()">
                                <i class="bi bi-file-text"></i> View System Logs
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Admin Dashboard - ai.junder.uk",
        username = username,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        dashboard_content = dashboard_content
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/dash.html", user_type, "dashboard", context)
end

function M.handle_dash_page_approved()
    local user_type, username, user_data = auth.check()
    
    -- Approved user dashboard content
    local dashboard_content = [[
        <div class="dashboard-container">
            <div class="dashboard-header">
                <h2><i class="bi bi-person-check text-success"></i> User Dashboard</h2>
                <p class="text-muted">Welcome back! Your account has full access.</p>
            </div>
            
            <div class="row">
                <div class="col-md-6">
                    <div class="card bg-dark border-success mb-4">
                        <div class="card-body">
                            <h5 class="card-title text-success">
                                <i class="bi bi-chat-dots"></i> Chat Features
                            </h5>
                            <ul class="list-unstyled">
                                <li><i class="bi bi-check-circle text-success"></i> Unlimited messages</li>
                                <li><i class="bi bi-check-circle text-success"></i> Redis chat history</li>
                                <li><i class="bi bi-check-circle text-success"></i> Full AI features</li>
                                <li><i class="bi bi-check-circle text-success"></i> Export chat history</li>
                            </ul>
                            <a href="/chat" class="btn btn-success">
                                <i class="bi bi-chat-square-dots"></i> Start Chatting
                            </a>
                        </div>
                    </div>
                </div>
                
                <div class="col-md-6">
                    <div class="card bg-dark border-info mb-4">
                        <div class="card-body">
                            <h5 class="card-title text-info">
                                <i class="bi bi-person"></i> Account Info
                            </h5>
                            <p><strong>Username:</strong> ]] .. username .. [[</p>
                            <p><strong>Account Type:</strong> <span class="badge bg-success">Approved</span></p>
                            <p><strong>Status:</strong> Full Access</p>
                            <p><strong>Storage:</strong> Redis Database</p>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="row">
                <div class="col-12">
                    <div class="card bg-dark border-primary">
                        <div class="card-body">
                            <h5 class="card-title text-primary">
                                <i class="bi bi-tools"></i> User Actions
                            </h5>
                            <button class="btn btn-primary me-2" onclick="exportChats()">
                                <i class="bi bi-download"></i> Export Chat History
                            </button>
                            <button class="btn btn-outline-danger" onclick="clearHistory()">
                                <i class="bi bi-trash"></i> Clear Chat History
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Dashboard - ai.junder.uk",
        username = username,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        dashboard_content = dashboard_content
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/dash.html", user_type, "dashboard", context)
end

function M.handle_dash_page_pending()
    local user_type, username, user_data = auth.check()
    
    -- Pending user dashboard content
    local dashboard_content = [[
        <div class="dashboard-container">
            <div class="pending-header text-center">
                <h2><i class="bi bi-clock-history text-warning"></i> Account Pending Approval</h2>
                <p class="text-muted">Your account is awaiting administrator approval</p>
            </div>
            
            <div class="row justify-content-center">
                <div class="col-md-8">
                    <div class="card bg-dark border-warning">
                        <div class="card-body text-center">
                            <div class="mb-4">
                                <i class="bi bi-hourglass-split" style="font-size: 4rem; color: #ffc107;"></i>
                            </div>
                            
                            <h4 class="text-warning mb-3">Account Under Review</h4>
                            
                            <p class="text-light mb-4">
                                Thank you for registering! Your account is currently being reviewed by our administrators.
                                This process typically takes 24-48 hours.
                            </p>
                            
                            <div class="alert alert-info">
                                <h6><i class="bi bi-info-circle"></i> What happens next?</h6>
                                <ul class="list-unstyled mb-0">
                                    <li>✓ Your registration has been received</li>
                                    <li>⏳ An administrator will review your account</li>
                                    <li>📧 You'll be notified when approved</li>
                                    <li>🚀 Full access will be granted immediately</li>
                                </ul>
                            </div>
                            
                            <div class="mt-4">
                                <p class="text-muted">
                                    <strong>Username:</strong> ]] .. username .. [[<br>
                                    <strong>Status:</strong> <span class="badge bg-warning">Pending Approval</span>
                                </p>
                            </div>
                            
                            <div class="mt-4">
                                <p class="text-muted">
                                    While you wait, you can try our guest chat with limited features.
                                </p>
                                <a href="/" class="btn btn-outline-warning">
                                    <i class="bi bi-chat-dots"></i> Try Guest Chat
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    ]]
    
    local context = {
        page_title = "Account Pending - ai.junder.uk",
        username = username,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        dashboard_content = dashboard_content
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/dash.html", user_type, "dashboard", context)
end

-- =============================================
-- AUTH PAGE HANDLERS
-- =============================================

function M.handle_login_page()
    local user_type, username, user_data = auth.check()
    local display_name = get_display_username(user_type, username, user_data)
    
    local context = {
        page_title = "Login - ai.junder.uk",
        username = display_name,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        auth_title = "Sign In",
        auth_subtitle = "Welcome back to ai.junder.uk"
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/login.html", user_type, "auth", context)
end

function M.handle_register_page()
    local user_type, username, user_data = auth.check()
    local display_name = get_display_username(user_type, username, user_data)
    
    local context = {
        page_title = "Register - ai.junder.uk",
        username = display_name,
        dash_buttons = get_nav_buttons(user_type, username, user_data),
        auth_title = "Create Account",
        auth_subtitle = "Join ai.junder.uk today"
    }
    
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/register.html", user_type, "auth", context)
end

-- =============================================
-- ERROR PAGE HANDLERS
-- =============================================

function M.handle_404_page()
    local context = {
        page_title = "404 - Page Not Found",
        username = "guest",
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/404.html", "is_none", "error", context)
end

function M.handle_429_page()
    local context = {
        page_title = "429 - Guest Slots Full",
        username = "guest", 
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/429.html", "is_none", "error", context)
end

function M.handle_50x_page()
    local context = {
        page_title = "Server Error",
        username = "guest",
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_page_with_base("/usr/local/openresty/nginx/dynamic_content/50x.html", "is_none", "error", context)
end

return M