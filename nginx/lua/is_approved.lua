local function handle_chat_page()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_approved()
    local context = {
        page_title = "Chat",
        nav = is_who.render_nav("approved", username, nil),
        chat_features = is_who.get_chat_features("approved"),
        chat_placeholder = "Ask anything..."
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat_approved.html", context)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_approved()
    local context = {
        page_title = "Approved dashboard",
        nav = is_public.render_nav("approved", username, nil),
        dashboard_content = is_public.get_dashboard_content("approved", username)
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash_approved.html", context)
end

-- =============================================
-- APPROVED USER CHAT API HANDLERS
-- =============================================

local function handle_chat_api()
    local cjson = require "cjson"
    local server = require "server"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    -- Require approved access for chat API
    local is_who = require "is_who"
    local username = is_who.require_approved()
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        -- Get chat history
        local limit = tonumber(ngx.var.arg_limit) or 50
        local messages = server.get_chat_history(username, limit)
        
        send_json(200, {
            success = true,
            messages = messages,
            user_type = "approved",
            storage_type = "redis"
        })
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        -- Clear chat history
        local success = server.clear_chat_history(username)
        
        if success then
            send_json(200, { success = true, message = "Chat history cleared" })
        else
            send_json(500, { success = false, error = "Failed to clear chat history" })
        end
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        handle_chat_stream()
    else
        send_json(404, { 
            error = "Chat API endpoint not found",
            requested = method .. " " .. uri
        })
    end
end

-- =============================================================================
-- Add to is_approved.lua - APPROVED-SPECIFIC STREAMING
-- =============================================================================

local function handle_chat_stream()
    local server = require "server"
    local is_who = require "is_who"
    local cjson = require "cjson"
    
    -- Get approved user info
    local username = is_who.require_approved()
    
    -- Approved user rate limiting
    local function pre_stream_check(message, request_data)
        local rate_ok, rate_error = server.check_rate_limit(username, false, false)
        if not rate_ok then
            return false, rate_error
        end
        return true, nil
    end
    
    -- Get chat history for approved users
    local function get_history(limit)
        return server.get_chat_history(username, limit)
    end
    
    -- Save user message to Redis
    local function save_user_message(message)
        server.save_message(username, "user", message)
    end
    
    -- Save AI response to Redis
    local function save_ai_response(response)
        server.save_message(username, "assistant", response)
    end
    
    -- Approved stream context
    local stream_context = {
        user_type = "is_approved",
        username = username,
        
        -- Approved capabilities
        include_history = true,   -- Approved users get history
        history_limit = 15,       -- More history than guests
        get_history = get_history,
        save_user_message = save_user_message,
        save_ai_response = save_ai_response,
        
        -- Approved-specific checks
        pre_stream_check = pre_stream_check,
        
        -- Approved AI options
        default_options = {
            temperature = 0.7,
            max_tokens = 2048,      -- Higher limit for approved
            num_predict = 2048,
            num_ctx = 1024,         -- Larger context
            priority = 2            -- Higher priority than guests
        }
    }
    
    -- Call common streaming function
    server.handle_chat_stream_common(stream_context)
end

-- Update the existing handle_chat_api function:
local function handle_chat_api()
    local cjson = require "cjson"
    local server = require "server"
    
    local function send_json(status, tbl)
        ngx.status = status
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(tbl))
        ngx.exit(status)
    end
    
    -- Require approved access for chat API
    local is_who = require "is_who"
    local username = is_who.require_approved()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    if uri == "/api/chat/history" and method == "GET" then
        -- Get chat history
        local limit = tonumber(ngx.var.arg_limit) or 50
        local messages = server.get_chat_history(username, limit)
        send_json(200, {
            success = true,
            messages = messages,
            user_type = "approved",
            storage_type = "redis"
        })
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        -- Clear chat history
        local success = server.clear_chat_history(username)
        
        if success then
            send_json(200, { success = true, message = "Chat history cleared" })
        else
            send_json(500, { success = false, error = "Failed to clear chat history" })
        end
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        handle_chat_stream() -- Approved-specific implementation
        
    else
        send_json(404, { 
            error = "Chat API endpoint not found",
            requested = method .. " " .. uri
        })
    end
end

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page,
    handle_chat_api = handle_chat_api,
    handle_chat_stream = handle_chat_stream
}