-- =============================================================================
-- nginx/lua/is_guest.lua - SIMPLIFIED: THREE MAIN HANDLERS
-- =============================================================================

local template = require "manage_template"
local cjson = require "cjson"
local is_who = require "is_who"

-- =============================================
-- MAIN ROUTE HANDLER - is_guest can see: ALL routes (/, /chat, /dash, /login, /register)
-- =============================================
local function handle_route(route_type)
    if route_type == "index" then
        handle_index_page()
    elseif route_type == "chat" then
        handle_chat_page()
    elseif route_type == "dash" then 
        handle_dash_page()
    elseif route_type == "login" then
        handle_login_page()
    elseif route_type == "register" then
        handle_register_page()
    elseif route_type == "chat_api" then
        handle_chat_api()
    else
        ngx.status = 404
        return ngx.exec("@custom_404")
    end
end

-- =============================================
-- FIVE HANDLERS (guests can see everything)
-- =============================================
local function handle_index_page()
    -- Guest can see index - show them they're a guest
    local context = {
        page_title = "ai.junder.uk - Guest Session",
        hero_title = "ai.junder.uk",
        hero_subtitle = "You're in a guest session! Advanced coding model, powered by Devstral.",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = get_guest_username(),
        dash_buttons = get_nav_buttons(),
        auto_start_guest = "false"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

local function handle_dash_page()
    -- Guest dashboard shows their session info
    local username, user_data = is_who.require_guest()
    
    local dashboard_content = build_guest_dashboard(user_data)
    
    local context = {
        page_title = "Guest Dashboard - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = username,
        dash_buttons = get_nav_buttons(),
        dashboard_content = dashboard_content
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash.html", context)
end

local function handle_chat_page()
    local username, user_data = is_who.require_guest()
    
    local context = {
        page_title = "Guest Chat",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = username or "guest",
        dash_buttons = get_nav_buttons(username),
        chat_features = get_chat_features(),
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 10 minutes)"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat.html", context)
end

-- =============================================
-- API HANDLERS
-- =============================================
local function handle_chat_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            messages = {},
            user_type = "is_guest",
            storage_type = "none",
            note = "Guest users don't have persistent chat history"
        }))
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ 
            success = true, 
            message = "Guest chat uses localStorage only - clear from browser"
        }))
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        handle_ollama_chat_stream()
        
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ 
            error = "Guest Chat API endpoint not found",
            requested = method .. " " .. uri
        }))
        return ngx.exit(404)
    end
end

local function handle_guest_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/guest/create-session" and method == "POST" then
        create_secure_guest_session_with_challenge()
    elseif uri == "/api/guest/challenge-status" and method == "GET" then
        handle_challenge_status()
    elseif uri == "/api/guest/challenge-response" and method == "POST" then
        handle_challenge_response()
    elseif uri == "/api/guest/force-claim" and method == "POST" then
        handle_force_claim()
    elseif uri == "/api/guest/stats" and method == "GET" then
        local stats = get_guest_stats()
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

-- =============================================
-- OLLAMA STREAMING HANDLER
-- =============================================
local function handle_ollama_chat_stream()
    local username, user_data = is_who.require_guest()
    
    local function pre_stream_check(message, request_data)
        local current_count = user_data.message_count or 0
        
        if current_count >= user_data.max_messages then
            return false, "Guest message limit reached (" .. user_data.max_messages .. " messages). Register for unlimited access."
        end
        
        if ngx.time() >= user_data.expires_at then
            return false, "Guest session expired. Please start a new session."
        end
        
        update_guest_message_count(user_data)
        return true, nil
    end
    
    -- Use existing manage module for Ollama streaming
    local manage = require "manage"
    local stream_context = {
        user_type = "is_guest",
        username = username,
        include_history = false,
        history_limit = 0,
        pre_stream_check = pre_stream_check,
        default_options = {
            model = "devstral",
            temperature = 0.7,
            max_tokens = 1024
        }
    }
    
    manage.handle_chat_stream_common(stream_context)
end

local function handle_login_page()
    -- Guest can see login page - show option to end guest session
    local context = {
        page_title = "Login - ai.junder.uk (Guest Session Active)",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = get_guest_username(),
        dash_buttons = get_nav_buttons(),
        auth_title = "Login to Full Account",
        auth_subtitle = "End guest session and login to your full account"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/login.html", context)
end

local function handle_register_page()
    -- Guest can see register page - show option to end guest session  
    local context = {
        page_title = "Register - ai.junder.uk (Guest Session Active)",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = get_guest_username(),
        dash_buttons = get_nav_buttons(),
        auth_title = "Create Full Account",
        auth_subtitle = "End guest session and create a permanent account"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/register.html", context)
end

-- =============================================
-- HELPER FUNCTIONS
-- =============================================
local function get_guest_username()
    local user_type, username, user_data = is_who.set_vars()
    return username or "guest"
end
local function get_nav_buttons(username)
    return '<a class="nav-link" href="/chat">Guest Chat</a><a class="nav-link" href="/register">Register</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">End Session</button>'
end

local function get_chat_features()
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

-- =============================================
-- GUEST SESSION MANAGEMENT (Additional functionality)
-- =============================================

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 600  -- 10 minutes
local GUEST_MESSAGE_LIMIT = 10

local function update_guest_message_count(user_data)
    if not user_data or not user_data.guest_slot_number then
        return false
    end
    
    local redis = require "resty.redis"
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(os.getenv("REDIS_HOST") or "redis", tonumber(os.getenv("REDIS_PORT")) or 6379)
    if not ok then return false end
    
    user_data.message_count = (user_data.message_count or 0) + 1
    user_data.last_activity = ngx.time()
    
    local session_key = "guest_active_session:" .. user_data.guest_slot_number
    local user_session_key = "guest_session:" .. user_data.username
    
    red:set(session_key, cjson.encode(user_data))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    red:set(user_session_key, cjson.encode(user_data))
    red:expire(user_session_key, GUEST_SESSION_DURATION)
    
    red:close()
    return true
end

local function build_guest_dashboard(user_data)
    local messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
    local time_remaining = (user_data.expires_at or 0) - ngx.time()
    local minutes_remaining = math.floor(time_remaining / 60)
    local seconds_remaining = time_remaining % 60
    
    return string.format([[
        <div class="dashboard-container">
            <div class="dashboard-header text-center">
                <h2><i class="bi bi-clock-history text-warning"></i> Guest Session Active</h2>
                <p>Temporary access to ai.junder.uk</p>
            </div>
            
            <div class="dashboard-content">
                <div class="row justify-content-center">
                    <div class="col-md-8">
                        <div class="card bg-dark border-warning mb-4">
                            <div class="card-body">
                                <h5 class="card-title text-warning">
                                    <i class="bi bi-info-circle"></i> Session Status
                                </h5>
                                <div class="row">
                                    <div class="col-md-6">
                                        <p><strong>Messages Remaining:</strong> %d/%d</p>
                                        <p><strong>Time Remaining:</strong> %dm %ds</p>
                                    </div>
                                    <div class="col-md-6">
                                        <p><strong>Storage:</strong> Browser only</p>
                                        <p><strong>Guest ID:</strong> %s</p>
                                    </div>
                                </div>
                                
                                <div class="mt-3">
                                    <a href="/chat" class="btn btn-warning me-2">
                                        <i class="bi bi-chat-square-dots"></i> Continue Chatting
                                    </a>
                                    <button class="btn btn-outline-danger" onclick="logout()">
                                        <i class="bi bi-x-circle"></i> End Session
                                    </button>
                                </div>
                            </div>
                        </div>
                        
                        <div class="card bg-dark border-success">
                            <div class="card-body">
                                <h5 class="card-title text-success">
                                    <i class="bi bi-person-plus"></i> Upgrade to Full Account
                                </h5>
                                <p>Get unlimited access and persistent chat history:</p>
                                <ul class="list-unstyled">
                                    <li>✅ Unlimited messages</li>
                                    <li>✅ Persistent history in Redis</li>
                                    <li>✅ Export chat data</li>
                                    <li>✅ Priority model access</li>
                                </ul>
                                
                                <div class="mt-3">
                                    <a href="/register" class="btn btn-success me-2">
                                        <i class="bi bi-person-plus"></i> Create Account
                                    </a>
                                    <a href="/login" class="btn btn-outline-primary">
                                        <i class="bi bi-box-arrow-in-right"></i> Login Existing
                                    </a>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    ]], 
    messages_remaining, (user_data.max_messages or 10),
    minutes_remaining, seconds_remaining,
    (user_data.display_username or "unknown")
    )
end

-- Placeholder functions for guest session management
local function create_secure_guest_session_with_challenge()
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Guest session creation placeholder"
    }))
end

local function handle_challenge_status()
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        challenge_active = false
    }))
end

local function handle_challenge_response()
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Challenge response placeholder"
    }))
end

local function handle_force_claim()
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Force claim placeholder"
    }))
end

return {
    handle_route = handle_route,
    handle_index_page = handle_index_page,
    handle_dash_page = handle_dash_page,
    handle_chat_page = handle_chat_page,
    handle_guest_api = handle_guest_api,
    handle_ollama_chat_stream = handle_ollama_chat_stream,
    get_guest_stats = get_guest_stats
}




