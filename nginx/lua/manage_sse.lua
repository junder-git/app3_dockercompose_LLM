-- =============================================================================
-- nginx/lua/manage_sse.lua - SSE (Server-Sent Events) session management
-- =============================================================================

local cjson = require "cjson"

-- Configuration
local MAX_SSE_SESSIONS = 3
local SESSION_TIMEOUT = 300

local M = {}

-- =============================================
-- PRIORITY MANAGEMENT
-- =============================================

-- Get priority level based on user type
local function get_user_priority(user_type)
    if user_type == "is_admin" then return 1 end
    if user_type == "is_approved" then return 2 end
    if user_type == "is_guest" then return 3 end
    return 4
end

-- =============================================
-- SESSION MANAGEMENT
-- =============================================

-- Clean up expired SSE sessions
local function cleanup_expired_sse_sessions()
    local current_time = ngx.time()
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local cleaned = 0
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local ok, session = pcall(cjson.decode, session_info)
                if ok and current_time - session.last_activity > SESSION_TIMEOUT then
                    ngx.shared.sse_sessions:delete(key)
                    cleaned = cleaned + 1
                end
            end
        end
    end
    
    return cleaned
end

-- Check if a user can start a new SSE session
function M.can_start_sse_session(user_type, username)
    if not user_type or not username then
        return false, "Missing parameters"
    end
    
    cleanup_expired_sse_sessions()
    
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local active_sessions = {}
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local ok, session = pcall(cjson.decode, session_info)
                if ok then
                    table.insert(active_sessions, session)
                    if session.username == username then
                        return false, "User already has active session"
                    end
                end
            end
        end
    end
    
    if #active_sessions < MAX_SSE_SESSIONS then
        return true, "Session allowed"
    end
    
    if user_type == "is_admin" then
        return true, "Admin session granted"
    end
    
    return false, "No available slots"
end

-- Start a new SSE session
function M.start_sse_session(user_type, username)
    local can_start, message = M.can_start_sse_session(user_type, username)
    if not can_start then
        return false, message
    end
    
    local session_id = username .. "_sse_" .. ngx.time() .. "_" .. math.random(1000, 9999)
    local session = {
        session_id = session_id,
        username = username,
        user_type = user_type,
        priority = get_user_priority(user_type),
        created_at = ngx.time(),
        last_activity = ngx.time(),
        remote_addr = ngx.var.remote_addr or "unknown"
    }
    
    ngx.shared.sse_sessions:set("sse:" .. session_id, cjson.encode(session), SESSION_TIMEOUT + 60)
    
    return true, session_id
end

-- Update activity timestamp for an SSE session
function M.update_sse_activity(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    local session_info = ngx.shared.sse_sessions:get(session_key)
    
    if not session_info then
        return false
    end
    
    local ok, session = pcall(cjson.decode, session_info)
    if not ok then
        return false
    end
    
    session.last_activity = ngx.time()
    ngx.shared.sse_sessions:set(session_key, cjson.encode(session), SESSION_TIMEOUT + 60)
    return true
end

-- End an SSE session
function M.end_sse_session(session_id)
    if not session_id then return false end
    
    local session_key = "sse:" .. session_id
    ngx.shared.sse_sessions:delete(session_key)
    
    return true
end

-- Get statistics about active SSE sessions
function M.get_sse_stats()
    cleanup_expired_sse_sessions()
    local session_keys = ngx.shared.sse_sessions:get_keys(0)
    local active_sessions = 0
    
    local stats = {
        total_sessions = 0,
        max_sessions = MAX_SSE_SESSIONS,
        available_slots = 0,
        by_priority = {
            admin_sessions = 0,
            approved_sessions = 0,
            guest_sessions = 0
        }
    }
    
    for _, key in ipairs(session_keys) do
        if string.match(key, "^sse:") then
            local session_info = ngx.shared.sse_sessions:get(key)
            if session_info then
                local ok, session = pcall(cjson.decode, session_info)
                if ok then
                    active_sessions = active_sessions + 1
                    
                    if session.priority == 1 then
                        stats.by_priority.admin_sessions = stats.by_priority.admin_sessions + 1
                    elseif session.priority == 2 then
                        stats.by_priority.approved_sessions = stats.by_priority.approved_sessions + 1
                    elseif session.priority == 3 then
                        stats.by_priority.guest_sessions = stats.by_priority.guest_sessions + 1
                    end
                end
            end
        end
    end
    
    stats.total_sessions = active_sessions
    stats.available_slots = MAX_SSE_SESSIONS - active_sessions
    
    return stats
end

-- Helper function to send SSE events
function M.sse_send(data)
    ngx.print("data: " .. cjson.encode(data) .. "\n\n")
    ngx.flush(true)
end

-- Setup SSE response headers
function M.setup_sse_response()
    ngx.header.content_type = 'text/event-stream; charset=utf-8'
    ngx.header.cache_control = 'no-cache'
    ngx.header.connection = 'keep-alive'
    ngx.header.access_control_allow_origin = '*'
    ngx.header["X-Accel-Buffering"] = "no"
    ngx.flush(true)
end

return M