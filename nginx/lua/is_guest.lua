-- =============================================================================
-- nginx/lua/is_guest.lua - UNIFIED GUEST MANAGEMENT WITH TEMPLATE RENDERER
-- =============================================================================

local cjson = require "cjson"
local server = require "server"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- PAGE HANDLER - Guest Chat Interface
-- =============================================

local function handle_chat_page()
    local is_who = require "is_who"
    local is_public = require "is_public"
    local template = require "template"
    
    local user_type, username, user_data = is_who.set_vars()
    
    -- Handle non-guest users who access guest chat
    if user_type ~= "guest" then
        username = "Anonymous"
    end
    
    -- Guest Redis data - limited access
    local is_guest_redis_data = {
        username = username,
        role = "guest",
        permissions = "limited_chat_access",
        user_badge = is_public.get_user_badge("guest", user_data),
        dash_buttons = is_public.get_nav_buttons("guest", username, user_data),
        slot_number = user_data and user_data.slot_number or "unknown",
        message_limit = "10",
        session_type = "temporary"
    }
    
    -- Guest content data - extends public shared content
    local is_guest_content_data = is_public.build_content_data("chat", "guest", {
        -- Guest-specific JavaScript (only base - no extensions)
        js_files = is_public.shared_content_data.base_js_files,
        
        -- Guest-specific chat features
        chat_features = is_public.get_chat_features("guest"),
        
        -- Guest-specific content
        storage_type = "localStorage",
        session_duration = "30 minutes",
        registration_prompt = "enabled"
    })
    
    template.render_and_output("app.html", is_guest_redis_data, is_guest_content_data)
end

-- =============================================
-- API HANDLERS - Guest Session Management
-- =============================================

-- SECURITY: Create secure guest session with hardcoded JWT
local function handle_create_guest_session()
    -- SECURITY: Rate limit guest session creation by IP
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
    
    -- Attempt to create secure guest session
    local session_data, error_msg = server.create_secure_guest_session()
    
    if not session_data then
        -- Increment failed attempts
        ngx.shared.guest_sessions:set(rate_limit_key, attempts + 1, 300) -- 5 minute lockout
        
        ngx.log(ngx.WARN, "Guest session creation failed from " .. ip .. ": " .. (error_msg or "unknown"))
        send_json(503, {
            error = "Guest session creation failed",
            message = error_msg or "All guest slots are currently occupied",
            available_soon = true,
            suggestion = "Try again in a few minutes or register for guaranteed access",
            max_guests = 5,
            slots_full = true
        })
    end
    
    -- SECURITY: Clear failed attempts on successful creation
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
            storage_type = session_data.storage_type,
            jwt_locked = session_data.is_jwt_locked
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
    
    -- Get current session limits
    local limits, err = server.get_guest_limits(user_data.slot_id)
    if not limits then
        send_json(500, {
            error = "Failed to get session info",
            message = err or "Unknown error accessing session data"
        })
    end
    
    send_json(200, {
        success = true,
        session = {
            username = limits.username,
            slot_number = limits.slot_number,
            slot_id = user_data.slot_id,
            max_messages = limits.max_messages,
            used_messages = limits.used_messages,
            remaining_messages = limits.remaining_messages,
            session_remaining_seconds = limits.session_remaining,
            session_remaining_minutes = math.floor(limits.session_remaining / 60),
            priority = limits.priority,
            storage_type = limits.storage_type
        },
        status = {
            can_chat = limits.remaining_messages > 0,
            session_active = limits.session_remaining > 0,
            jwt_locked = user_data.is_jwt_locked or false,
            slot_secured = true
        },
        warnings = limits.remaining_messages <= 2 and {
            "Only " .. limits.remaining_messages .. " messages remaining",
            "Consider registering for unlimited access"
        } or nil
    })
end

-- Get guest session stats (public endpoint)
local function handle_guest_stats()
    local stats, err = server.get_guest_stats()
    if not stats then
        send_json(500, {
            error = "Failed to get guest stats",
            message = err or "Service unavailable"
        })
    end
    
    -- Public version (no sensitive data)
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
            message_limit_per_guest = 10,
            session_duration_minutes = 30,
            hardcoded_jwt_slots = true,
            anti_hijacking_enabled = true,
            jwt_cooldown_seconds = 60,
            max_concurrent_guests = 5
        },
        availability = {
            can_create_session = stats.available_slots > 0,
            estimated_wait_time = stats.available_slots == 0 and "1-30 minutes" or "immediate"
        }
    })
end

-- End guest session (logout)
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
        local success, msg = server.end_guest_session(user_data.slot_id)
        if success then
            -- Clear guest token cookie
            ngx.header["Set-Cookie"] = "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
            
            ngx.log(ngx.INFO, "Guest session ended voluntarily: " .. (username or "unknown") .. " [" .. user_data.slot_id .. "]")
            
            send_json(200, {
                success = true,
                message = "Guest session ended successfully",
                slot_freed = true,
                slot_number = user_data.slot_number,
                jwt_unlocked = true,
                message_usage = {
                    used = user_data.message_count or 0,
                    limit = 10
                }
            })
        else
            send_json(500, {
                error = "Failed to end session",
                message = msg or "Unknown error during session cleanup"
            })
        end
    else
        send_json(404, {
            error = "Session not found",
            message = "No active guest session to end"
        })
    end
end

-- Check guest message usage (for rate limiting)
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
    
    local success, msg, usage_info = server.use_guest_message(user_data.slot_id)
    
    if not success then
        send_json(429, {
            error = "Message limit reached",
            message = msg,
            suggestion = "Register for unlimited messaging",
            upgrade_url = "/register",
            current_usage = "10/10 messages used"
        })
    end
    
    send_json(200, {
        success = true,
        message = "Message quota used",
        usage = usage_info,
        remaining_info = {
            messages_left = usage_info.remaining,
            total_used = usage_info.used,
            limit = usage_info.max,
            can_continue = usage_info.remaining > 0,
            slot_number = usage_info.slot
        },
        warnings = usage_info.remaining <= 2 and {
            "Low message count: " .. usage_info.remaining .. " remaining",
            "Consider registering for unlimited access"
        } or nil
    })
end

-- Validate guest session (middleware helper)
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
-- API ROUTING
-- =============================================

-- SECURE guest API routing
local function handle_guest_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    -- Log API access for security monitoring
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
    handle_create_guest_session = handle_create_guest_session,
    handle_guest_info = handle_guest_info,
    handle_guest_stats = handle_guest_stats,
    handle_end_guest_session = handle_end_guest_session,
    handle_use_guest_message = handle_use_guest_message,
    handle_validate_guest_session = handle_validate_guest_session
}