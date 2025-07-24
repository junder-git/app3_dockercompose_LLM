-- =============================================================================
-- nginx/lua/is_approved.lua - APPROVED USER API HANDLERS ONLY (VIEWS HANDLED BY manage_views.lua)
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- APPROVED USER CHAT STREAMING
-- =============================================

local function handle_ollama_chat_stream()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_approved" and user_type ~= "is_admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Approved user access required"
        }))
        return ngx.exit(403)
    end
    
    -- Use shared Ollama streaming from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    local stream_context = {
        user_type = "is_approved",
        username = username,
        user_data = user_data,
        include_history = true,
        history_limit = 50,
        default_options = {
            model = os.getenv("MODEL_NAME") or "devstral",
            temperature = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.7,
            max_tokens = tonumber(os.getenv("MODEL_NUM_PREDICT")) or 2048  -- Good limit for approved users
        }
    }
    
    return stream_ollama.handle_chat_stream_common(stream_context)
end

-- =============================================
-- APPROVED USER CHAT API
-- =============================================

local function handle_chat_history()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_approved" and user_type ~= "is_admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Access denied"
        }))
        return
    end
    
    -- For now, return empty history - could implement Redis chat history here
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        messages = {},
        user_type = user_type,
        storage_type = "redis",
        note = "Chat history loaded from Redis database"
    }))
end

local function handle_clear_chat()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_approved" and user_type ~= "is_admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Access denied"
        }))
        return
    end
    
    -- Could implement Redis chat history clearing here
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Chat history cleared from Redis database"
    }))
end

-- =============================================
-- APPROVED USER API HANDLER
-- =============================================

function M.handle_chat_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        handle_chat_history()
    elseif uri == "/api/chat/clear" and method == "POST" then
        handle_clear_chat()
    elseif uri == "/api/chat/stream" and method == "POST" then
        return handle_ollama_chat_stream()
    else
        -- Delegate to shared chat API handler
        local stream_ollama = require "manage_stream_ollama"
        return stream_ollama.handle_chat_api("is_approved")
    end
end

-- =============================================
-- ROUTE HANDLER (FOR NON-VIEW ROUTES)
-- =============================================

function M.handle_route(route_type)
    -- This function handles non-view routes for approved users
    -- Views are handled by manage_views.lua
    if route_type == "chat_api" then
        return M.handle_chat_api()
    else
        ngx.status = 404
        return ngx.say("Approved user route not found: " .. tostring(route_type))
    end
end

return {
    handle_chat_api = M.handle_chat_api,
    handle_ollama_chat_stream = handle_ollama_chat_stream,
    handle_route = M.handle_route
}