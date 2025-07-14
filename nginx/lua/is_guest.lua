-- nginx/lua/is_guest.lua - Guest interface using nav.html template
local cjson = require "cjson"
local template = require "template"
local server = require "server"
local is_who = require "is_who"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function send_sse_chunk(data)
    if data == "[DONE]" then
        ngx.say("data: [DONE]\n")
    else
        ngx.say("data: " .. cjson.encode(data) .. "\n")
    end
    ngx.flush(true)
end

-- Create guest session
local function handle_create_guest_session()
    local session_data = server.create_guest_session()
    
    send_json(200, {
        success = true,
        session = {
            username = session_data.username,
            expires_at = session_data.expires_at,
            session_duration = session_data.expires_at - ngx.time()
        },
        limits = {
            max_messages = session_data.max_messages,
            used_messages = 0,
            remaining_messages = session_data.max_messages
        },
        message = "Guest session created - chat history stored in browser localStorage only",
        storage_type = "localStorage",
        permissions = {"guest_chat"}
    })
end

-- UNIVERSAL GUEST CHAT PAGE - same template but guest navigation
local function handle_guest_chat_page()
    local user_type, username, user_data = is_who.set_vars()
    
    if user_type == "guest" then
        -- Active guest session - show guest nav
        local nav_links = '<a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Guest Chat</a>'
        
        local nav_user = string.format([[
<span class="navbar-text me-3">%s (Guest)</span>
<a class="nav-link" href="/register"><i class="bi bi-person-plus"></i> Register</a>
]], username)

        template.render_template("/usr/local/openresty/nginx/html/chat.html", {
            nav_links = nav_links,
            nav_user = nav_user,
            storage_type = "localStorage",
            user_type = "guest"
        })
    else
        -- No guest session - show public nav
        local nav_links = ''
        
        local nav_user = [[
<a class="nav-link" href="/login"><i class="bi bi-box-arrow-in-right"></i> Login</a>
<a class="nav-link" href="/register"><i class="bi bi-person-plus"></i> Register</a>
]]

        template.render_template("/usr/local/openresty/nginx/html/chat.html", {
            nav_links = nav_links,
            nav_user = nav_user,
            storage_type = "localStorage",
            user_type = "none"
        })
    end
end

-- GUEST CHAT STREAMING - limited features
local function handle_guest_chat_stream()
    local user_type, username = is_who.set_vars()
    
    if user_type ~= "guest" then
        send_json(403, { error = "Guest session required" })
    end
    
    -- Check if can start SSE session
    local can_start, start_message = server.can_start_sse_session("guest", username)
    if not can_start then
        send_json(503, { 
            error = "SSE capacity reached", 
            message = start_message,
            max_sessions = 5
        })
    end
    
    -- Start SSE session
    local success, session_id = server.start_sse_session("guest", username)
    if not success then
        send_json(503, { error = "Could not start SSE session" })
    end
    
    -- Store session ID for cleanup
    ngx.var.sse_session_id = session_id
    
    ngx.req.read_body()
    local data = cjson.decode(ngx.req.get_body_data() or "{}")
    local message = data.message
    local options = data.options or {}

    if not message or message:match("^%s*$") then
        send_json(400, { error = "Message cannot be empty" })
    end

    -- Check guest message limits
    local can_use, use_message = server.use_guest_message(username)
    if not can_use then
        local limits = server.get_guest_limits(username)
        if not limits then
            send_json(401, { error = "Guest session expired" })
        else
            send_json(429, { 
                error = "Guest message limit exceeded",
                limits = limits,
                message = "Register for unlimited access"
            })
        end
    end

    -- Set streaming headers
    ngx.header.content_type = "text/plain"
    ngx.header.cache_control = "no-cache"
    ngx.header.connection = "keep-alive"
    ngx.header["X-Chat-Storage"] = "localStorage"
    ngx.header["X-Session-Type"] = "guest"
    ngx.header["X-SSE-Session-ID"] = session_id

    -- Guests don't get history from server - they use localStorage
    local messages = {{ role = "user", content = message }}

    ngx.log(ngx.INFO, "Starting guest chat stream for " .. username .. " (session: " .. session_id .. ")")

    local accumulated = ""
    local chunk_count = 0
    -- Guest gets reduced token limit
    local guest_options = {
        temperature = options.temperature or 0.8,
        max_tokens = 512  -- Limited for guests
    }
    
    local final_response, err = server.call_ollama_streaming(messages, guest_options, function(chunk)
        accumulated = chunk.accumulated
        chunk_count = chunk_count + 1
        
        -- Update session activity
        server.update_sse_activity(session_id)
        
        -- Send chunk with guest indicators
        send_sse_chunk({ 
            content = chunk.content, 
            done = chunk.done,
            chunk_id = chunk_count,
            storage_type = "localStorage",
            user_type = "guest"
        })
    end)

    if err then
        ngx.log(ngx.ERR, "Guest chat streaming error: " .. err)
        send_sse_chunk({ error = err })
    else
        ngx.log(ngx.INFO, "Guest chat stream completed: " .. chunk_count .. " chunks")
    end

    -- Send final instruction for localStorage storage
    send_sse_chunk({
        type = "storage_instruction",
        message = "Chat history stored in browser localStorage only",
        storage_type = "localStorage",
        upgrade_message = "Register for unlimited messages and cloud storage"
    })

    send_sse_chunk("[DONE]")
    ngx.exit(200)
end

-- Guest status/limits - only shows guest data
local function handle_guest_status()
    local user_type, username = is_who.set_vars()
    
    if user_type == "guest" then
        local limits = server.get_guest_limits(username)
        if not limits then
            send_json(401, {
                success = false,
                error = "Guest session expired",
                message = "Please refresh to start a new guest session"
            })
        end
        
        send_json(200, {
            success = true,
            user_type = "guest",
            username = username,
            limits = limits,
            storage_type = "localStorage",
            permissions = {"guest_chat"},
            upgrade_available = true
        })
    else
        send_json(401, {
            success = false,
            error = "No guest session found",
            message = "Please start a guest session or login"
        })
    end
end

-- Guest chat capacity info - public data
local function handle_guest_capacity()
    local sse_stats = server.get_sse_stats()
    
    send_json(200, {
        success = true,
        capacity = {
            current_sessions = sse_stats.total_sessions,
            max_sessions = sse_stats.max_sessions,
            available_slots = sse_stats.available_slots,
            is_full = sse_stats.available_slots == 0
        },
        guest_info = {
            session_duration_minutes = 30,
            message_limit = 10,
            storage_type = "localStorage",
            upgrade_benefits = {
                "Unlimited messages",
                "Cloud storage (Redis)", 
                "Chat history saved",
                "Priority access",
                "Export conversations"
            }
        }
    })
end

-- SECURE GUEST API ROUTING
local function handle_guest_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/guest/create-session" and method == "POST" then
        handle_create_guest_session()
    elseif uri == "/api/guest/status" and method == "GET" then
        handle_guest_status()
    elseif uri == "/api/guest/capacity" and method == "GET" then
        handle_guest_capacity()
    elseif uri == "/api/chat/stream" and method == "POST" then
        handle_guest_chat_stream()
    else
        send_json(404, { error = "Guest API endpoint not found" })
    end
end

return {
    handle_guest_chat_page = handle_guest_chat_page,
    handle_create_guest_session = handle_create_guest_session,
    handle_guest_api = handle_guest_api
}