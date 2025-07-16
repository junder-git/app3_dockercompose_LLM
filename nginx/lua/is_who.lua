-- =============================================================================
-- nginx/lua/is_who.lua - FIXED ROUTING WITH PROPER GUEST SESSION HANDLING
-- =============================================================================

local jwt = require "resty.jwt"
local server = require "server"
local auth = require "auth"
local template = require "template"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

function M.set_vars()
    local user_type, username, user_data = auth.check()
    
    ngx.var.username = username or "guest"
    ngx.var.user_type = user_type or "is_none"    
    if user_type == "is_guest" and user_data and user_data.slot_number then
        local ok, err = pcall(function()
            ngx.var.guest_slot_id = tostring(user_data.slot_number)
        end)
        if not ok then ngx.log(ngx.WARN, "Failed to set guest_slot_id: " .. err) end
    else
        local ok, err = pcall(function()
            ngx.var.guest_slot_id = ""
        end)
        if not ok then ngx.log(ngx.DEBUG, "Failed to clear guest_slot_id: " .. err) end
    end    
    return user_type, username, user_data
end

function M.require_admin()
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_admin" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.require_approved()
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.require_guest()
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_guest" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    if not user_data or not user_data.slot_number then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.get_user_info()
    local user_type, username, user_data = auth.check()
    
    if user_type == "is_none" then
        return { success = false, user_type = "is_none", authenticated = false, message = "Not authenticated" }
    end
    
    local response = {
        success = true,
        username = username,
        user_type = user_type,
        authenticated = true
    }
    
    if user_type == "is_guest" and user_data then
        response.message_limit = user_data.max_messages or 10
        response.messages_used = user_data.message_count or 0
        response.messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
        response.session_remaining = (user_data.expires_at or 0) - ngx.time()
        response.slot_number = user_data.slot_number
        response.priority = user_data.priority or 3
    end
    
    return response
end

-- =====================================================================
-- FIXED route_to_handler function with proper guest session creation
-- =====================================================================
function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_vars()
    ngx.log(ngx.INFO, "Routing " .. route_type .. " for user_type: " .. ngx.var.user_type .. ", username: " .. (username or "unknown"))

    if ngx.var.user_type == "is_admin" then
        -- Admin functionality not implemented yet
        ngx.status = 501
        ngx.header.content_type = 'text/html'
        ngx.say('<h1>Admin functionality not implemented yet</h1>')
        ngx.exit(501)

    elseif ngx.var.user_type == "is_approved" then
        -- Approved user functionality not implemented yet
        ngx.status = 501
        ngx.header.content_type = 'text/html'
        ngx.say('<h1>Approved user functionality not implemented yet</h1>')
        ngx.exit(501)

    elseif ngx.var.user_type == "is_guest" then
        -- Guest functionality not implemented yet
        ngx.status = 501
        ngx.header.content_type = 'text/html'
        ngx.say('<h1>Guest functionality not implemented yet</h1>')
        ngx.exit(501)

    elseif ngx.var.user_type == "is_pending" then
        -- Pending user functionality not implemented yet
        ngx.status = 501
        ngx.header.content_type = 'text/html'
        ngx.say('<h1>Pending user functionality not implemented yet</h1>')
        ngx.exit(501)

    elseif ngx.var.user_type == "is_none" then
        -- Anonymous users
        if route_type == "chat" then
            -- FIXED: Check if user is explicitly requesting guest chat
            local start_guest_chat = ngx.var.arg_start_guest_chat
            if start_guest_chat == "1" then
                -- Redirect to guest session creation
                ngx.log(ngx.INFO, "Anonymous user requesting guest chat - redirecting to guest session creation")
                return ngx.redirect("/?guest_session_requested=1")
            else
                -- Regular chat access without guest session - redirect to home
                ngx.log(ngx.INFO, "Anonymous user trying to access chat - redirecting to home")
                return ngx.redirect("/?start_guest_chat=1")
            end
            
        elseif route_type == "dash" then
            -- Show public dashboard with guest session option
            M.handle_dash_page_with_guest_info()
            
        elseif route_type == "chat_api" then
            -- API access without auth should return 401
            ngx.status = 401
            ngx.header.content_type = 'application/json'
            ngx.say('{"error":"Authentication required","message":"Please login or start a guest session"}')
            return ngx.exit(401)
            
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end
    else
        -- Unknown user type
        ngx.log(ngx.ERROR, "Unknown user type: " .. ngx.var.user_type)
        return ngx.redirect("/login")
    end
end

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
    if user_type == "is_admin" then
        local dashboard_content = template.read_file("/usr/local/openresty/nginx/dynamic_content/dash_admin.html")
        return dashboard_content
    end
    return nil
end

-- =============================================
-- RENDER NAV FROM FILE
-- =============================================

function M.render_nav(user_type, username, user_data)
    local nav_content = template.read_file("/usr/local/openresty/nginx/dynamic_content/nav.html")
    
    -- Simple variable replacement
    nav_content = nav_content:gsub("{{%s*username%s*}}", username or "guest")
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
    local user_type, username, user_data = auth.check()
    
    if user_type == "is_none" then
        username = "guest"
    end
    
    -- Check if guest session was requested
    local guest_session_requested = ngx.var.arg_guest_session_requested
    local auto_start_guest = "false"
    if guest_session_requested == "1" then
        auto_start_guest = "true"
    end
    
    local context = {
        page_title = "ai.junder.uk",
        hero_title = "ai.junder.uk",
        hero_subtitle = "Advanced coding model, powered by Devstral.",
        nav = M.render_nav(user_type, username, user_data),
        auto_start_guest = auto_start_guest
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

-- =============================================
-- API ROUTING FUNCTIONS
-- =============================================

function M.handle_auth_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/auth/login" and method == "POST" then
        auth.handle_login()
    elseif uri == "/api/auth/logout" and method == "POST" then
        auth.handle_logout()
    elseif uri == "/api/auth/check" and method == "GET" then
        auth.handle_check_auth()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say('{"error":"Auth endpoint not found"}')
        ngx.exit(404)
    end
end

function M.handle_register_api()
    ngx.status = 501
    ngx.header.content_type = 'application/json'
    ngx.say('{"error":"Registration not implemented yet"}')
    ngx.exit(501)
end

function M.handle_admin_api()
    ngx.status = 501
    ngx.header.content_type = 'application/json'
    ngx.say('{"error":"Admin API not implemented yet"}')
    ngx.exit(501)
end

function M.handle_guest_api()
    ngx.status = 501
    ngx.header.content_type = 'application/json'
    ngx.say('{"error":"Guest API not implemented yet"}')
    ngx.exit(501)
end

function M.handle_login_page()
    local context = {
        page_title = "Login - ai.junder.uk",
        auth_title = "Welcome Back",
        auth_subtitle = "Sign in to access Devstral AI",
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/login.html", context)
end

function M.handle_register_page()
    local context = {
        page_title = "Register - ai.junder.uk",
        auth_title = "Create Account",
        auth_subtitle = "Join the Devstral AI community",
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/register.html", context)
end

function M.handle_404_page()
    local context = {
        page_title = "404 - Page Not Found",
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/404.html", context)
end

function M.handle_429_page()
    local context = {
        page_title = "429 - Guest reached max sessions",
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/429.html", context)
end

function M.handle_50x_page()
    local context = {
        page_title = "Server Error",
        nav = M.render_nav("public", "Anonymous", nil)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/50x.html", context)
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
        nav = M.render_nav("is_none", "guest", nil),
        dashboard_content = dashboard_content
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

return M