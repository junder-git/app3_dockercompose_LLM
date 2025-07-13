-- nginx/lua/guest_api.lua - Guest session API endpoints
local cjson = require "cjson"
local unified_auth = require "unified_auth"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function handle_create_guest_session()
    local session, error_msg = unified_auth.create_guest_chat_session()
    
    if not session then
        if error_msg == "Chat is full" then
            send_json(503, {
                error = "Chat capacity reached",
                message = "All guest chat slots are currently occupied. Please try again in a few minutes or register for unlimited access.",
                max_guests = unified_auth.MAX_CHAT_GUESTS
            })
        else
            send_json(500, {
                error = "Failed to create session",
                message = error_msg
            })
        end
    end
    
    local limits = unified_auth.get_guest_limits(session.session_id)
    
    send_json(200, {
        success = true,
        session = {
            session_id = session.session_id,
            username = session.username,
            created_at = session.created_at,
            expires_at = session.expires_at
        },
        limits = limits,
        message = "Guest session created successfully"
    })
end

local function handle_guest_status()
    local user_type, username, error_msg = unified_auth.check_user_access()
    
    if user_type == "guest" then
        local guest_session_id = ngx.var.cookie_guest_session
        local limits = unified_auth.get_guest_limits(guest_session_id)
        
        send_json(200, {
            success = true,
            user_type = "guest",
            username = username,
            limits = limits
        })
    elseif user_type == "user" then
        send_json(200, {
            success = true,
            user_type = "user",
            username = username
        })
    else
        send_json(401, {
            success = false,
            user_type = "none",
            error = error_msg or "No active session"
        })
    end
end

local function handle_guest_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/guest/create-session" and method == "POST" then
        handle_create_guest_session()
    elseif uri == "/api/guest/status" and method == "GET" then
        handle_guest_status()
    else
        send_json(404, { error = "Guest API endpoint not found" })
    end
end

return {
    handle_guest_api = handle_guest_api,
    handle_create_guest_session = handle_create_guest_session,
    handle_guest_status = handle_guest_status
}