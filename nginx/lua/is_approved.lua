-- nginx/lua/is_approved.lua - Clean URLs navigation
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

-- Chat page for approved users
local function handle_chat_page()
    local username, user_data = is_who.require_approved()
    
    local is_admin = user_data.is_admin == "true"
    local admin_link = is_admin and '<a class="nav-link" href="/admin"><i class="bi bi-gear"></i> Admin</a>' or ""
    
    local nav_html = string.format([[
<nav class="navbar navbar-expand-lg navbar-dark">
    <div class="container-fluid">
        <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
        <div class="navbar-nav ms-auto">
            %s
            <a class="nav-link" href="/dashboard"><i class="bi bi-speedometer2"></i> Dashboard</a>
            <span class="navbar-text me-3">%s</span>
            <button class="btn btn-outline-light btn-sm" onclick="DevstralCommon.logout()"><i class="bi bi-box-arrow-right"></i> Logout</button>
        </div>
    </div>
</nav>
]], admin_link, username)

    template.render_template("/usr/local/openresty/nginx/html/approved_chat.html", {
        nav = nav_html,
        username = username,
        model_name = "Devstral AI"
    })
end

-- Dashboard page for approved users
local function handle_dashboard_page()
    local username = is_who.require_approved()
    
    local nav_html = string.format([[
<nav class="navbar navbar-expand-lg navbar-dark">
    <div class="container-fluid">
        <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
        <div class="navbar-nav ms-auto">
            <a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Chat</a>
            <span class="navbar-text me-3">%s</span>
            <button class="btn btn-outline-light btn-sm" onclick="DevstralCommon.logout()"><i class="bi bi-box-arrow-right"></i> Logout</button>
        </div>
    </div>
</nav>
]], username)

    template.render_template("/usr/local/openresty/nginx/html/approved_dash.html", {
        nav = nav_html,
        username = username
    })
end

-- Chat streaming with SSE session management
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

    -- Check rate limits
    local rate_ok, rate_message = server.check_rate_limit(username)
    if not rate_ok then
        send_json(429, { error = rate_message })
    end

    -- Set streaming headers
    ngx.header.content_type = "text/plain"
    ngx.header.cache_control = "no-cache"
    ngx.header.connection = "keep-alive"
    ngx.header["X-Chat-Storage"] = "redis"
    ngx.header["X-SSE-Session-ID"] = session_id

    local messages = {}
    
    -- Include chat history if requested
    if include_history then
        local history = server.get_chat_history(username, 10)
        for _, msg in ipairs(history) do
            table.insert(messages, { role = msg.role, content = msg.content })
        end
    end
    
    table.insert(messages, { role = "user", content = message })

    -- Save user message to Redis
    server.save_message(username, "user", message)

    ngx.log(ngx.INFO, "Starting chat stream for " .. username .. " (session: " .. session_id .. ")")

    local accumulated = ""
    local chunk_count = 0
    local final_response, err = server.call_ollama_streaming(messages, options, function(chunk)
        accumulated = chunk.accumulated
        chunk_count = chunk_count + 1
        
        -- Update session activity
        server.update_sse_activity(session_id)
        
        -- Send chunk
        send_sse_chunk({ 
            content = chunk.content, 
            done = chunk.done,
            chunk_id = chunk_count,
            storage_type = "redis"
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
    
    -- Cleanup handled by log_by_lua_block in nginx.conf
    ngx.exit(200)
end

-- Get chat history
local function handle_chat_history()
    local username = is_who.require_approved()
    
    local limit = tonumber(ngx.var.arg_limit) or 20
    local history = server.get_chat_history(username, limit)
    
    send_json(200, {
        success = true,
        messages = history,
        count = #history,
        storage_type = "redis"
    })
end

-- Clear chat history
local function handle_clear_chat()
    local username = is_who.require_approved()
    
    server.clear_chat_history(username)
    
    send_json(200, {
        success = true,
        message = "Chat history cleared",
        storage_type = "redis"
    })
end

-- Route handler
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