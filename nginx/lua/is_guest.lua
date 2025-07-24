-- =============================================================================
-- nginx/lua/is_guest.lua - FIXED: DISPLAY NAME AND LOGOUT FUNCTIONALITY
-- =============================================================================

local template = require "manage_template"
local cjson = require "cjson"

-- Import required modules
local auth = require "manage_auth"

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 600  -- 10 minutes
local GUEST_MESSAGE_LIMIT = 10

-- =============================================
-- HELPER FUNCTIONS - IMPORT FROM manage_auth
-- =============================================

-- Use shared Redis functions from manage_auth
local redis_to_lua = auth.redis_to_lua
local connect_redis = auth.connect_redis

-- FIXED: Get the current guest user's display name (not internal username)
local function get_guest_display_name()
    local user_type, username, user_data = auth.check()
    if user_type == "is_guest" and user_data then
        -- FIXED: Return display_username, not the internal username
        return user_data.display_username or "guest"
    end
    return "guest"
end

local function get_chat_features()
    return [[
        <div class="user-features guest-features">
            <div class="alert alert-warning">
                <h6><i class="bi bi-clock-history text-warning"></i> Guest Chat</h6>
                <p class="mb-1">10 messages • 10 minutes • localStorage only</p>
                <a href="/register" class="btn btn-warning btn-sm">Register for unlimited</a>
            </div>
        </div>
    ]]
end

local function get_guest_stats()
    local red = connect_redis()
    if not red then 
        return {
            active_sessions = 0,
            max_sessions = MAX_GUEST_SESSIONS,
            available_slots = MAX_GUEST_SESSIONS,
            challenges_active = 0
        }
    end

    local active_count = 0
    local challenges_active = 0
    
    -- Check guest_user_1 and guest_user_2
    for i = 1, MAX_GUEST_SESSIONS do
        local username = "guest_user_" .. i
        local session_key = "guest_active_session:" .. username
        local session_data = redis_to_lua(red:get(session_key))
        
        if session_data then
            local ok, session = pcall(cjson.decode, session_data)
            if ok and session.expires_at and ngx.time() < session.expires_at then
                active_count = active_count + 1
            else
                -- Clean expired session
                red:del(session_key)
            end
        end
        
        local challenge_key = "guest_challenge:" .. username
        local challenge_data = redis_to_lua(red:get(challenge_key))
        if challenge_data then
            local ok, challenge = pcall(cjson.decode, challenge_data)
            if ok and challenge.expires_at and ngx.time() < challenge.expires_at then
                challenges_active = challenges_active + 1
            else
                red:del(challenge_key)
            end
        end
    end
    
    red:close()
    
    return {
        active_sessions = active_count,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = MAX_GUEST_SESSIONS - active_count,
        challenges_active = challenges_active
    }
end

local function update_guest_message_count(user_data)
    if not user_data or not user_data.username then
        return false
    end
    
    local red = connect_redis()
    if not red then return false end
    
    user_data.message_count = (user_data.message_count or 0) + 1
    user_data.last_activity = ngx.time()
    
    local session_key = "guest_active_session:" .. user_data.username
    local user_session_key = "guest_session:" .. user_data.username
    
    red:set(session_key, cjson.encode(user_data))
    red:expire(session_key, GUEST_SESSION_DURATION)
    
    red:set(user_session_key, cjson.encode(user_data))
    red:expire(user_session_key, GUEST_SESSION_DURATION)
    
    red:close()
    return true
end
-- =============================================
-- API HANDLERS - USE SHARED MODULES
-- =============================================

local function handle_chat_api()
    -- Use shared chat API handler from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    return stream_ollama.handle_chat_api("is_guest")
end

-- FIXED: Guest logout handler using manage_auth
local function handle_guest_logout()
    -- FIXED: Use the shared logout handler from manage_auth
    local user_type, username, user_data = auth.check()
    
    if user_type == "is_guest" then
        ngx.log(ngx.INFO, "🔚 Guest logout requested for: " .. (user_data and user_data.display_username or username or "unknown"))
        
        -- Use the shared logout from manage_auth which handles guest cleanup
        auth.handle_logout()
        return
    else
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Not a guest session"
        }))
        return ngx.exit(403)
    end
end

-- Import guest session management from is_none
local function handle_guest_api()
    local is_none = require "is_none"
    return is_none.handle_guest_session_api()
end

-- =============================================
-- OLLAMA STREAMING HANDLER - USE SHARED MODULE
-- =============================================

local function handle_ollama_chat_stream()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_guest" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Guest session required"
        }))
        return ngx.exit(403)
    end
    
    -- Guest-specific pre-stream check function
    local function guest_pre_stream_check(message, request_data)
        local current_count = user_data.message_count or 0
        
        if current_count >= (user_data.max_messages or GUEST_MESSAGE_LIMIT) then
            return false, "Guest message limit reached (" .. (user_data.max_messages or GUEST_MESSAGE_LIMIT) .. " messages). Register for unlimited access."
        end
        
        if user_data.expires_at and ngx.time() >= user_data.expires_at then
            return false, "Guest session expired. Please start a new session."
        end
        
        update_guest_message_count(user_data)
        return true, nil
    end
    
    -- Use shared Ollama streaming from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    local stream_context = {
        user_type = "is_guest",
        username = username,
        user_data = user_data,
        include_history = false,
        history_limit = 0,
        pre_stream_check = guest_pre_stream_check,
        default_options = {
            model = os.getenv("MODEL_NAME") or "devstral",
            temperature = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.7,
            max_tokens = tonumber(os.getenv("MODEL_NUM_PREDICT")) or 1024
        }
    }
    
    return stream_ollama.handle_chat_stream_common(stream_context)
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return { 
    -- API handlers
    handle_guest_api = handle_guest_api,
    handle_chat_api = handle_chat_api,
    handle_ollama_chat_stream = handle_ollama_chat_stream,
    handle_guest_logout = handle_guest_logout,  -- FIXED: Export logout handler
    
    -- Session management functions
    get_guest_stats = get_guest_stats,
    update_guest_message_count = update_guest_message_count,
    
    -- Helper functions
    get_guest_display_name = get_guest_display_name,  -- FIXED: Export display name function
    get_chat_features = get_chat_features
}