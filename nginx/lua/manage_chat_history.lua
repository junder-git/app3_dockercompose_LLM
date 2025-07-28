-- =============================================================================
-- nginx/lua/manage_chat_history.lua - REDIS CHAT PERSISTENCE SYSTEM
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- Configuration
local MAX_CHAT_HISTORY = 100  -- Maximum messages per user
local CHAT_RETENTION_DAYS = 30  -- How long to keep chat history

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
        role = role,  -- 'user' or 'assistant'
        content = content,
        timestamp = ngx.time(),
        iso_timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        metadata = metadata or {}
    }
end

-- =============================================
-- SAVE MESSAGE TO REDIS
-- =============================================

function M.save_message(username, role, content, metadata)
    if not username or not role or not content then
        ngx.log(ngx.WARN, "save_message: Missing required parameters")
        return false, "Missing parameters"
    end
    
    -- Only save for admin and approved users
    local user_type, _, user_data = auth.check()
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.log(ngx.INFO, "save_message: Skipping save for user type: " .. tostring(user_type))
        return true  -- Return success but don't save
    end
    
    local red = auth.connect_redis()
    if not red then
        ngx.log(ngx.ERR, "save_message: Redis connection failed")
        return false, "Redis connection failed"
    end
    
    local chat_key = get_chat_key(username)
    local meta_key = get_chat_meta_key(username)
    
    -- Create message object
    local message = create_message(role, content, metadata)
    local message_json = cjson.encode(message)
    
    -- Add to chat history list (newest first)
    red:lpush(chat_key, message_json)
    
    -- Trim to max history size
    red:ltrim(chat_key, 0, MAX_CHAT_HISTORY - 1)
    
    -- Update metadata
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
    
    -- Set expiration (optional - for cleanup)
    local expiry = CHAT_RETENTION_DAYS * 24 * 3600
    red:expire(chat_key, expiry)
    red:expire(meta_key, expiry)
    
    red:close()
    
    ngx.log(ngx.INFO, "save_message: Saved " .. role .. " message for " .. username .. " (" .. string.len(content) .. " chars)")
    return true, message.id
end

-- =============================================
-- LOAD CHAT HISTORY FROM REDIS
-- =============================================

function M.load_history(username, limit)
    if not username then
        return {}, "Missing username"
    end
    
    limit = limit or 50  -- Default to last 50 messages
    
    local red = auth.connect_redis()
    if not red then
        ngx.log(ngx.ERR, "load_history: Redis connection failed")
        return {}, "Redis connection failed"
    end
    
    local chat_key = get_chat_key(username)
    
    -- Get messages (newest first)
    local messages_json = red:lrange(chat_key, 0, limit - 1)
    red:close()
    
    if not messages_json or #messages_json == 0 then
        return {}, nil
    end
    
    local messages = {}
    for i = #messages_json, 1, -1 do  -- Reverse to get chronological order
        local ok, message = pcall(cjson.decode, messages_json[i])
        if ok and message then
            table.insert(messages, message)
        else
            ngx.log(ngx.WARN, "load_history: Failed to decode message: " .. tostring(messages_json[i]))
        end
    end
    
    ngx.log(ngx.INFO, "load_history: Loaded " .. #messages .. " messages for " .. username)
    return messages, nil
end

-- =============================================
-- CLEAR CHAT HISTORY
-- =============================================

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
    
    ngx.log(ngx.INFO, "clear_history: Cleared " .. deleted_messages .. " messages for " .. username)
    return true, deleted_messages
end

-- =============================================
-- GET CHAT STATISTICS
-- =============================================

function M.get_chat_stats(username)
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

-- =============================================
-- FORMAT MESSAGES FOR API RESPONSE
-- =============================================

function M.format_messages_for_api(messages)
    local formatted = {}
    
    for _, msg in ipairs(messages) do
        table.insert(formatted, {
            id = msg.id,
            role = msg.role,
            content = msg.content,
            timestamp = msg.timestamp,
            iso_timestamp = msg.iso_timestamp,
            metadata = msg.metadata or {}
        })
    end
    
    return formatted
end

-- =============================================
-- SEARCH CHAT HISTORY
-- =============================================

function M.search_history(username, query, limit)
    if not username or not query then
        return {}, "Missing parameters"
    end
    
    limit = limit or 20
    local messages, err = M.load_history(username, 200)  -- Search in last 200 messages
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

-- =============================================
-- EXPORT CHAT HISTORY
-- =============================================

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
            messages = M.format_messages_for_api(messages)
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
-- CLEANUP OLD CHAT HISTORIES
-- =============================================

function M.cleanup_old_histories()
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local cutoff_time = ngx.time() - (CHAT_RETENTION_DAYS * 24 * 3600)
    local cleaned = 0
    
    -- Find all chat meta keys
    local meta_keys = red:keys("chat_meta:*")
    
    for _, meta_key in ipairs(meta_keys) do
        local last_message_time = red:hget(meta_key, "last_message_time")
        if last_message_time and tonumber(last_message_time) < cutoff_time then
            local username = string.match(meta_key, "chat_meta:(.+)")
            if username then
                local chat_key = get_chat_key(username)
                red:del(chat_key)
                red:del(meta_key)
                cleaned = cleaned + 1
                ngx.log(ngx.INFO, "cleanup_old_histories: Deleted old chat for " .. username)
            end
        end
    end
    
    red:close()
    
    ngx.log(ngx.INFO, "cleanup_old_histories: Cleaned " .. cleaned .. " old chat histories")
    return true, cleaned
end

return M