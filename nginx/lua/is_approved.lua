-- =============================================================================
-- nginx/lua/is_approved.lua - APPROVED USER FUNCTIONALITY
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- APPROVED USER SPECIFIC FUNCTIONS
-- =============================================

-- Get approved user profile/stats
function M.get_user_profile(username)
    local user_data = auth.get_user(username)
    if not user_data or user_data.user_type ~= "approved" then
        return nil, "User not found or not approved"
    end
    
    return {
        username = user_data.username,
        user_type = user_data.user_type,
        created_at = user_data.created_at,
        last_activity = user_data.last_activity,
        features = {
            unlimited_messages = true,
            redis_storage = true,
            full_features = true,
            export_history = true,
            priority_level = 2
        }
    }, nil
end

-- Check approved user limits (approved users have no limits)
function M.check_usage_limits(username)
    return {
        can_chat = true,
        messages_remaining = -1, -- unlimited
        features_available = {
            "chat_streaming",
            "history_export", 
            "history_search",
            "full_context",
            "premium_models"
        },
        restrictions = {}
    }, nil
end

-- =============================================
-- APPROVED USER API HANDLERS
-- =============================================

function M.handle_profile_api(username)
    local profile, err = M.get_user_profile(username)
    if err then
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        profile = profile
    }))
end

function M.handle_usage_stats(username)
    local limits, err = M.check_usage_limits(username)
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        usage = limits,
        user_type = "approved"
    }))
end

-- Export user's personal data (GDPR compliance)
function M.handle_data_export(username)
    local user_data = auth.get_user(username)
    if not user_data or user_data.user_type ~= "approved" then
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "User not found"
        }))
        return
    end
    
    -- Get chat stats
    local manage_chat = require "manage_chat"
    local chat_stats, _ = manage_chat.get_stats(username)
    
    local export_data = {
        user_info = {
            username = user_data.username,
            user_type = user_data.user_type,
            created_at = user_data.created_at,
            last_activity = user_data.last_activity
        },
        chat_statistics = chat_stats,
        export_metadata = {
            exported_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            export_type = "user_data",
            data_retention_policy = "30_days_chat_history"
        }
    }
    
    local filename = "approved-user-data-" .. username .. "-" .. os.date("%Y%m%d") .. ".json"
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.header["Content-Disposition"] = 'attachment; filename="' .. filename .. '"'
    ngx.say(cjson.encode(export_data))
end

-- =============================================
-- APPROVED USER PREFERENCES
-- =============================================

function M.get_user_preferences(username)
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local prefs_key = "user_prefs:" .. username
    local prefs_data = red:hgetall(prefs_key)
    red:close()
    
    if not prefs_data or #prefs_data == 0 then
        -- Return default preferences
        return {
            theme = "dark",
            chat_model = "default",
            max_context = 4096,
            temperature = 0.7,
            notifications = true,
            auto_save = true
        }, nil
    end
    
    -- Convert Redis hash to Lua table
    local prefs = {}
    for i = 1, #prefs_data, 2 do
        local key = prefs_data[i]
        local value = auth.redis_to_lua(prefs_data[i + 1])
        prefs[key] = value
    end
    
    return prefs, nil
end

function M.update_user_preferences(username, new_prefs)
    local red = auth.connect_redis()
    if not red then
        return false, "Redis connection failed"
    end
    
    local prefs_key = "user_prefs:" .. username
    
    -- Validate and set preferences
    local valid_prefs = {
        theme = new_prefs.theme or "dark",
        chat_model = new_prefs.chat_model or "default", 
        max_context = tonumber(new_prefs.max_context) or 4096,
        temperature = tonumber(new_prefs.temperature) or 0.7,
        notifications = new_prefs.notifications == "true" or new_prefs.notifications == true,
        auto_save = new_prefs.auto_save == "true" or new_prefs.auto_save == true
    }
    
    -- Save to Redis
    for key, value in pairs(valid_prefs) do
        red:hset(prefs_key, key, tostring(value))
    end
    
    red:expire(prefs_key, 86400 * 90) -- 90 day expiry
    red:close()
    
    return true, valid_prefs
end

function M.handle_preferences_api(username, method)
    if method == "GET" then
        local prefs, err = M.get_user_preferences(username)
        if err then
            ngx.status = 500
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                error = err
            }))
            return
        end
        
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            preferences = prefs
        }))
        
    elseif method == "POST" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        if not body then
            ngx.status = 400
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({error = "No request body"}))
            return
        end
        
        local ok, data = pcall(cjson.decode, body)
        if not ok then
            ngx.status = 400
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({error = "Invalid JSON"}))
            return
        end
        
        local success, result = M.update_user_preferences(username, data)
        if not success then
            ngx.status = 500
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                error = result
            }))
            return
        end
        
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            message = "Preferences updated",
            preferences = result
        }))
    else
        ngx.status = 405
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Method not allowed",
            allowed_methods = {"GET", "POST"}
        }))
    end
end

-- =============================================
-- APPROVED USER CHAT FEATURES  
-- =============================================

function M.get_chat_config(username)
    local prefs, _ = M.get_user_preferences(username)
    
    return {
        max_tokens = tonumber(prefs.max_context) or 4096,
        temperature = tonumber(prefs.temperature) or 0.7,
        model = prefs.chat_model or "default",
        features = {
            history_enabled = true,
            search_enabled = true,
            export_enabled = true,
            streaming_enabled = true,
            code_execution = false, -- Admin only
            file_upload = false     -- Admin only
        },
        limits = {
            messages_per_hour = -1, -- unlimited
            context_window = tonumber(prefs.max_context) or 4096,
            concurrent_sessions = 1
        }
    }
end

return M