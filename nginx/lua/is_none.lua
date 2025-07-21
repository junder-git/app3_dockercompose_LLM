-- =============================================================================
-- nginx/lua/is_none.lua - HANDLERS FOR NON-AUTHENTICATED USERS
-- =============================================================================

local template = require "manage_template"
local cjson = require "cjson"

local M = {}

-- Get safe guest stats for display
local function get_safe_guest_stats()
    local ok, is_guest = pcall(require, "is_guest")
    if not ok then
        ngx.log(ngx.WARN, "Failed to load is_guest module: " .. tostring(is_guest))
        return {
            active_sessions = 0,
            max_sessions = 2,
            available_slots = 2
        }
    end
    
    local guest_stats, err = nil, nil
    local ok_stats, result = pcall(function()
        return is_guest.get_guest_stats()
    end)
    
    if ok_stats and result then
        guest_stats = result
    else
        err = tostring(result or "Unknown error")
        ngx.log(ngx.WARN, "Failed to get guest stats: " .. tostring(err))
        guest_stats = {
            active_sessions = 0,
            max_sessions = 2,
            available_slots = 2
        }
    end
    
    return guest_stats
end

-- Generate navigation buttons for public users
local function get_nav_buttons()
    return '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
end

-- =============================================
-- ROUTE HANDLER
-- =============================================

function M.handle_route(route_type)
    if route_type == "index" then
        M.handle_index_page()
    elseif route_type == "login" then
        M.handle_login_page()
    elseif route_type == "register" then
        M.handle_register_page()
    elseif route_type == "dash" then
        M.handle_dash_page_with_guest_info()
    elseif route_type == "chat" then
        -- Public users trying to access chat without auth
        local start_guest_chat = ngx.var.guest_slot_requested
        if start_guest_chat == "true" then
            return ngx.redirect("/?guest_slot_requested=true")
        end
        -- Redirect to login for regular chat access
        return ngx.redirect("/login")
    elseif route_type == "chat_api" then
        -- API access without auth should return 401
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    else
        ngx.status = 404
        return ngx.exec("@custom_404")
    end
end

-- =============================================
-- PAGE HANDLERS
-- =============================================

function M.handle_index_page()
    local guest_slot_requested = ngx.var.arg_guest_slot_requested
    local auto_start_guest = (guest_slot_requested == "1") and "true" or "false"
    
    local context = {
        page_title = "ai.junder.uk",
        hero_title = "ai.junder.uk",
        hero_subtitle = "Advanced coding model, powered by Devstral.",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = get_nav_buttons(),
        auto_start_guest = auto_start_guest
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

function M.handle_login_page()
    local context = {
        page_title = "Login - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = get_nav_buttons(),
        auth_title = "Welcome Back",
        auth_subtitle = "Sign in to access Devstral AI"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/login.html", context)
end

function M.handle_register_page()
    local context = {
        page_title = "Register - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = get_nav_buttons(),
        auth_title = "Create Account",
        auth_subtitle = "Join the Devstral AI community"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/register.html", context)
end

function M.handle_dash_page_with_guest_info()
    local guest_unavailable = ngx.var.arg_guest_unavailable
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
                                        <p><strong>Session Duration:</strong> 10 minutes</p>
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
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = get_nav_buttons(),
        dashboard_content = dashboard_content
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash.html", context)
end

return M