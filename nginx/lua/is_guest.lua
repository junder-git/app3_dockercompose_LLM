-- =============================================================================
-- nginx/lua/is_guest.lua - COMPLETE GUEST USER HANDLER WITH CHALLENGE SYSTEM
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- GUEST MESSAGE COUNT UPDATE WITH SLOT LOOKUP
-- =============================================

local function update_guest_message_count(user_data)
    if not user_data or not user_data.display_username then
        return false, "Not a guest user"
    end
    
    -- Get guest system to update message count using slot lookup
    local is_none = require "is_none"
    
    -- Find the slot by checking shared memory for this display name
    local slot_number = nil
    
    -- Check both slots to find which one has this display name
    for i = 1, 2 do
        local session = is_none.get_session(i)
        if session and session.display_name == user_data.display_username then
            slot_number = i
            break
        end
    end
    
    if not slot_number then
        return false, "Guest session not found in shared memory"
    end
    
    return is_none.update_message_count(slot_number, user_data.message_count)
end

-- =============================================
-- GUEST CHAT API HANDLERS
-- =============================================

local function handle_chat_history()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_guest" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Guest access required"
        }))
        return
    end
    
    -- Guests don't have persistent history - return empty
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        messages = {},
        storage_type = "localStorage",
        note = "Guest users use localStorage only - no server history",
        message_count = user_data.message_count or 0,
        max_messages = user_data.max_messages or 10
    }))
end

local function handle_clear_chat()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_guest" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Guest access required"
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        message = "Guest chat uses localStorage only - clear from browser"
    }))
end

-- =============================================
-- GUEST LOGOUT HANDLER WITH SLOT CLEANUP
-- =============================================

local function handle_guest_logout()
    local user_type, username, user_data = auth.check()
    
    if user_type == "is_guest" then
        ngx.log(ngx.INFO, "🔚 Guest logout requested for: " .. (username or "unknown"))
        
        -- Clean up guest session from shared memory
        if user_data and user_data.display_username then
            local is_none = require "is_none"
            
            -- Find and cleanup the slot
            for i = 1, 2 do
                local session = is_none.get_session(i)
                if session and session.display_name == user_data.display_username then
                    is_none.cleanup_session(i)
                    ngx.log(ngx.INFO, "🧹 Cleaned up guest slot " .. i .. " for " .. user_data.display_username)
                    break
                end
            end
        end
        
        -- Use the shared logout from manage_auth
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

-- =============================================
-- GUEST OLLAMA STREAMING HANDLER - FIXED
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
        local max_messages = user_data.max_messages or 10
        
        if current_count >= max_messages then
            return false, "Guest message limit reached (" .. max_messages .. " messages). Register for unlimited access."
        end
        
        if user_data.expires_at and ngx.time() >= user_data.expires_at then
            return false, "Guest session expired. Please start a new session."
        end
        
        -- Update message count in shared memory and JWT
        local success, new_count = update_guest_message_count(user_data)
        if not success then
            return false, "Failed to update message count: " .. (new_count or "unknown error")
        end
        
        return true, nil
    end
    
    -- Use shared Ollama streaming from manage_stream_ollama
    local stream_ollama = require "manage_stream_ollama"
    local stream_context = {
        user_type = "is_guest",
        username = username,
        user_data = user_data,
        include_history = false,  -- Guests don't have server history
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
-- GUEST CHAT API HANDLER
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
        return stream_ollama.handle_chat_api("is_guest")
    end
end

-- =============================================
-- GUEST HELPER FUNCTIONS
-- =============================================

local function get_guest_display_name()
    local user_type, username, user_data = auth.check()
    if user_type == "is_guest" and user_data then
        return user_data.display_username or "Guest User"
    end
    return "Guest User"
end

local function get_chat_features()
    local user_type, username, user_data = auth.check()
    local message_count = 0
    local max_messages = 10
    
    if user_data then
        message_count = user_data.message_count or 0
        max_messages = user_data.max_messages or 10
    end
    
    return string.format([[
        <div class="user-features guest-features">
            <div class="alert alert-warning">
                <h6><i class="bi bi-clock-history text-warning"></i> Guest Chat</h6>
                <p class="mb-1">%d/%d messages • Time limited • localStorage only</p>
                <div class="guest-actions">
                    <a href="/register" class="btn btn-warning btn-sm me-2">Register for unlimited</a>
                    <button class="btn btn-outline-light btn-sm" onclick="downloadGuestHistory()">Download History</button>
                </div>
            </div>
        </div>
    ]], message_count, max_messages)
end

local function get_guest_stats()
    local is_none = require "is_none"
    return is_none.get_guest_stats()
end

-- =============================================
-- ROUTE HANDLER (FOR NON-VIEW ROUTES)
-- =============================================

function M.handle_route(route_type)
    if route_type == "chat_api" then
        return M.handle_chat_api()
    elseif route_type == "guest_logout" then
        return handle_guest_logout()
    else
        ngx.status = 404
        return ngx.say("Guest route not found: " .. tostring(route_type))
    end
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return { 
    -- API handlers
    handle_chat_api = M.handle_chat_api,
    handle_ollama_chat_stream = handle_ollama_chat_stream,
    handle_guest_logout = handle_guest_logout,
    handle_route = M.handle_route,
    
    -- Session management functions
    get_guest_stats = get_guest_stats,
    update_guest_message_count = update_guest_message_count,
    
    -- Helper functions
    get_guest_display_name = get_guest_display_name,
    get_chat_features = get_chat_features
}