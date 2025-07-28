-- =============================================================================
-- nginx/lua/is_approved.lua - APPROVED USER API HANDLERS WITH REDIS CHAT PERSISTENCE
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"
local chat_history = require "manage_chat_history"

local M = {}

-- =============================================
-- APPROVED USER CHAT API HANDLERS
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
    
    -- Get limit from query params
    local limit = tonumber(ngx.var.arg_limit) or 50  
    local messages, err = chat_history.load_history(username, limit)
    
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to load chat history: " .. err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        messages = chat_history.format_messages_for_api(messages),
        user_type = user_type,
        storage_type = "redis",
        message_count = #messages,
        note = "Approved user chat history loaded from Redis database"
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
    
    local success, deleted_count = chat_history.clear_history(username)
    
    if not success then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to clear chat history: " .. tostring(deleted_count)
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Approved user chat history cleared from Redis database",
        deleted_messages = deleted_count
    }))
end

local function handle_export_chat()
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
    
    local format = ngx.var.arg_format or "json"
    local export_data, content_type = chat_history.export_history(username, format)
    
    if not export_data then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to export chat history: " .. tostring(content_type)
        }))
        return
    end
    
    local filename = "chat-" .. username .. "-" .. os.date("%Y%m%d") .. "." .. format
    
    ngx.status = 200
    ngx.header.content_type = content_type
    ngx.header["Content-Disposition"] = 'attachment; filename="' .. filename .. '"'
    ngx.say(export_data)
end

local function handle_search_chat()
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
    
    local query = ngx.var.arg_q
    if not query or query == "" then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Search query required (use ?q=search_term)"
        }))
        return
    end
    
    local limit = tonumber(ngx.var.arg_limit) or 20
    local results, err = chat_history.search_history(username, query, limit)
    
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Search failed: " .. err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        query = query,
        results = chat_history.format_messages_for_api(results),
        result_count = #results,
        note = "Search results from Redis chat history"
    }))
end

local function handle_chat_stats()
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
    
    local stats, err = chat_history.get_chat_stats(username)
    
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to get chat stats: " .. err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        stats = stats,
        user_type = user_type,
        storage_type = "redis"
    }))
end

-- =============================================
-- APPROVED USER CHAT STREAMING WITH HISTORY SAVING
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
        },
        -- Custom message handler to save to Redis
        on_user_message = function(message)
            chat_history.save_message(username, "user", message)
        end,
        on_assistant_message = function(message)
            chat_history.save_message(username, "assistant", message)
        end
    }
    
    return stream_ollama.handle_chat_stream_common(stream_context)
end

-- =============================================
-- APPROVED USER CHAT API HANDLER
-- =============================================

function M.handle_chat_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/chat/history" and method == "GET" then
        handle_chat_history()
    elseif uri == "/api/chat/clear" and method == "POST" then
        handle_clear_chat()
    elseif uri == "/api/chat/export" and method == "GET" then
        handle_export_chat()
    elseif uri == "/api/chat/search" and method == "GET" then
        handle_search_chat()
    elseif uri == "/api/chat/stats" and method == "GET" then
        handle_chat_stats()
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