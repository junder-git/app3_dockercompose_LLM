-- =============================================================================
-- nginx/lua/is_who.lua - UPDATED FOR VLLM BACKEND WITH NEW ROUTE HANDLERS
-- =============================================================================

local jwt = require "resty.jwt"
local manage = require "manage"
local auth = require "auth"
local template = require "template"
local cjson = require "cjson"
local user_manager = require "manage_users"
local sse_manager = require "manage_sse"
local ollama_adapter = require "manage_adapter_ollama_streaming"

local JWT_SECRET = os.getenv("JWT_SECRET")
local VLLM_URL = os.getenv("VLLM_URL") or "http://vllm:8000"
local VLLM_MODEL = os.getenv("VLLM_MODEL") or "devstral"

local M = {}

function M.set_vars()
    local user_type, username, guest_slot_number, user_data = auth.check()
    ngx.var.username = username or "guest"
    ngx.var.user_type = user_type or "is_none"
    ngx.var.guest_slot_number = guest_slot_number or "1"    
    if user_type == "is_guest" and user_data and user_data.guest_slot_number then
        local ok, err = pcall(function()
            ngx.var.guest_slot_number = tostring(user_data.guest_slot_number)
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
    if not user_data or not user_data.guest_slot_number then
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
        response.guest_slot_number = user_data.guest_slot_number
        response.priority = user_data.priority or 3
    end
    
    return response
end

-- =====================================================================
-- UPDATED route_to_handler function with vLLM endpoints
-- =====================================================================
function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_vars()
    
    -- Handle vLLM API endpoints
    if route_type == "vllm_chat_api" then
        M.handle_vllm_chat_api()
        return
    elseif route_type == "vllm_models_api" then
        M.handle_vllm_models_api()
        return
    elseif route_type == "vllm_completions_api" then
        M.handle_vllm_completions_api()
        return
    end
    
    -- Handle user-specific routes
    if ngx.var.user_type == "is_admin" then
        local is_admin = require "is_admin"
        if route_type == "chat" then
            is_admin.handle_chat_page()
        elseif route_type == "dash" then
            is_admin.handle_dash_page()
        elseif route_type == "chat_api" then
            is_admin.handle_chat_api()
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end
        
    elseif ngx.var.user_type == "is_approved" then
        local is_approved = require "is_approved"
        if route_type == "chat" then
            is_approved.handle_chat_page()
        elseif route_type == "dash" then
            is_approved.handle_dash_page()
        elseif route_type == "chat_api" then
            is_approved.handle_chat_api()
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end
        
    elseif ngx.var.user_type == "is_guest" then
        local is_guest = require "is_guest"
        if route_type == "chat" then
            is_guest.handle_chat_page()
        elseif route_type == "chat_api" then
            is_guest.handle_chat_api()
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end
        
    elseif ngx.var.user_type == "is_pending" then
        local is_pending = require "is_pending"
        if route_type == "dash" then
            is_pending.handle_dash_page()
        else
            return ngx.redirect("/pending")
        end
        
    elseif ngx.var.user_type == "is_none" then
        -- Handle anonymous users
        if route_type == "chat" then
            -- Check if user is explicitly requesting guest chat
            local start_guest_chat = ngx.var.guest_slot_requested
            if start_guest_chat == "true" then
                -- Redirect to guest session creation
                ngx.log(ngx.INFO, "Anonymous user requesting guest chat - redirecting to guest session creation")
                return ngx.redirect("/?guest_slot_requested=true")
            end
            
        elseif route_type == "dash" then
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

-- =====================================================================
-- NEW VLLM API HANDLERS
-- =====================================================================

function M.handle_vllm_chat_api()
    local user_type, username, user_data = M.set_vars()
    
    -- Check authentication
    if user_type == "is_none" then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    end
    
    -- Route to appropriate handler based on user type
    if user_type == "is_admin" then
        local is_admin = require "is_admin"
        if is_admin.handle_vllm_chat_stream then
            is_admin.handle_vllm_chat_stream()
        else
            M.proxy_to_vllm_with_auth(user_type, username, user_data)
        end
    elseif user_type == "is_approved" then
        local is_approved = require "is_approved"
        if is_approved.handle_vllm_chat_stream then
            is_approved.handle_vllm_chat_stream()
        else
            M.proxy_to_vllm_with_auth(user_type, username, user_data)
        end
    elseif user_type == "is_guest" then
        local is_guest = require "is_guest"
        if is_guest.handle_vllm_chat_stream then
            is_guest.handle_vllm_chat_stream()
        else
            M.proxy_to_vllm_with_auth(user_type, username, user_data)
        end
    else
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Invalid user type"
        }))
        return ngx.exit(403)
    end
end

function M.handle_vllm_models_api()
    local user_type, username, user_data = M.set_vars()
    
    -- Check authentication
    if user_type == "is_none" then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    end
    
    -- Proxy to vLLM models endpoint
    M.proxy_to_vllm("/v1/models")
end

function M.handle_vllm_completions_api()
    local user_type, username, user_data = M.set_vars()
    
    -- Check authentication
    if user_type == "is_none" then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    end
    
    -- Route to appropriate handler based on user type
    if user_type == "is_admin" then
        local is_admin = require "is_admin"
        if is_admin.handle_vllm_completions_stream then
            is_admin.handle_vllm_completions_stream()
        else
            M.proxy_to_vllm_with_auth(user_type, username, user_data)
        end
    elseif user_type == "is_approved" then
        local is_approved = require "is_approved"
        if is_approved.handle_vllm_completions_stream then
            is_approved.handle_vllm_completions_stream()
        else
            M.proxy_to_vllm_with_auth(user_type, username, user_data)
        end
    elseif user_type == "is_guest" then
        local is_guest = require "is_guest"
        if is_guest.handle_vllm_completions_stream then
            is_guest.handle_vllm_completions_stream()
        else
            M.proxy_to_vllm_with_auth(user_type, username, user_data)
        end
    else
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Invalid user type"
        }))
        return ngx.exit(403)
    end
end

-- =====================================================================
-- VLLM PROXY HELPERS - USING EXISTING MANAGE MODULE
-- =====================================================================

function M.proxy_to_vllm(endpoint)
    local vllm_adapter = require "manage_adapter_vllm_streaming"
    
    -- Get request body
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Bad request",
            message = "Request body required"
        }))
        return ngx.exit(400)
    end
    
    -- Parse request
    local ok, request_data = pcall(cjson.decode, body)
    if not ok then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Bad request",
            message = "Invalid JSON in request body"
        }))
        return ngx.exit(400)
    end
    
    -- Handle /v1/models endpoint
    if endpoint == "/v1/models" then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            object = "list",
            data = {
                {
                    id = VLLM_MODEL,
                    object = "model",
                    created = ngx.time(),
                    owned_by = "ai.junder.uk"
                }
            }
        }))
        return ngx.exit(200)
    end
    
    -- For other endpoints, use the vLLM adapter
    local result = vllm_adapter.call_vllm_api(request_data.messages or {}, request_data)
    
    if result.success then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(result.raw_response or {
            choices = {
                {
                    message = {
                        role = "assistant",
                        content = result.content
                    }
                }
            }
        }))
    else
        ngx.status = 502
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Backend unavailable",
            message = result.error or "Failed to connect to AI service"
        }))
    end
end

function M.proxy_to_vllm_with_auth(user_type, username, user_data)
    -- Guest-specific checks
    if user_type == "is_guest" and user_data then
        -- Check message limit
        if user_data.message_count >= user_data.max_messages then
            ngx.status = 429
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Rate limit exceeded",
                message = "Guest message limit reached (" .. user_data.max_messages .. " messages)"
            }))
            return ngx.exit(429)
        end
        
        -- Check session expiry
        if ngx.time() >= user_data.expires_at then
            ngx.status = 401
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Session expired",
                message = "Guest session has expired"
            }))
            return ngx.exit(401)
        end
    end
    
    -- Use the existing proxy function
    M.proxy_to_vllm("/v1/chat/completions")
end

-- =============================================
-- NAVIGATION BUILDERS (unchanged)
-- =============================================
function M.get_nav_buttons(user_type, username, user_data)
    if user_type == "is_admin" then
        return '<a class="nav-link" href="/chat">Chat</a><a class="nav-link" href="/dash">Admin Dashboard</a><button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>'
    end
    if user_type == "is_approved" then
        return '<a class="nav-link" href="/chat">Chat</a><a class="nav-link" href="/dash">Dashboard</a><button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>'
    end
    if user_type == "is_pending" then
        return '<a class="nav-link" href="/pending">Status</a><button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>'
    end
    if user_type == "is_guest" then
        return '<a class="nav-link" href="/chat">Guest Chat</a><a class="nav-link" href="/register">Register</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">End Session</button>'
    end
    if user_type == "is_none" then
        return '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    end
end

function M.get_chat_features(user_type)
    if user_type == "is_admin" then
        return [[
            <div class="user-features admin-features">
                <div class="alert alert-info">
                    <h6><i class="bi bi-shield-check text-danger"></i> Admin Chat Access</h6>
                    <p class="mb-0">Full system access • Unlimited messages • All features</p>
                </div>
            </div>
        ]]
    end
    if user_type == "is_approved" then
        return [[
            <div class="user-features approved-features">
                <div class="alert alert-success">
                    <h6><i class="bi bi-check-circle text-success"></i> Full Chat Access</h6>
                    <p class="mb-0">Unlimited messages • Redis storage • Export history</p>
                </div>
            </div>
        ]]
    end
    if user_type == "is_pending" then
        return [[
            <div class="user-features approved-features">
                <div class="alert alert-success">
                    <h6><i class="bi bi-check-circle text-success"></i> Full Chat Access</h6>
                    <p class="mb-0">Unlimited messages • Redis storage • Export history</p>
                </div>
            </div>
        ]]
    end
    if user_type == "is_guest" then
        return [[
            <div class="user-features guest-features">
                <div class="alert alert-warning">
                    <h6><i class="bi bi-clock-history text-warning"></i> Guest Chat</h6>
                    <p class="mb-1">10 messages • 10 minutes • localStorage only</p>
                    <a href="/register" class="btn btn-warning btn-sm">Register for unlimited</a>
                </div>
            </div>
        ]]
    end
    if user_type == "is_none" then
        return [[ ]]
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
    
    -- Check if guest session was requested
    local guest_slot_requested = ngx.var.arg_guest_slot_requested
    local auto_start_guest = "false"
    if guest_slot_requested == "1" then
        auto_start_guest = "true"
    end
    
    local context = {
        page_title = "ai.junder.uk",
        hero_title = "ai.junder.uk",
        hero_subtitle = "Advanced coding model, powered by Devstral.",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = username or "guest",  -- Nav context
        dash_buttons = M.get_nav_buttons(user_type, username, user_data),  -- Nav context
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
    end
    if uri == "/api/auth/logout" and method == "POST" then
        auth.handle_logout()
    end
    if uri == "/api/auth/check" and method == "GET" then
        auth.handle_check_auth()
    end
end

function M.handle_register_api()
    local register = require "register"
    register.handle_register_api()
end

function M.handle_admin_api()
    local is_admin = require "is_admin"
    is_admin.handle_admin_api()
end

function M.handle_guest_api()
    local is_guest = require "is_guest"
    is_guest.handle_guest_api()
end

function M.handle_login_page()
    local context = {
        page_title = "Login - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = "guest",  -- Nav context
        dash_buttons = M.get_nav_buttons("is_none", "guest", nil),  -- Nav context
        auth_title = "Welcome Back",
        auth_subtitle = "Sign in to access Devstral AI"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/login.html", context)
end

function M.handle_register_page()
    local context = {
        page_title = "Register - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = "guest",  -- Nav context
        dash_buttons = M.get_nav_buttons("is_none", "guest", nil),  -- Nav context
        auth_title = "Create Account",
        auth_subtitle = "Join the Devstral AI community"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/register.html", context)
end

function M.handle_404_page()
    local context = {
        page_title = "404 - Page Not Found",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = "guest",  -- Nav context
        dash_buttons = M.get_nav_buttons("is_none", "guest", nil)  -- Nav context
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/404.html", context)
end

function M.handle_429_page()
    local context = {
        page_title = "429 - Guest reached max sessions",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = "guest",  -- Nav context
        dash_buttons = M.get_nav_buttons("is_none", "guest", nil)  -- Nav context
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/429.html", context)
end

function M.handle_50x_page()
    local context = {
        page_title = "Server Error",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = "guest",  -- Nav context
        dash_buttons = M.get_nav_buttons("is_none", "guest", nil)  -- Nav context
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/50x.html", context)
end

function M.handle_dash_page_with_guest_info()
    -- Check if user came from failed guest session creation
    local guest_unavailable = ngx.var.arg_guest_unavailable
    
    -- Use safe guest stats function with proper is_guest module
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
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = "guest",  -- Nav context
        dash_buttons = M.get_nav_buttons("is_none", "guest", nil),  -- Nav context
        dashboard_content = dashboard_content
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

-- =============================================
-- Export all functions from sub-modules
-- =============================================

-- User Manager Functions
M.get_user = user_manager.get_user
M.create_user = user_manager.create_user
M.update_user_activity = user_manager.update_user_activity
M.get_all_users = user_manager.get_all_users
M.verify_password = user_manager.verify_password
M.get_user_counts = user_manager.get_user_counts
M.get_pending_users = user_manager.get_pending_users
M.approve_user = user_manager.approve_user
M.reject_user = user_manager.reject_user
M.get_registration_stats = user_manager.get_registration_stats
M.save_message = user_manager.save_message
M.get_chat_history = user_manager.get_chat_history
M.clear_chat_history = user_manager.clear_chat_history
M.check_rate_limit = user_manager.check_rate_limit

-- SSE Manager Functions
M.can_start_sse_session = sse_manager.can_start_sse_session
M.start_sse_session = sse_manager.start_sse_session
M.update_sse_activity = sse_manager.update_sse_activity
M.end_sse_session = sse_manager.end_sse_session
M.get_sse_stats = sse_manager.get_sse_stats
M.sse_send = sse_manager.sse_send
M.setup_sse_response = sse_manager.setup_sse_response

-- Ollama Adapter Functions (simplified - only streaming function)
M.call_ollama_streaming = ollama_adapter.call_ollama_streaming
M.format_messages = ollama_adapter.format_messages

return M