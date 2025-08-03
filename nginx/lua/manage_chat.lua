-- =============================================================================
-- nginx/lua/manage_chat.lua - COMPLETE CHAT HANDLERS (NO EXTERNAL DEPENDENCIES)
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- Configuration
local MAX_CHAT_HISTORY = 100
local CHAT_RETENTION_DAYS = 30

-- =============================================
-- REDIS KEY HELPERS
-- =============================================

local function get_chat_key(username)
    return "chat_history:" .. username
end

local function get_chat_meta_key(username)
    return "chat_meta:" .. username
end

-- =============================================
-- MESSAGE STRUCTURE
-- =============================================

local function create_message(role, content, metadata)
    return {
        id = tostring(ngx.time() * 1000 + math.random(1000)),
        role = role,
        content = content,
        timestamp = ngx.time(),
        iso_timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        metadata = metadata or {}
    }
end

-- =============================================
-- CORE CHAT FUNCTIONS
-- =============================================

function M.save_message(username, role, content, metadata)
    if not username or not role or not content then
        return false, "Missing parameters"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local chat_key = get_chat_key(username)
    local meta_key = get_chat_meta_key(username)
    
    local message = create_message(role, content, metadata)
    local message_json = cjson.encode(message)
    
    red:lpush(chat_key, message_json)
    red:ltrim(chat_key, 0, MAX_CHAT_HISTORY - 1)
    
    local meta = {
        last_message_time = ngx.time(),
        total_messages = red:llen(chat_key),
        last_role = role
    }
    red:hmset(meta_key, 
        "last_message_time", meta.last_message_time,
        "total_messages", meta.total_messages,
        "last_role", meta.last_role
    )
    
    local expiry = CHAT_RETENTION_DAYS * 24 * 3600
    red:expire(chat_key, expiry)
    red:expire(meta_key, expiry)
    
    red:close()
    return true, message.id
end

function M.load_history(username, limit)
    if not username then
        return {}, "Missing username"
    end
    
    limit = limit or 50
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local chat_key = get_chat_key(username)
    local messages_json = red:lrange(chat_key, 0, limit - 1)
    red:close()
    
    if not messages_json or #messages_json == 0 then
        return {}, nil
    end
    
    local messages = {}
    for i = #messages_json, 1, -1 do
        local ok, message = pcall(cjson.decode, messages_json[i])
        if ok and message then
            table.insert(messages, message)
        end
    end
    
    return messages, nil
end

function M.clear_history(username)
    if not username then
        return false, "Missing username"
    end
    
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local chat_key = get_chat_key(username)
    local meta_key = get_chat_meta_key(username)
    
    local deleted_messages = red:llen(chat_key)
    red:del(chat_key)
    red:del(meta_key)
    
    red:close()
    return true, deleted_messages
end

function M.search_history(username, query, limit)
    if not username or not query then
        return {}, "Missing parameters"
    end
    
    limit = limit or 20
    local messages, err = M.load_history(username, 200)
    if err then
        return {}, err
    end
    
    local results = {}
    local query_lower = string.lower(query)
    
    for _, msg in ipairs(messages) do
        if string.find(string.lower(msg.content), query_lower, 1, true) then
            table.insert(results, msg)
            if #results >= limit then
                break
            end
        end
    end
    
    return results, nil
end

function M.get_stats(username)
    if not username then
        return {}, "Missing username"
    end
    
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local chat_key = get_chat_key(username)
    local meta_key = get_chat_meta_key(username)
    
    local message_count = red:llen(chat_key)
    local meta_data = red:hmget(meta_key, "last_message_time", "last_role")
    
    red:close()
    
    local stats = {
        message_count = message_count,
        last_message_time = meta_data[1] and tonumber(meta_data[1]) or nil,
        last_role = meta_data[2] or nil,
        chat_exists = message_count > 0
    }
    
    return stats, nil
end

function M.export_history(username, format)
    format = format or "json"
    
    local messages, err = M.load_history(username, MAX_CHAT_HISTORY)
    if err then
        return nil, err
    end
    
    if format == "json" then
        local export_data = {
            username = username,
            exported_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            message_count = #messages,
            messages = messages
        }
        return cjson.encode(export_data), "application/json"
        
    elseif format == "txt" then
        local lines = {
            "Chat History Export",
            "Username: " .. username,
            "Exported: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
            "Messages: " .. #messages,
            string.rep("=", 50),
            ""
        }
        
        for _, msg in ipairs(messages) do
            table.insert(lines, "[" .. msg.iso_timestamp .. "] " .. string.upper(msg.role) .. ":")
            table.insert(lines, msg.content)
            table.insert(lines, "")
        end
        
        return table.concat(lines, "\n"), "text/plain"
    end
    
    return nil, "Unsupported format"
end

-- =============================================
-- CHAT API HANDLERS - NO AUTH CHECKS (DONE IN ROUTER)
-- =============================================

function M.handle_history(user_type, username, user_data)
    -- Access control based on user type
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat history not available for " .. user_type
        }))
        return
    end
    
    local limit = tonumber(ngx.var.arg_limit) or 50
    local messages, err = M.load_history(username, limit)
    
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
        messages = messages,
        user_type = user_type,
        storage_type = "redis",
        message_count = #messages
    }))
end

function M.handle_clear(user_type, username, user_data)
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat clear not available for " .. user_type
        }))
        return
    end
    
    local success, deleted_count = M.clear_history(username)
    
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
        message = "Chat history cleared",
        deleted_messages = deleted_count
    }))
end

function M.handle_export(user_type, username, user_data)
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat export not available for " .. user_type
        }))
        return
    end
    
    local format = ngx.var.arg_format or "json"
    local export_data, content_type = M.export_history(username, format)
    
    if not export_data then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to export chat history: " .. tostring(content_type)
        }))
        return
    end
    
    local filename = user_type:gsub("is_", "") .. "-chat-" .. username .. "-" .. os.date("%Y%m%d") .. "." .. format
    
    ngx.status = 200
    ngx.header.content_type = content_type
    ngx.header["Content-Disposition"] = 'attachment; filename="' .. filename .. '"'
    ngx.say(export_data)
end

function M.handle_search(user_type, username, user_data)
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat search not available for " .. user_type
        }))
        return
    end
    
    local query = ngx.var.arg_q or ngx.var.arg_query
    if not query or query == "" then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Search query required",
            message = "Use ?q=your_search_term parameter"
        }))
        return
    end
    
    local results, err = M.search_history(username, query)
    
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
        results = results,
        result_count = #results,
        user_type = user_type
    }))
end

function M.handle_stats(user_type, username, user_data)
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat stats only available for admin and approved users"
        }))
        return
    end
    
    local stats, err = M.get_stats(username)
    
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to get stats: " .. err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        stats = stats,
        user_type = user_type
    }))
end

function M.handle_stream(user_type, username, user_data)
    if user_type ~= "is_admin" and user_type ~= "is_approved" and user_type ~= "is_guest" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat streaming not available for " .. user_type
        }))
        return
    end
    
    local stream_ollama = require "manage_stream_ollama"
    
    -- Set different limits based on user type
    local max_tokens = 2048  -- Default for guests
    if user_type == "is_admin" then
        max_tokens = tonumber(os.getenv("MODEL_NUM_PREDICT")) or 4096
    elseif user_type == "is_approved" then
        max_tokens = 3072
    end
    
    local stream_context = {
        user_type = user_type,
        username = username,
        user_data = user_data,
        include_history = (user_type == "is_admin" or user_type == "is_approved"),
        history_limit = (user_type == "is_admin" and 100) or (user_type == "is_approved" and 50) or 0,
        default_options = {
            model = os.getenv("MODEL_NAME") or "devstral",
            temperature = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.7,
            max_tokens = max_tokens
        },
        -- Save messages to Redis for admin and approved users only
        on_user_message = function(message)
            if user_type == "is_admin" or user_type == "is_approved" then
                M.save_message(username, "user", message)
            end
        end,
        on_assistant_message = function(message)
            if user_type == "is_admin" or user_type == "is_approved" then
                M.save_message(username, "assistant", message)
            end
        end
    }
    
    return stream_ollama.handle_chat_stream_common(stream_context)
end

return M