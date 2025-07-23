-- =============================================================================
-- nginx/lua/is_guest.lua - IMPORT SHARED FUNCTIONS FROM manage_auth
-- =============================================================================

local template = require "manage_template"
local cjson = require "cjson"

-- Import required modules
local auth = require "manage_auth"

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 600  -- 10 minutes
local GUEST_MESSAGE_LIMIT = 10

-- =============================================
-- HELPER FUNCTIONS - IMPORT FROM manage_auth
-- =============================================

-- Use shared Redis functions from manage_auth
local redis_to_lua = auth.redis_to_lua
local connect_redis = auth.connect_redis

-- Get the current guest user's info from auth check
local function get_guest_username()
    local user_type, username, user_data = auth.check()
    if user_type == "is_guest" then
        return user_data.display_username or username or "guest"
    end
    return "guest"
end

local function get_nav_buttons(username)
    return '<a class="nav-link" href="/register">Register</a><button class="btn btn-outline-secondary btn-sm ms-2" onclick="logout()">End Session</button>'
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

local function get_guest_stats()
    local red = connect_redis()
    if not red then 
        return {
            active_sessions = 0,
            max_sessions = MAX_GUEST_SESSIONS,
            available_slots = MAX_GUEST_SESSIONS,
            challenges_active = 0
        }
    end

    local active_count = 0
    local challenges_active = 0
    
    -- Check guest_user_1 and guest_user_2
    for i = 1, MAX_GUEST_SESSIONS do
        local username = "guest_user_" .. i
        local session_key = "guest_active_session:" .. username
        local session_data = redis_to_lua(red:get(session_key))
        
        if session_data then
            local ok, session = pcall(cjson.decode, session_data)
            if ok and session.expires_at and ngx.time() < session.expires_at then
                active_count = active_count + 1
            else
                -- Clean expired session
                red:del(session_key)
            end
        end
        
        local challenge_key = "guest_challenge:" .. username
        local challenge_data = redis_to_lua(red:get(challenge_key))
        if challenge_data then
            local ok, challenge = pcall(cjson.decode, challenge_data)
            if ok and challenge.expires_at and ngx.time() < challenge.expires_at then
                challenges_active = challenges_active + 1
            else
                red:del(challenge_key)
            end
        end
    end
    
    red:close()
    
    return {
        active_sessions = active_count,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = MAX_GUEST_SESSIONS - active_count,
        challenges_active = challenges_active
    }
end

local function update_guest_message_count(user_data)
    if not user_data or not user_data.username then
        return false
    end
    
    local red = connect_redis()
    if not red then return false end
    
    user_data.message_count = (user_data.message_count or 0) + 1
    user_data.last_activity = ngx.time()
    
    local session_key = "guest_active_session:" .. user_data.username
    local user_session_key = "guest_session:" .. user_data.username
    
    red:set(session_key, cjson.encode(user_data))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    red:set(user_session_key, cjson.encode(user_data))
    red:expire(user_session_key, GUEST_SESSION_DURATION)
    
    red:close()
    return true
end

local function build_guest_dashboard(user_data)
    if not user_data then
        return '<div class="alert alert-danger">Guest session data not found</div>'
    end
    
    local messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
    local time_remaining = (user_data.expires_at or 0) - ngx.time()
    local minutes_remaining = math.max(0, math.floor(time_remaining / 60))
    local seconds_remaining = math.max(0, time_remaining % 60)
    
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
    (user_data.display_username or user_data.username or "unknown")
    )
end

-- =============================================
-- PAGE HANDLERS - GUESTS CAN SEE ALL PAGES
-- =============================================

local function handle_index_page()
    local user_type, username, user_data = auth.check()
    local display_name = user_data and user_data.display_username or username or "guest"
    
    local context = {
        page_title = "ai.junder.uk - Guest Session",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,
        dash_buttons = get_nav_buttons()
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/index.html", context)
end

local function handle_dash_page()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_guest" then
        ngx.log(ngx.WARN, "Non-guest user accessing guest dashboard: " .. (user_type or "none"))
        return ngx.redirect("/")
    end
    
    local display_name = user_data and user_data.display_username or username or "guest"
    local dashboard_content = build_guest_dashboard(user_data)
    
    local context = {
        page_title = "Guest Dashboard - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,
        dash_buttons = get_nav_buttons(),
        dashboard_content = dashboard_content
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash.html", context)
end

local function handle_chat_page()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_guest" then
        ngx.log(ngx.WARN, "Non-guest user accessing guest chat: " .. (user_type or "none"))
        return ngx.redirect("/")
    end
    
    local display_name = user_data and user_data.display_username or username or "guest"
    
    local context = {
        page_title = "Guest Chat - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,
        dash_buttons = get_nav_buttons(),
        chat_features = get_chat_features(),
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 10 minutes)"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat.html", context)
end

local function handle_login_page()
    local display_name = get_guest_username()
    
    local context = {
        page_title = "Login - ai.junder.uk (Guest Session Active)",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,
        dash_buttons = get_nav_buttons(),
        auth_title = "Login to Full Account",
        auth_subtitle = "End guest session and login to your full account"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/login.html", context)
end

local function handle_register_page()
    local display_name = get_guest_username()
    
    local context = {
        page_title = "Register - ai.junder.uk (Guest Session Active)",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = display_name,
        dash_buttons = get_nav_buttons(),
        auth_title = "Create Full Account",
        auth_subtitle = "End guest session and create a permanent account"
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/register.html", context)
end

-- =============================================
-- API HANDLERS - USE SHARED MODULES
-- =============================================

local function handle_chat_api()
    -- Use shared chat API handler from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    return stream_ollama.handle_chat_api("is_guest")
end

-- Import guest session management from is_none
local function handle_guest_api()
    local is_none = require "is_none"
    return is_none.handle_guest_session_api()
end

-- =============================================
-- OLLAMA STREAMING HANDLER - USE SHARED MODULE
-- =============================================

local function handle_ollama_chat_stream()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_guest" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Guest session required"
        }))
        return ngx.exit(403)
    end
    
    -- Guest-specific pre-stream check function
    local function guest_pre_stream_check(message, request_data)
        local current_count = user_data.message_count or 0
        
        if current_count >= (user_data.max_messages or GUEST_MESSAGE_LIMIT) then
            return false, "Guest message limit reached (" .. (user_data.max_messages or GUEST_MESSAGE_LIMIT) .. " messages). Register for unlimited access."
        end
        
        if user_data.expires_at and ngx.time() >= user_data.expires_at then
            return false, "Guest session expired. Please start a new session."
        end
        
        update_guest_message_count(user_data)
        return true, nil
    end
    
    -- Use shared Ollama streaming from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    local stream_context = {
        user_type = "is_guest",
        username = username,
        user_data = user_data,
        include_history = false,
        history_limit = 0,
        pre_stream_check = guest_pre_stream_check,
        default_options = {
            model = os.getenv("MODEL_NAME") or "devstral",
            temperature = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.7,
            max_tokens = tonumber(os.getenv("MODEL_NUM_PREDICT")) or 1024
        }
    }
    
    return stream_ollama.handle_chat_stream_common(stream_context)
end

-- =============================================
-- MAIN ROUTE HANDLER - GUESTS CAN SEE ALL ROUTES
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
-- MODULE EXPORTS
-- =============================================

return {
    -- Main route handler
    handle_route = handle_route,
    
    -- Page handlers
    handle_index_page = handle_index_page,
    handle_dash_page = handle_dash_page,
    handle_chat_page = handle_chat_page,
    handle_login_page = handle_login_page,
    handle_register_page = handle_register_page,
    
    -- API handlers
    handle_guest_api = handle_guest_api,
    handle_chat_api = handle_chat_api,
    handle_ollama_chat_stream = handle_ollama_chat_stream,
    
    -- Session management functions
    get_guest_stats = get_guest_stats,
    update_guest_message_count = update_guest_message_count,
    
    -- Helper functions
    get_guest_username = get_guest_username,
    get_nav_buttons = get_nav_buttons,
    get_chat_features = get_chat_features,
    build_guest_dashboard = build_guest_dashboard
}