-- nginx/lua/is_approved.lua - Universal templates with server-controlled data
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

-- UNIVERSAL CHAT PAGE - same template for all approved users
local function handle_chat_page()
    local username, user_data = is_who.require_approved()
    
    local is_admin = user_data.is_admin == "true"
    
    -- Build nav links based on permissions
    local nav_links = '<a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Chat</a>'
    nav_links = nav_links .. '<a class="nav-link" href="/dashboard"><i class="bi bi-speedometer2"></i> Dashboard</a>'
    if is_admin then
        nav_links = '<a class="nav-link" href="/admin"><i class="bi bi-gear"></i> Admin</a>' .. nav_links
    end
    
    local nav_user = string.format([[
<span class="navbar-text me-3">%s%s</span>
<button class="btn btn-outline-light btn-sm" onclick="DevstralCommon.logout()"><i class="bi bi-box-arrow-right"></i> Logout</button>
]], username, is_admin and " (Admin)" or "")

    -- UNIVERSAL TEMPLATE - JavaScript will populate features based on API response
    template.render_template("/usr/local/openresty/nginx/html/chat.html", {
        nav_links = nav_links,
        nav_user = nav_user,
        storage_type = "redis",
        user_type = is_admin and "admin" or "approved"
    })
end

-- UNIVERSAL DASHBOARD PAGE - same template for all approved users  
local function handle_dashboard_page()
    local username, user_data = is_who.require_approved()
    
    local is_admin = user_data.is_admin == "true"
    
    -- Build nav links based on permissions
    local nav_links = '<a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Chat</a>'
    nav_links = nav_links .. '<a class="nav-link" href="/dashboard"><i class="bi bi-speedometer2"></i> Dashboard</a>'
    if is_admin then
        nav_links = '<a class="nav-link" href="/admin"><i class="bi bi-gear"></i> Admin</a>' .. nav_links
    end
    
    local nav_user = string.format([[
<span class="navbar-text me-3">%s%s</span>
<button class="btn btn-outline-light btn-sm" onclick="DevstralCommon.logout()"><i class="bi bi-box-arrow-right"></i> Logout</button>
]], username, is_admin and " (Admin)" or "")

    -- UNIVERSAL TEMPLATE - JavaScript will populate features based on API response
    template.render_template("/usr/local/openresty/nginx/html/dashboard.html", {
        nav_links = nav_links,
        nav_user = nav_user
    })
end

-- SECURE CHAT STREAMING - permission-based features
local function handle_chat_stream()
    local user_type, username = is_who.set_vars()
    
    if user_type ~= "admin" and user_type ~= "approved" then
        send_json(403, { error = "Approved user access required" })
    end
    
    -- Check if can start SSE session
    local can_start, start_message = server.can_start_sse_session(user_type, username)
    if not can_start then
        send_json(503, { 
            error = "SSE capacity reached", 
            message = start_message,
            max_sessions = 5
        })
    end
    
    -- Start SSE session
    local success, session_id = server.start_sse_session(user_type, username)
    if not success then
        send_json(503, { error = "Could not start SSE session" })
    end
    
    ngx.req.read_body()
    local data = cjson.decode(ngx.req.get_body_data() or "{}")
    local message = data.message
    local include_history = data.include_history or false
    local options = data.options or {}

    if not message or message:match("^%s*$") then
        send_json(400, { error = "Message cannot be empty" })
    end

    -- Check rate limits (admins get higher limits)
    local rate_ok, rate_message = server.check_rate_limit(username, user_type == "admin")
    if not rate_ok then
        send_json(429, { error = rate_message })
    end

    -- Set streaming headers
    ngx.header.content_type = "text/plain"
    ngx.header.cache_control = "no-cache"
    ngx.header.connection = "keep-alive"
    ngx.header["X-Chat-Storage"] = "redis"
    ngx.header["X-SSE-Session-ID"] = session_id
    ngx.header["X-User-Type"] = user_type

    local messages = {}
    
    -- Include chat history if requested (and user has permission)
    if include_history then
        local history = server.get_chat_history(username, user_type == "admin" and 20 or 10)
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    
    table.insert(messages, { role = "user", content = message })

    -- Save user message to Redis
    server.save_message(username, "user", message)

    ngx.log(ngx.INFO, "Starting chat stream for " .. user_type .. " " .. username .. " (session: " .. session_id .. ")")

    local accumulated = ""
    local chunk_count = 0
    local final_response, err = server.call_ollama_streaming(messages, options, function(chunk)
        accumulated = chunk.accumulated
        chunk_count = chunk_count + 1
        
        -- Update session activity
        server.update_sse_activity(session_id)
        
        -- Send chunk with user type info
        send_sse_chunk({ 
            content = chunk.content, 
            done = chunk.done,
            chunk_id = chunk_count,
            storage_type = "redis",
            user_type = user_type
        })
    end)

    if err then
        ngx.log(ngx.ERR, "Chat streaming error: " .. err)
        send_sse_chunk({ error = err })
    else
        -- Save AI response to Redis
        server.save_message(username, "assistant", accumulated)
        ngx.log(ngx.INFO, "Chat stream completed: " .. chunk_count .. " chunks, " .. #accumulated .. " chars")
    end

    send_sse_chunk("[DONE]")
    ngx.exit(200)
end

-- SECURE CHAT HISTORY - permission-based limits
local function handle_chat_history()
    local username, user_data = is_who.require_approved()
    
    local is_admin = user_data.is_admin == "true"
    local limit = tonumber(ngx.var.arg_limit) or (is_admin and 50 or 20)
    local history = server.get_chat_history(username, limit)
    
    send_json(200, {
        success = true,
        messages = history,
        count = #history,
        storage_type = "redis",
        user_type = is_admin and "admin" or "approved",
        max_limit = is_admin and 100 or 50
    })
end

-- SECURE CHAT CLEAR - all approved users can clear
local function handle_clear_chat()
    local username = is_who.require_approved()
    
    server.clear_chat_history(username)
    
    send_json(200, {
        success = true,
        message = "Chat history cleared",
        storage_type = "redis"
    })
end

-- SECURE API ROUTING - server-side permission checks
local function handle_chat_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method

    if uri == "/api/chat/stream" and method == "POST" then
        handle_chat_stream()
    elseif uri == "/api/chat/history" and method == "GET" then
        handle_chat_history()
    elseif uri == "/api/chat/clear" and method == "POST" then
        handle_clear_chat()
    else
        send_json(404, { error = "Chat API endpoint not found" })
    end
end

return {
    handle_chat_page = handle_chat_page,
    handle_dashboard_page = handle_dashboard_page,
    handle_chat_api = handle_chat_api
}