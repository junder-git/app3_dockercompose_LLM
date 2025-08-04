-- =============================================================================
-- nginx/lua/is_none.lua - SMART SESSION MANAGEMENT WITH FORCE KICK FOR UNAUTHENTICATED USERS
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

-- Session timeout configurations
local GUEST_SESSION_TIMEOUT = 3600  -- 1 hour total
local INACTIVITY_KICK_THRESHOLD = 120  -- 2 minute of inactivity = force kick

local M = {}

-- Helper function to send JSON response and exit
local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- ENHANCED SESSION ANALYSIS WITH FORCE KICK LOGIC
-- =============================================

local function analyze_active_sessions()
    local red = auth.connect_redis()
    if not red then
        return {}, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    local user_keys = red:keys("username:*")
    local session_analysis = {
        active_sessions = {},
        kickable_sessions = {},
        blocking_sessions = {},
        total_active = 0
    }
    
    for _, key in ipairs(user_keys) do
        local is_active = red:hget(key, "is_active")
        local user_type = red:hget(key, "user_type")
        local username = red:hget(key, "username")
        local last_activity = tonumber(red:hget(key, "last_activity")) or 0
        local created_at_str = red:hget(key, "created_at")
        
        if is_active == "true" and username and user_type then
            local session_age = current_time - last_activity
            local session_info = {
                username = username,
                user_type = user_type,
                last_activity = last_activity,
                session_age = session_age,
                key = key,
                created_at = created_at_str
            }
            
            table.insert(session_analysis.active_sessions, session_info)
            session_analysis.total_active = session_analysis.total_active + 1
            
            -- Determine if session can be kicked based on user type and inactivity
            if user_type == "is_guest" then
                -- Guest sessions: kick if inactive for >1 minute OR expired (>1 hour)
                if session_age > INACTIVITY_KICK_THRESHOLD or session_age > GUEST_SESSION_TIMEOUT then
                    table.insert(session_analysis.kickable_sessions, session_info)
                    ngx.log(ngx.INFO, string.format("👢 Guest session %s is kickable (inactive: %ds)", username, session_age))
                else
                    table.insert(session_analysis.blocking_sessions, session_info)
                    ngx.log(ngx.INFO, string.format("🔒 Guest session %s is blocking (active: %ds ago)", username, session_age))
                end
            elseif user_type == "is_admin" or user_type == "is_approved" then
                -- Admin/Approved users: only kick if inactive for >1 minute
                if session_age > INACTIVITY_KICK_THRESHOLD then
                    table.insert(session_analysis.kickable_sessions, session_info)
                    ngx.log(ngx.INFO, string.format("👢 %s session %s is kickable (inactive: %ds)", user_type, username, session_age))
                else
                    table.insert(session_analysis.blocking_sessions, session_info)
                    ngx.log(ngx.INFO, string.format("🔒 %s session %s is blocking (active: %ds ago)", user_type, username, session_age))
                end
            else
                -- Unknown user types are considered blocking
                table.insert(session_analysis.blocking_sessions, session_info)
            end
        end
    end
    
    red:close()
    
    ngx.log(ngx.INFO, string.format("📊 Session analysis: %d total, %d kickable, %d blocking", 
        session_analysis.total_active, #session_analysis.kickable_sessions, #session_analysis.blocking_sessions))
    
    return session_analysis, nil
end

-- =============================================
-- FORCE KICK INACTIVE SESSIONS
-- =============================================

local function force_kick_sessions(sessions_to_kick)
    if not sessions_to_kick or #sessions_to_kick == 0 then
        return 0, nil
    end
    
    local red = auth.connect_redis()
    if not red then
        return 0, "Redis connection failed"
    end
    
    local kicked_count = 0
    local kicked_users = {}
    
    for _, session in ipairs(sessions_to_kick) do
        -- Set session as inactive
        red:hset(session.key, "is_active", "false")
        red:hset(session.key, "kicked_at", ngx.time())
        red:hset(session.key, "kick_reason", "inactivity")
        
        kicked_count = kicked_count + 1
        table.insert(kicked_users, session.username)
        
        ngx.log(ngx.INFO, string.format("👢 Force kicked %s session: %s (inactive for %ds)", 
            session.user_type, session.username, session.session_age))
    end
    
    red:close()
    
    return kicked_count, kicked_users
end

-- =============================================
-- SMART SESSION CHECK BEFORE GUEST CREATION
-- =============================================

local function can_create_guest_session()
    ngx.log(ngx.INFO, "🧠 is_none: Checking if guest session can be created")
    
    -- Analyze current session state
    local session_analysis, analysis_err = analyze_active_sessions()
    if analysis_err then
        return false, "Failed to analyze sessions: " .. analysis_err, nil
    end
    
    -- If no active sessions, allow creation
    if session_analysis.total_active == 0 then
        ngx.log(ngx.INFO, "✅ No active sessions - guest creation allowed")
        return true, "No active sessions", {
            action = "create",
            kicked_sessions = {},
            blocking_sessions = {}
        }
    end
    
    -- If there are blocking sessions (active within 1 minute), check priority
    if #session_analysis.blocking_sessions > 0 then
        -- Check if any blocking sessions are high priority (admin/approved recently active)
        local high_priority_blocking = {}
        for _, session in ipairs(session_analysis.blocking_sessions) do
            if session.user_type == "is_admin" or session.user_type == "is_approved" then
                table.insert(high_priority_blocking, session)
            end
        end
        
        if #high_priority_blocking > 0 then
            local blocking_session = high_priority_blocking[1]
            return false, string.format("High priority user '%s' (%s) is currently active (last seen %ds ago)", 
                blocking_session.username, 
                blocking_session.user_type:gsub("is_", ""), 
                blocking_session.session_age), {
                action = "denied",
                reason = "high_priority_active",
                blocking_sessions = high_priority_blocking,
                kicked_sessions = {}
            }
        end
        
        -- If only guest sessions are blocking, provide different message
        local guest_blocking = {}
        for _, session in ipairs(session_analysis.blocking_sessions) do
            if session.user_type == "is_guest" then
                table.insert(guest_blocking, session)
            end
        end
        
        if #guest_blocking > 0 then
            local blocking_session = guest_blocking[1]
            return false, string.format("Another guest user is currently active (last seen %ds ago). Please wait a moment.", 
                blocking_session.session_age), {
                action = "denied", 
                reason = "guest_recently_active",
                blocking_sessions = guest_blocking,
                kicked_sessions = {}
            }
        end
    end
    
    -- Force kick inactive sessions to make room
    if #session_analysis.kickable_sessions > 0 then
        local kicked_count, kicked_users = force_kick_sessions(session_analysis.kickable_sessions)
        
        if kicked_count > 0 then
            ngx.log(ngx.INFO, string.format("👢 Force kicked %d inactive sessions: %s", 
                kicked_count, table.concat(kicked_users or {}, ", ")))
            
            return true, string.format("Kicked %d inactive sessions", kicked_count), {
                action = "create_after_kick",
                kicked_sessions = session_analysis.kickable_sessions,
                blocked_sessions = {}
            }
        else
            return false, "Failed to kick inactive sessions", {
                action = "kick_failed",
                kicked_sessions = {},
                blocking_sessions = session_analysis.blocking_sessions
            }
        end
    end
    
    -- Should not reach here, but fallback
    return false, "Unable to create guest session - unknown session state", {
        action = "unknown_state",
        kicked_sessions = {},
        blocking_sessions = session_analysis.blocking_sessions
    }
end

-- =============================================
-- MAIN GUEST SESSION HANDLER (CALLS is_guest.lua)
-- =============================================

function M.handle_create_session()
    ngx.log(ngx.INFO, "🎮 is_none: Smart guest session creation requested")
    
    -- Check if guest session can be created (with force kick logic)
    local can_create, reason, session_info = can_create_guest_session()
    
    if not can_create then
        -- Determine appropriate HTTP status based on reason
        local status_code = 409  -- Conflict (default)
        local error_reason = "sessions_full"
        
        if session_info and session_info.reason then
            if session_info.reason == "high_priority_active" then
                status_code = 409
                error_reason = "high_priority_user_active"
            elseif session_info.reason == "guest_recently_active" then
                status_code = 429  -- Too Many Requests
                error_reason = "guest_recently_active"
            end
        end
        
        ngx.log(ngx.INFO, "❌ Guest session denied: " .. reason)
        
        send_json(status_code, {
            success = false,
            error = "Cannot create guest session",
            message = reason,
            reason = error_reason,
            session_info = {
                blocking_sessions = session_info and #session_info.blocking_sessions or 0,
                kicked_sessions = session_info and #session_info.kicked_sessions or 0,
                suggestion = "Please try again in a minute when current sessions become inactive"
            }
        })
    end
    
    -- Log session creation details if sessions were kicked
    if session_info and session_info.kicked_sessions and #session_info.kicked_sessions > 0 then
        local kicked_usernames = {}
        for _, session in ipairs(session_info.kicked_sessions) do
            table.insert(kicked_usernames, session.username)
        end
        ngx.log(ngx.INFO, "👢 Kicked inactive sessions before creating guest: " .. table.concat(kicked_usernames, ", "))
    end
    
    -- Session creation is allowed - delegate to is_guest.lua
    ngx.log(ngx.INFO, "✅ Session creation allowed - delegating to is_guest.lua")
    
    local is_guest = require "is_guest"
    return is_guest.handle_create_session()
end

-- =============================================
-- SESSION STATUS CHECK API (FOR DEBUGGING)
-- =============================================

function M.get_session_status()
    local session_analysis, err = analyze_active_sessions()
    if err then
        return {
            success = false,
            error = err
        }
    end
    
    return {
        success = true,
        total_active_sessions = session_analysis.total_active,
        kickable_sessions = #session_analysis.kickable_sessions,
        blocking_sessions = #session_analysis.blocking_sessions,
        can_create_guest = #session_analysis.blocking_sessions == 0,
        session_details = {
            active = session_analysis.active_sessions,
            kickable = session_analysis.kickable_sessions,
            blocking = session_analysis.blocking_sessions
        },
        thresholds = {
            inactivity_kick_seconds = INACTIVITY_KICK_THRESHOLD,
            guest_session_timeout_seconds = GUEST_SESSION_TIMEOUT
        }
    }
end

-- =============================================
-- API HANDLER FOR is_none USERS
-- =============================================

function M.handle_api(uri, method)
    if uri == "/api/guest/create-session" and method == "POST" then
        return M.handle_create_session()
    elseif uri == "/api/guest/session-status" and method == "GET" then
        local status = M.get_session_status()
        send_json(200, status)
    else
        send_json(404, {
            success = false,
            error = "is_none API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/guest/create-session - Create guest session with smart logic",
                "GET /api/guest/session-status - Check session status"
            }
        })
    end
end

return M