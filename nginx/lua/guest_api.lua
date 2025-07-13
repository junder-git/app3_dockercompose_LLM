-- nginx/lua/guest_api.lua - Enhanced guest API with hardcoded tokens
local cjson = require "cjson"
local unified_auth = require "unified_auth"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function handle_create_guest_session()
    local session_data, error_msg, slot_num = unified_auth.create_guest_session()
    
    if not session_data then
        if error_msg == "Chat is full" then
            send_json(503, {
                error = "Chat capacity reached",
                message = "All guest chat slots are currently occupied. Please try again in a few minutes or register for unlimited access.",
                max_guests = unified_auth.MAX_CHAT_GUESTS,
                active_sessions = unified_auth.count_active_guest_sessions()
            })
        else
            send_json(500, {
                error = "Failed to create session",
                message = error_msg
            })
        end
    end
    
    local limits = unified_auth.get_guest_limits(slot_num)
    
    send_json(200, {
        success = true,
        session = {
            slot_num = session_data.slot_num,
            username = session_data.username,
            expires_at = session_data.expires_at,
            session_duration = session_data.session_duration
        },
        limits = limits,
        message = "Guest session created successfully"
    })
end

local function handle_guest_status()
    local user_type, username, slot_num = unified_auth.check_user_access()
    
    if user_type == "guest" then
        local limits = unified_auth.get_guest_limits(slot_num)
        
        if not limits then
            send_json(401, {
                success = false,
                user_type = "expired",
                error = "Guest session expired"
            })
        end
        
        send_json(200, {
            success = true,
            user_type = "guest",
            username = username,
            slot_num = slot_num,
            limits = limits
        })
    elseif user_type == "user" or user_type == "admin" then
        send_json(200, {
            success = true,
            user_type = user_type,
            username = username
        })
    else
        send_json(401, {
            success = false,
            user_type = "none",
            error = "No active session"
        })
    end
end

local function handle_guest_extend()
    -- Allow guests to extend their session (if implemented in the future)
    local user_type, username, slot_num = unified_auth.check_user_access()
    
    if user_type ~= "guest" then
        send_json(403, { error = "Only guest users can extend sessions" })
    end
    
    -- For now, return not implemented
    send_json(501, {
        error = "Session extension not implemented",
        message = "Guest sessions have a fixed duration"
    })
end

local function handle_chat_capacity()
    local active_count = unified_auth.count_active_guest_sessions()
    local max_sessions = unified_auth.MAX_CHAT_GUESTS
    local is_full = active_count >= max_sessions
    
    send_json(200, {
        success = true,
        active_sessions = active_count,
        max_sessions = max_sessions,
        utilization_percent = math.floor((active_count / max_sessions) * 100),
        is_full = is_full,
        available_slots = max_sessions - active_count,
        session_duration_minutes = unified_auth.GUEST_SESSION_DURATION / 60,
        message_limit = unified_auth.GUEST_MESSAGE_LIMIT
    })
end

local function handle_guest_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/guest/create-session" and method == "POST" then
        handle_create_guest_session()
    elseif uri == "/api/guest/status" and method == "GET" then
        handle_guest_status()
    elseif uri == "/api/guest/extend" and method == "POST" then
        handle_guest_extend()
    elseif uri == "/api/guest/capacity" and method == "GET" then
        handle_chat_capacity()
    else
        send_json(404, { error = "Guest API endpoint not found" })
    end
end

return {
    handle_guest_api = handle_guest_api,
    handle_create_guest_session = handle_create_guest_session,
    handle_guest_status = handle_guest_status,
    handle_guest_extend = handle_guest_extend,
    handle_chat_capacity = handle_chat_capacity
}