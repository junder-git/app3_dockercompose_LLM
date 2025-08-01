-- =============================================================================
-- nginx/lua/is_admin.lua - ADMIN API HANDLERS WITH REDIS CHAT PERSISTENCE
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"
local chat_history = require "manage_chat_history"

local M = {}

-- =============================================
-- ADMIN CHAT API HANDLERS
-- =============================================

function M.handle_chat_history()  
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
        note = "Admin chat history loaded from Redis database"
    }))
end

function M.handle_clear_chat()   
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
        message = "Admin chat history cleared from Redis database",
        deleted_messages = deleted_count
    }))
end

function M.handle_export_chat()    
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
    
    local filename = "admin-chat-" .. username .. "-" .. os.date("%Y%m%d") .. "." .. format
    
    ngx.status = 200
    ngx.header.content_type = content_type
    ngx.header["Content-Disposition"] = 'attachment; filename="' .. filename .. '"'
    ngx.say(export_data)
end

-- =============================================
-- ADMIN CHAT STREAMING WITH HISTORY SAVING
-- =============================================

function M.handle_ollama_chat_stream()    
    -- Use shared Ollama streaming from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    local stream_context = {
        user_type = "is_admin",
        username = username,
        user_data = user_data,
        include_history = true,
        history_limit = 100,
        default_options = {
            model = os.getenv("MODEL_NAME") or "devstral",
            temperature = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.7,
            max_tokens = tonumber(os.getenv("MODEL_NUM_PREDICT")) or 4096  -- Highest limit for admins
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

return M