-- Build guest acquisition dashboard (moved from is_guest to is_none)
local function build_guest_acquisition_dashboard(guest_unavailable, guest_stats)
    local content = [[
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
        content = content .. [[
                        <div class-- =============================================================================
-- nginx/lua/is_none.lua - SIMPLIFIED: THREE HANDLERS ONLY
-- =============================================================================

local template = require "manage_template"
local cjson = require "cjson"

-- =============================================
-- MAIN ROUTE HANDLER - is_none can see: /, /login, /register
-- =============================================
local function handle_route(route_type)
    if route_type == "index" then
        handle_index_page()
    elseif route_type == "login" then
        handle_login_page()
    elseif route_type == "register" then
        handle_register_page()
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
local function handle_index_page()
    local guest_slot_requested = ngx.var.arg_guest_slot_requested
    local auto_start_guest = (guest_slot_requested == "1") and "true" or "false"
    local guest_stats = get_safe_guest_stats()
    
    local context = {
        page_title = "ai.junder.uk",
        hero_title = "ai.junder.uk",
        hero_subtitle = "Advanced coding model, powered by Devstral.",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = get_nav_buttons(),
        auto_start_guest = auto_start_guest,
        guest_stats = guest_stats
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

local function handle_dash_page()
    -- is_none users can't normally see dash, but if they got here via redirect logic,
    -- show them guest upgrade options instead
    local guest_unavailable = ngx.var.arg_guest_unavailable
    local guest_stats = get_safe_guest_stats()
    
    local dashboard_content = build_guest_acquisition_dashboard(guest_unavailable, guest_stats)
    
    local context = {
        page_title = "Get Access - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = get_nav_buttons(),
        dashboard_content = dashboard_content
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash.html", context)
end

local function handle_chat_page()
    -- Public users trying to access chat without auth
    local start_guest_chat = ngx.var.guest_slot_requested
    if start_guest_chat == "true" then
        return ngx.redirect("/?guest_slot_requested=true")
    end
    -- Redirect to login for regular chat access
    return ngx.redirect("/login")
end

-- =============================================
-- ADDITIONAL PAGE HANDLERS
-- =============================================
local function handle_login_page()
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

local function handle_register_page()
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

-- =============================================
-- HELPER FUNCTIONS
-- =============================================

-- Generate navigation buttons for public users
local function get_nav_buttons()
    return '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
end

-- Get safe guest stats for display
local function get_safe_guest_stats()
    local ok, is_guest = pcall(require, "is_guest")
    if not ok then
        return {
            active_sessions = 0,
            max_sessions = 2,
            available_slots = 2
        }
    end
    
    local ok_stats, result = pcall(function()
        return is_guest.get_guest_stats()
    end)
    
    if ok_stats and result then
        return result
    else
        return {
            active_sessions = 0,
            max_sessions = 2,
            available_slots = 2
        }
    end
end

-- Build guest acquisition dashboard (moved from is_guest to is_none)
local function build_guest_acquisition_dashboard(guest_unavailable, guest_stats)
    local content = [[
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
        content = content .. [[
                        <div class="alert alert-warning" role="alert">
                            <h5><i class="bi bi-exclamation-triangle"></i> Guest Chat Unavailable</h5>
                            <p>All guest chat sessions are currently occupied. Please try again later or create an account for guaranteed access.</p>
                        </div>
        ]]
    end
    
    content = content .. [[
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
        content = content .. [[
                                    <button class="btn btn-success" onclick="startGuestSession()">
                                        <i class="bi bi-chat-square-dots"></i> Start Guest Chat
                                    </button>
        ]]
    else
        content = content .. [[
                                    <button class="btn btn-secondary" disabled>
                                        <i class="bi bi-chat-square-dots"></i> Guest Chat Full
                                    </button>
                                    <small class="text-muted ms-2">Try again in a few minutes</small>
        ]]
    end
    
    content = content .. [[
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
    
    return content
end

-- Add guest session creation API (moved from is_guest)
function M.handle_guest_session_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/guest/create-session" and method == "POST" then
        create_secure_guest_session_with_challenge()
    elseif uri == "/api/guest/stats" and method == "GET" then
        local stats = get_safe_guest_stats()
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            stats = stats
        }))
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ 
            error = "Guest API endpoint not found",
            requested = method .. " " .. uri
        }))
        return ngx.exit(404)
    end
end

-- Simplified guest session creation (moved from is_guest)
local function create_secure_guest_session_with_challenge()
    local guest_stats = get_safe_guest_stats()
    
    if guest_stats.available_slots > 0 then
        -- Create guest session and redirect to chat
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            message = "Guest session created",
            redirect = "/chat"
        }))
    else
        ngx.status = 429
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "no_slots_available",
            message = "All guest slots are currently occupied"
        }))
    end
end

return {
    handle_route = handle_route,
    handle_index_page = handle_index_page,
    handle_dash_page = handle_dash_page,
    handle_chat_page = handle_chat_page,
    handle_guest_session_api = handle_guest_session_api
}