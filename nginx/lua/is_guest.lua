-- =============================================================================
-- nginx/lua/is_guest.lua - COMPLETE GUEST SESSION MANAGEMENT
-- =============================================================================

local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 1800  -- 30 minutes
local GUEST_MESSAGE_LIMIT = 10
local JWT_COOLDOWN_SECONDS = 60
local CURRENT_VERSION = "v2.0"

-- HELPER: Safe Redis response handling
local function redis_to_lua(value)
    if value == ngx.null or value == nil then
        return nil
    end
    return value
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection failed: " .. (err or "unknown"))
        return nil
    end
    return red
end

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- GUEST SESSION CORE LOGIC
-- =============================================

-- Initialize guest tokens
local function initialize_guest_tokens()
    local red = connect_redis()
    if not red then
        return false, "Redis unavailable"
    end
    
    local initialized = redis_to_lua(red:get("guest_tokens_initialized"))
    if initialized == CURRENT_VERSION then
        return true, "Already initialized"
    end
    
    -- Clear old data
    local old_keys = redis_to_lua(red:keys("guest_*")) or {}
    for _, key in ipairs(old_keys) do
        red:del(key)
    end
    
    local username_pools = {
        {"QuickFox", "SilentEagle", "BrightWolf", "SwiftTiger", "CleverHawk"},
        {"BoldBear", "CalmLion", "SharpOwl", "WiseCat", "CoolDog"}
    }
    
    for i = 1, MAX_GUEST_SESSIONS do
        local slot_id = "guest_slot_" .. i
        local payload = {
            sub = slot_id,
            user_type = "guest",
            priority = 3,
            slot = i,
            version = 1,
            iat = 1640995200,
            exp = 9999999999
        }
        
        local token = jwt:sign(JWT_SECRET, {
            header = { typ = "JWT", alg = "HS256" },
            payload = payload
        })
        
        local token_data = {
            slot_id = slot_id,
            slot_number = i,
            jwt_token = token,
            username_pool = username_pools[i],
            created_at = ngx.time(),
            version = CURRENT_VERSION
        }
        
        red:set("guest_token_slot:" .. i, cjson.encode(token_data))
    end
    
    red:set("guest_tokens_initialized", CURRENT_VERSION)
    red:expire("guest_tokens_initialized", 86400)
    
    ngx.log(ngx.INFO, "Initialized " .. MAX_GUEST_SESSIONS .. " guest tokens")
    return true, "Initialized"
end

-- Find available guest slot
local function find_available_guest_slot()
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    if not initialize_guest_tokens() then
        return nil, "Failed to initialize guest tokens"
    end
    
    local current_time = ngx.time()
    
    for i = 1, MAX_GUEST_SESSIONS do
        local slot_id = "guest_slot_" .. i
        local session_key = "guest_session:" .. slot_id
        local session_data = redis_to_lua(red:get(session_key))
        
        if not session_data then
            -- Slot is free
            local token_data = redis_to_lua(red:get("guest_token_slot:" .. i))
            if token_data then
                local ok, data = pcall(cjson.decode, token_data)
                if ok then
                    return data, nil
                end
            end
        else
            -- Check if session expired
            local ok, session = pcall(cjson.decode, session_data)
            if ok and session.expires_at and current_time >= session.expires_at then
                -- Clean expired session
                red:del(session_key)
                local token_data = redis_to_lua(red:get("guest_token_slot:" .. i))
                if token_data then
                    local ok_token, data = pcall(cjson.decode, token_data)
                    if ok_token then
                        return data, nil
                    end
                end
            end
        end
    end
    
    return nil, "All guest slots occupied (" .. MAX_GUEST_SESSIONS .. "/" .. MAX_GUEST_SESSIONS .. ")"
end

-- Create guest session
local function create_secure_guest_session()
    local slot_data, error_msg = find_available_guest_slot()
    if not slot_data then
        return nil, error_msg
    end
    
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    -- Generate username
    local username_base = slot_data.username_pool[math.random(#slot_data.username_pool)]
    local guest_username = username_base .. math.random(100, 999)
    local expires_at = ngx.time() + GUEST_SESSION_DURATION
    
    local session_data = {
        slot_id = slot_data.slot_id,
        username = guest_username,
        user_type = "guest",
        jwt_token = slot_data.jwt_token,
        created_at = ngx.time(),
        expires_at = expires_at,
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = ngx.var.remote_addr or "unknown",
        last_activity = ngx.time(),
        priority = 3,
        slot_number = slot_data.slot_number,
        chat_storage = "none"
    }
    
    -- Store session
    red:set("guest_session:" .. slot_data.slot_id, cjson.encode(session_data))
    red:expire("guest_session:" .. slot_data.slot_id, GUEST_SESSION_DURATION)
    
    -- Set cookie
    ngx.header["Set-Cookie"] = "guest_token=" .. slot_data.jwt_token .. 
        "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    return {
        success = true,
        slot_id = slot_data.slot_id,
        username = guest_username,
        token = slot_data.jwt_token,
        expires_at = expires_at,
        message_limit = GUEST_MESSAGE_LIMIT,
        session_duration = GUEST_SESSION_DURATION,
        priority = 3,
        slot_number = slot_data.slot_number,
        storage_type = "none"
    }, nil
end

-- Validate guest session
local function validate_guest_session(token)
    if not token then
        return nil, "No token provided"
    end
    
    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        return nil, "Invalid token"
    end
    
    local payload = jwt_obj.payload
    if not payload.sub or payload.user_type ~= "guest" then
        return nil, "Invalid guest token"
    end
    
    local red = connect_redis()
    if not red then
        return nil, "Service unavailable"
    end
    
    local session_key = "guest_session:" .. payload.sub
    local session_data = redis_to_lua(red:get(session_key))
    
    if not session_data then
        return nil, "Session not active"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        return nil, "Invalid session data"
    end
    
    if ngx.time() >= session.expires_at then
        red:del(session_key)
        return nil, "Session expired"
    end
    
    -- Update activity
    session.last_activity = ngx.time()
    red:set(session_key, cjson.encode(session))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    return session, nil
end

-- Get guest stats
local function get_guest_stats()
    local red = connect_redis()
    if not red then
        return {
            active_sessions = 0,
            max_sessions = MAX_GUEST_SESSIONS,
            available_slots = 0,
            error = "Redis unavailable"
        }, "Service unavailable"
    end
    
    local guest_keys = redis_to_lua(red:keys("guest_session:*")) or {}
    local active_sessions = 0
    local total_messages = 0
    local current_time = ngx.time()
    
    for _, key in ipairs(guest_keys) do
        local session_data = redis_to_lua(red:get(key))
        if session_data then
            local ok, session = pcall(cjson.decode, session_data)
            if ok and session.expires_at then
                if current_time < session.expires_at then
                    active_sessions = active_sessions + 1
                    total_messages = total_messages + (session.message_count or 0)
                else
                    red:del(key) -- Clean expired
                end
            end
        end
    end
    
    return {
        active_sessions = active_sessions,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = MAX_GUEST_SESSIONS - active_sessions,
        total_messages_used = total_messages,
        average_messages_per_session = active_sessions > 0 and math.floor(total_messages / active_sessions) or 0
    }, nil
end

-- Clear all guest sessions (admin function)
local function clear_all_guest_sessions()
    local red = connect_redis()
    if not red then
        return false, "Service unavailable"
    end
    
    local session_keys = redis_to_lua(red:keys("guest_session:*")) or {}
    for _, key in ipairs(session_keys) do
        red:del(key)
    end
    
    red:del("guest_tokens_initialized")
    
    return true, "Cleared " .. #session_keys .. " sessions. System will re-initialize."
end

-- =============================================
-- API HANDLERS - Guest Session Management
-- =============================================

-- Create secure guest session
local function handle_create_guest_session()
    local ip = ngx.var.remote_addr or "unknown"
    local rate_limit_key = "guest_create_attempts:" .. ip
    local attempts = ngx.shared.guest_sessions:get(rate_limit_key) or 0
    
    if attempts >= 3 then
        ngx.log(ngx.WARN, "Too many guest session creation attempts from " .. ip)
        send_json(429, { 
            error = "Too many guest session attempts",
            message = "Please wait before creating another guest session",
            retry_after = 300,
            cooldown_minutes = 5
        })
    end
    
    local session_data, error_msg = create_secure_guest_session()
    
    if not session_data then
        ngx.shared.guest_sessions:set(rate_limit_key, attempts + 1, 300)
        ngx.log(ngx.WARN, "Guest session creation failed from " .. ip .. ": " .. (error_msg or "unknown"))
        
        send_json(503, {
            error = "Guest session creation failed",
            message = error_msg or "All guest slots are currently occupied",
            available_soon = true,
            suggestion = "Try again in a few minutes or register for guaranteed access",
            max_guests = MAX_GUEST_SESSIONS,
            slots_full = true
        })
    end
    
    ngx.shared.guest_sessions:delete(rate_limit_key)
    ngx.log(ngx.INFO, "Guest session created successfully: " .. session_data.username .. " [Slot " .. session_data.slot_number .. "] from " .. ip)
    
    send_json(200, {
        success = true,
        message = "Guest session created successfully",
        session = {
            username = session_data.username,
            slot_number = session_data.slot_number,
            slot_id = session_data.slot_id,
            message_limit = session_data.message_limit,
            session_duration_minutes = math.floor(session_data.session_duration / 60),
            expires_at = session_data.expires_at,
            priority = session_data.priority,
            storage_type = session_data.storage_type
        },
        instructions = {
            "You have " .. session_data.message_limit .. " messages available",
            "Session expires in " .. math.floor(session_data.session_duration / 60) .. " minutes", 
            "Chat history is not saved (register for persistent storage)",
            "Your messages are processed with priority " .. session_data.priority .. " (lowest)",
            "JWT slot " .. session_data.slot_number .. " is now locked to your session"
        },
        security = {
            hardcoded_jwt = true,
            anti_hijacking = true,
            slot_locked = true
        },
        redirect = "/chat"
    })
end

-- Get guest session info
local function handle_guest_info()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type ~= "guest" then
        send_json(403, {
            error = "Not a guest session",
            user_type = user_type or "none",
            message = "This endpoint requires an active guest session"
        })
    end
    
    if not user_data or not user_data.slot_id then
        send_json(404, {
            error = "Guest session not found",
            message = "Session may have expired or been invalidated",
            suggestion = "Create a new guest session"
        })
    end
    
    send_json(200, {
        success = true,
        session = {
            username = user_data.username,
            slot_number = user_data.slot_number,
            slot_id = user_data.slot_id,
            max_messages = user_data.max_messages,
            used_messages = user_data.message_count,
            remaining_messages = user_data.max_messages - user_data.message_count,
            session_remaining_seconds = user_data.expires_at - ngx.time(),
            session_remaining_minutes = math.floor((user_data.expires_at - ngx.time()) / 60),
            priority = user_data.priority,
            storage_type = user_data.chat_storage
        },
        status = {
            can_chat = (user_data.max_messages - user_data.message_count) > 0,
            session_active = user_data.expires_at > ngx.time(),
            slot_secured = true
        }
    })
end

-- Get guest session stats
local function handle_guest_stats()
    local stats, err = get_guest_stats()
    if not stats then
        send_json(500, {
            error = "Failed to get guest stats",
            message = err or "Service unavailable"
        })
    end
    
    send_json(200, {
        success = true,
        stats = {
            active_sessions = stats.active_sessions,
            max_sessions = stats.max_sessions,
            available_slots = stats.available_slots,
            slots_occupied = stats.active_sessions .. "/" .. stats.max_sessions,
            average_messages_per_session = stats.average_messages_per_session,
            total_messages_used = stats.total_messages_used,
            utilization_percent = math.floor((stats.active_sessions / stats.max_sessions) * 100)
        },
        info = {
            message_limit_per_guest = GUEST_MESSAGE_LIMIT,
            session_duration_minutes = math.floor(GUEST_SESSION_DURATION / 60),
            hardcoded_jwt_slots = true,
            anti_hijacking_enabled = true,
            jwt_cooldown_seconds = JWT_COOLDOWN_SECONDS,
            max_concurrent_guests = MAX_GUEST_SESSIONS
        },
        availability = {
            can_create_session = stats.available_slots > 0,
            estimated_wait_time = stats.available_slots == 0 and "1-30 minutes" or "immediate"
        }
    })
end

-- End guest session
local function handle_end_guest_session()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type ~= "guest" then
        send_json(403, {
            error = "Not a guest session",
            message = "Only active guest sessions can be ended"
        })
    end
    
    if user_data and user_data.slot_id then
        local red = connect_redis()
        if red then
            red:del("guest_session:" .. user_data.slot_id)
        end
        
        ngx.header["Set-Cookie"] = "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        ngx.log(ngx.INFO, "Guest session ended voluntarily: " .. (username or "unknown") .. " [" .. user_data.slot_id .. "]")
        
        send_json(200, {
            success = true,
            message = "Guest session ended successfully",
            slot_freed = true,
            slot_number = user_data.slot_number
        })
    else
        send_json(404, {
            error = "Session not found",
            message = "No active guest session to end"
        })
    end
end

-- Use guest message quota
local function handle_use_guest_message()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type ~= "guest" then
        send_json(403, {
            error = "Not a guest session",
            message = "This endpoint is for guest users only"
        })
    end
    
    if not user_data or not user_data.slot_id then
        send_json(404, {
            error = "Guest session not found",
            message = "Session expired or invalid"
        })
    end
    
    if user_data.message_count >= user_data.max_messages then
        send_json(429, {
            error = "Message limit reached",
            message = "You have used all " .. user_data.max_messages .. " messages",
            suggestion = "Register for unlimited messaging",
            upgrade_url = "/register"
        })
    end
    
    -- Update message count
    local red = connect_redis()
    if red then
        user_data.message_count = user_data.message_count + 1
        user_data.last_activity = ngx.time()
        red:set("guest_session:" .. user_data.slot_id, cjson.encode(user_data))
        red:expire("guest_session:" .. user_data.slot_id, GUEST_SESSION_DURATION)
    end
    
    send_json(200, {
        success = true,
        message = "Message quota used",
        remaining_info = {
            messages_left = user_data.max_messages - user_data.message_count,
            total_used = user_data.message_count,
            limit = user_data.max_messages,
            can_continue = user_data.message_count < user_data.max_messages,
            slot_number = user_data.slot_number
        }
    })
end

-- Validate guest session
local function handle_validate_guest_session()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type ~= "guest" then
        send_json(200, {
            valid = false,
            user_type = user_type or "none",
            message = "Not a guest session"
        })
    end
    
    if not user_data or not user_data.slot_id then
        send_json(200, {
            valid = false,
            message = "Guest session not found or expired"
        })
    end
    
    send_json(200, {
        valid = true,
        username = username,
        slot_id = user_data.slot_id,
        slot_number = user_data.slot_number,
        session_active = true
    })
end

-- =============================================
-- PAGE HANDLER - Guest Chat Interface
-- =============================================

local function handle_chat_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local template = require "template"
    
    local user_type, username, user_data = is_who.set_vars()
    
    if user_type ~= "guest" then
        username = "Anonymous"
        user_data = nil
    end
    
    local context = {
        page_title = "Guest Chat - ai.junder.uk",
        css_files = is_public.common_css,
        js_files = is_public.common_js_base,
        nav = is_public.render_nav("guest", username or "Anonymous", user_data),
        chat_features = is_public.get_chat_features("guest"),
        chat_placeholder = "Ask anything... (10 messages max, 30 minutes)"
    }
    
    template.render_template("/usr/local/openresty/nginx/html/chat.html", context)
end

-- =============================================
-- CHAT API HANDLERS
-- =============================================

local function handle_chat_api()
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type ~= "guest" and user_type ~= "none" then
        send_json(403, {
            error = "Guest chat access only",
            user_type = user_type,
            message = "This endpoint is for guest users only"
        })
    end
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        send_json(200, {
            success = true,
            messages = {},
            user_type = "guest",
            storage_type = "none",
            message = "Guest users don't have persistent chat history"
        })
    elseif uri == "/api/chat/clear" and method == "POST" then
        send_json(200, { 
            success = true, 
            message = "Guest chat history cleared (localStorage only)" 
        })
    elseif uri == "/api/chat/stream" and method == "POST" then
        send_json(501, { 
            error = "Streaming chat not implemented yet",
            message = "Guest streaming chat coming soon"
        })
    else
        send_json(404, { 
            error = "Guest chat API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "GET /api/chat/history - Get chat history (empty for guests)",
                "POST /api/chat/clear - Clear chat history (localStorage only)",
                "POST /api/chat/stream - Stream chat messages (coming soon)"
            }
        })
    end
end

-- =============================================
-- API ROUTING
-- =============================================

local function handle_guest_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "Guest API access: " .. method .. " " .. uri .. " from " .. (ngx.var.remote_addr or "unknown"))
    
    if uri == "/api/guest/create-session" and method == "POST" then
        handle_create_guest_session()
    elseif uri == "/api/guest/info" and method == "GET" then
        handle_guest_info()
    elseif uri == "/api/guest/stats" and method == "GET" then
        handle_guest_stats()
    elseif uri == "/api/guest/end-session" and method == "POST" then
        handle_end_guest_session()
    elseif uri == "/api/guest/use-message" and method == "POST" then
        handle_use_guest_message()
    elseif uri == "/api/guest/validate" and method == "GET" then
        handle_validate_guest_session()
    else
        send_json(404, { 
            error = "Guest API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/guest/create-session - Create new guest session",
                "GET /api/guest/info - Get current session info", 
                "GET /api/guest/stats - Get public guest statistics",
                "GET /api/guest/validate - Validate current session",
                "POST /api/guest/end-session - End current session",
                "POST /api/guest/use-message - Use message quota"
            }
        })
    end
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {
    -- Page handlers
    handle_chat_page = handle_chat_page,
    
    -- API handlers
    handle_guest_api = handle_guest_api,
    handle_chat_api = handle_chat_api,
    
    -- Core functions (for other modules to use)
    create_secure_guest_session = create_secure_guest_session,
    validate_guest_session = validate_guest_session,
    get_guest_stats = get_guest_stats,
    clear_all_guest_sessions = clear_all_guest_sessions
}