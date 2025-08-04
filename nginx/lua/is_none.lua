-- =============================================================================
-- nginx/lua/is_none.lua - COMPLETE SMART SESSION MANAGEMENT FOR UNAUTHENTICATED USERS
-- =============================================================================

local cjson = require "cjson"

local M = {}

-- Helper function to send JSON response and exit
local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- SIMPLIFIED GUEST SESSION CREATION WITH COLLISION DETECTION
-- =============================================

function M.handle_create_session()
    ngx.log(ngx.INFO, "🎮 is_none: Handling guest session creation request")
    
    -- Delegate directly to is_guest.lua which now handles collision detection
    local success, result = pcall(function()
        local is_guest = require "is_guest"
        return is_guest.handle_create_session()
    end)
    
    if not success then
        ngx.log(ngx.ERR, "❌ is_guest handler failed: " .. tostring(result))
        ngx.log(ngx.ERR, "❌ Stack trace: " .. debug.traceback())
        
        send_json(500, {
            success = false,
            error = "Guest session creation failed",
            message = "Internal error in guest session handler",
            debug_info = {
                error_type = "lua_runtime_error",
                handler = "is_guest.handle_create_session",
                suggestion = "Please try again or contact support if the problem persists"
            }
        })
    end
    
    -- If we get here, is_guest should have sent its own response and exited
    ngx.log(ngx.INFO, "✅ is_guest handler completed successfully")
end

-- =============================================
-- DEBUG SESSION STATUS (OPTIONAL)
-- =============================================

function M.get_session_debug_info()
    local auth = require "manage_auth"
    
    local red = auth.connect_redis()
    if not red then
        return {
            success = false,
            error = "Redis connection failed"
        }
    end
    
    local current_time = ngx.time()
    local user_keys = red:keys("username:*")
    local sessions = {}
    
    for _, key in ipairs(user_keys) do
        local user_data = red:hgetall(key)
        if user_data and #user_data > 0 then
            local session = {}
            for i = 1, #user_data, 2 do
                local field = user_data[i]
                local value = user_data[i + 1]
                if value == ngx.null then
                    value = nil
                end
                session[field] = value
            end
            
            -- Add computed fields for debugging
            if session.last_activity then
                session.seconds_since_activity = current_time - tonumber(session.last_activity)
                session.is_recently_active = (current_time - tonumber(session.last_activity)) <= 60
            end
            
            if session.user_type == "is_guest" then
                session.session_age = current_time - tonumber(session.last_activity or 0)
                session.is_expired = session.session_age > 3600  -- 1 hour
                session.should_be_kicked = session.session_age > 60 or session.is_expired
            end
            
            session.redis_key = key
            table.insert(sessions, session)
        end
    end
    
    red:close()
    
    -- Analyze session state for guest creation eligibility
    local guest_sessions = {}
    local blocking_sessions = {}
    local can_create_guest = true
    local denial_reason = nil
    
    for _, session in ipairs(sessions) do
        if session.is_active == "true" then
            if session.user_type == "is_guest" then
                table.insert(guest_sessions, session)
                if session.is_recently_active then
                    can_create_guest = false
                    denial_reason = "Another guest is recently active"
                end
            elseif session.user_type == "is_admin" or session.user_type == "is_approved" then
                if session.is_recently_active then
                    table.insert(blocking_sessions, session)
                    can_create_guest = false
                    denial_reason = "High priority user is active"
                end
            end
        end
    end
    
    return {
        success = true,
        current_time = current_time,
        total_sessions = #sessions,
        guest_sessions = #guest_sessions,
        blocking_sessions = #blocking_sessions,
        can_create_guest = can_create_guest,
        denial_reason = denial_reason,
        sessions = sessions,
        analysis = {
            active_guest_sessions = guest_sessions,
            blocking_high_priority = blocking_sessions,
            recommendation = can_create_guest and "Guest creation allowed" or denial_reason
        },
        thresholds = {
            inactivity_kick_seconds = 60,
            guest_session_timeout_seconds = 3600
        }
    }
end

-- =============================================
-- API HANDLER FOR is_none USERS
-- =============================================

function M.handle_api(uri, method)
    ngx.log(ngx.INFO, "🎮 is_none.handle_api: " .. method .. " " .. uri)
    
    -- Wrap in error handling
    local success, result = pcall(function()
        if uri == "/api/guest/create-session" and method == "POST" then
            ngx.log(ngx.INFO, "✅ Routing to handle_create_session")
            return M.handle_create_session()
            
        elseif uri == "/api/guest/session-status" and method == "GET" then
            ngx.log(ngx.INFO, "✅ Routing to session debug info")
            local debug_info = M.get_session_debug_info()
            send_json(200, debug_info)
            
        else
            ngx.log(ngx.WARN, "❌ Unknown is_none API endpoint: " .. method .. " " .. uri)
            send_json(404, {
                success = false,
                error = "is_none API endpoint not found",
                requested = method .. " " .. uri,
                available_endpoints = {
                    "POST /api/guest/create-session - Create guest session with collision detection",
                    "GET /api/guest/session-status - Get session debug information"
                },
                user_type = "is_none",
                note = "This API is only available for unauthenticated users"
            })
        end
    end)
    
    if not success then
        ngx.log(ngx.ERR, "❌ is_none.handle_api error: " .. tostring(result))
        ngx.log(ngx.ERR, "❌ Stack trace: " .. debug.traceback())
        
        send_json(500, {
            success = false,
            error = "is_none API handler error",
            message = tostring(result),
            debug_info = {
                uri = uri,
                method = method,
                error_type = "lua_runtime_error",
                handler = "is_none.handle_api"
            }
        })
    end
end

-- =============================================
-- PAGE HANDLING FOR is_none USERS (OPTIONAL)
-- =============================================

function M.handle_index_page()
    -- This could be used if you want special handling for is_none users on index page
    ngx.log(ngx.INFO, "🏠 is_none user accessing index page")
    
    -- You could add special logic here, like:
    -- - Show different content for unauthenticated users
    -- - Track anonymous user metrics
    -- - Display registration prompts
    
    -- For now, just log and continue with normal index handling
    return true
end

function M.get_user_capabilities()
    -- Return what an unauthenticated user can do
    return {
        can_view_public_pages = true,
        can_create_guest_session = true,
        can_register = true,
        can_login = true,
        cannot_access_chat_directly = true,
        cannot_access_dashboard = true,
        cannot_access_admin_features = true,
        guest_session_options = {
            duration_minutes = 60,
            max_messages = "unlimited_during_session",
            storage_type = "temporary",
            features = "basic_chat_only"
        }
    }
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return M