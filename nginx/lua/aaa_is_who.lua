-- =============================================================================
-- nginx/lua/aaa_is_who.lua - UPDATED WITH SESSION MANAGEMENT AND PRIORITY HANDLING
-- =============================================================================

local jwt = require "resty.jwt"
local auth = require "manage_auth"
local session_manager = require "manage_session"
local cjson = require "cjson"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

-- =============================================
-- ENHANCED USER TYPE DETERMINATION WITH SESSION VALIDATION
-- =============================================

function M.set_user()
    -- Clean up expired sessions first
    session_manager.cleanup_expired_sessions()
    
    local user_type, username, user_data = auth.check()
    if user_type == "is_admin" or user_type == "is_approved" or user_type == "is_pending" or user_type == "is_guest" then
       return user_type, username, user_data
    else
        username = "guest"
        user_type = "is_none"
    end
    return user_type, username, user_data
end

-- =============================================
-- ENHANCED AUTHENTICATION API WITH SESSION MANAGEMENT
-- =============================================

function M.handle_auth_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/auth/login" and method == "POST" then
        return auth.handle_login()
    elseif uri == "/api/auth/logout" and method == "POST" then
        return auth.handle_logout()
    elseif uri == "/api/auth/register" and method == "POST" then
        local manage_register = require "manage_register"
        return manage_register.handle_register()
    elseif uri == "/api/auth/status" and method == "GET" then
        return M.handle_auth_status()
    elseif uri == "/api/auth/session-status" and method == "GET" then
        return auth.handle_session_status()
    elseif uri == "/api/auth/force-logout" and method == "POST" then
        return auth.handle_force_logout()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Auth endpoint not found",
            available_endpoints = {
                "POST /api/auth/login",
                "POST /api/auth/logout", 
                "POST /api/auth/register",
                "GET /api/auth/status",
                "GET /api/auth/session-status",
                "POST /api/auth/force-logout"
            }
        }))
    end
end

-- =============================================
-- ENHANCED AUTH STATUS WITH SESSION INFO
-- =============================================

function M.handle_auth_status()
    local user_type, username, user_data = M.set_user()
    
    -- Get session stats
    local session_stats, session_err = session_manager.get_session_stats()
    if session_err then
        session_stats = { error = session_err }
    end
    
    local response = {
        authenticated = user_type ~= "is_none",
        user_type = user_type,
        username = username,
        session_stats = session_stats
    }
    
    -- Add session-specific info for authenticated users
    if user_type ~= "is_none" and session_stats.current_session then
        response.session_info = {
            expires_at = session_stats.current_session.expires_at,
            time_remaining = session_stats.current_session.time_remaining,
            last_activity = session_stats.current_session.last_activity
        }
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(response))
end

-- =============================================
-- ENHANCED GUEST API WITH SESSION AWARENESS
-- =============================================

function M.handle_guest_api(user_type, username, user_data)
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "🎮 Guest API: " .. method .. " " .. uri .. " (user: " .. user_type .. ")")
    
    if (uri == "/api/guest/create" or uri == "/api/guest/create-session") and method == "POST" then
        -- Check if guest sessions are allowed (no admin/approved users logged in)
        local active_session, session_err = session_manager.get_active_session()
        if active_session and (active_session.user_type == "admin" or active_session.user_type == "approved") then
            ngx.status = 409
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Guest sessions not allowed",
                message = string.format("%s '%s' is currently logged in", 
                    active_session.user_type, active_session.username),
                retry_after = active_session.expires_at - ngx.time()
            }))
            return
        end
        
        -- Only is_none users can create guest sessions
        if user_type ~= "is_none" then
            ngx.status = 400
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Already authenticated",
                current_user_type = user_type
            }))
            return
        end
        
        local manage_guest = require "manage_guest"
        return manage_guest.handle_create_session()
        
    elseif uri == "/api/guest/status" and method == "GET" then
        local session_stats, err = session_manager.get_session_stats()
        
        local guest_allowed = true
        local blocking_session = nil
        
        if session_stats and session_stats.current_session then
            local current = session_stats.current_session
            if current.user_type == "admin" or current.user_type == "approved" then
                guest_allowed = false
                blocking_session = current
            end
        end
        
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            guest_sessions_allowed = guest_allowed,
            blocking_session = blocking_session,
            session_stats = session_stats
        }))
        return
        
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Guest API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/guest/create-session",
                "GET /api/guest/status"
            }
        }))
    end
end

-- =============================================
-- ENHANCED CHAT API WITH SESSION VALIDATION
-- =============================================

function M.handle_chat_api(user_type, username, user_data)
    -- Additional session validation for chat access
    if user_type ~= "is_none" and user_type ~= "is_guest" then
        local session_valid, session_err = session_manager.validate_session(username, user_type:gsub("is_", ""))
        if not session_valid then
            ngx.status = 401
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Session invalid",
                message = session_err,
                action_required = "please_login"
            }))
            return ngx.exit(401)
        end
    end
    
    -- Auth check - only authenticated users can access chat API
    if user_type == "is_none" then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    end
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "🔄 Chat API: " .. method .. " " .. uri .. " (user: " .. user_type .. ")")
    
    -- Delegate to chat manager with pre-authenticated user info
    local manage_chat = require "manage_chat"
    
    if uri == "/api/chat/history" and method == "GET" then
        return manage_chat.handle_history(user_type, username, user_data)
    elseif uri == "/api/chat/clear" and method == "POST" then
        return manage_chat.handle_clear(user_type, username, user_data)
    elseif uri == "/api/chat/export" and method == "GET" then
        return manage_chat.handle_export(user_type, username, user_data)
    elseif uri == "/api/chat/search" and method == "GET" then
        return manage_chat.handle_search(user_type, username, user_data)
    elseif uri == "/api/chat/stats" and method == "GET" then
        return manage_chat.handle_stats(user_type, username, user_data)
    elseif uri == "/api/chat/stream" and method == "POST" then
        return manage_chat.handle_stream(user_type, username, user_data)
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Chat API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "GET /api/chat/history",
                "POST /api/chat/clear", 
                "GET /api/chat/export",
                "GET /api/chat/search",
                "GET /api/chat/stats",
                "POST /api/chat/stream"
            }
        }))
    end
end

-- =============================================
-- ENHANCED ADMIN API WITH SESSION VALIDATION
-- =============================================

function M.handle_admin_api(user_type, username, user_data)
    -- Admin-only access control with session validation
    if user_type ~= "is_admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Admin access required",
            user_type = user_type
        }))
        return ngx.exit(403)
    end
    
    -- Validate admin session
    local session_valid, session_err = session_manager.validate_session(username, "admin")
    if not session_valid then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Admin session invalid",
            message = session_err,
            action_required = "please_login"
        }))
        return ngx.exit(401)
    end
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    -- Delegate to admin manager
    local manage_admin = require "manage_admin"
    
    if uri == "/api/admin/users" and method == "GET" then
        return manage_admin.handle_get_all_users()
    elseif uri == "/api/admin/users/pending" and method == "GET" then
        return manage_admin.handle_get_pending_users()
    elseif uri == "/api/admin/users/approve" and method == "POST" then
        return manage_admin.handle_approve_user()
    elseif uri == "/api/admin/users/reject" and method == "POST" then
        return manage_admin.handle_reject_user()
    elseif uri == "/api/admin/stats" and method == "GET" then
        return manage_admin.handle_system_stats()
    elseif uri == "/api/admin/guests/clear" and method == "POST" then
        return manage_admin.handle_clear_guest_sessions()
    elseif uri == "/api/admin/session/force-logout" and method == "POST" then
        return auth.handle_force_logout()
    elseif uri == "/api/admin/session/status" and method == "GET" then
        return auth.handle_session_status()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Admin API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "GET /api/admin/users",
                "GET /api/admin/users/pending",
                "POST /api/admin/users/approve",
                "POST /api/admin/users/reject",
                "GET /api/admin/stats",
                "POST /api/admin/guests/clear",
                "POST /api/admin/session/force-logout",
                "GET /api/admin/session/status"
            }
        }))
    end
end

-- =============================================
-- MAIN ROUTING HANDLER - ENHANCED WITH SESSION MANAGEMENT
-- =============================================

function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_user()
    
    -- Handle API routes first
    if route_type == "chat_api" then
        return M.handle_chat_api(user_type, username, user_data)
    elseif route_type == "admin_api" then
        return M.handle_admin_api(user_type, username, user_data)
    elseif route_type == "auth_api" then
        return M.handle_auth_api()
    elseif route_type == "guest_api" then
        return M.handle_guest_api(user_type, username, user_data)
    end
    
    -- Handle page routes - delegate to page managers with access control
    if route_type == "index" then
        local manage_view_index = require "manage_view_index"
        return manage_view_index.handle(user_type, username, user_data)
        
    elseif route_type == "chat" then
        -- Enhanced access control for chat page with session validation
        if user_type == "is_none" then
            return ngx.redirect("/")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        
        -- Validate session for non-guest users
        if user_type ~= "is_guest" then
            local session_valid, session_err = session_manager.validate_session(username, user_type:gsub("is_", ""))
            if not session_valid then
                ngx.log(ngx.WARN, string.format("Chat access denied - invalid session for %s '%s': %s", 
                    user_type, username, session_err))
                return ngx.redirect("/?session_expired=1")
            end
        end
        
        local manage_view_chat = require "manage_view_chat"
        return manage_view_chat.handle(user_type, username, user_data)
        
    elseif route_type == "dash" then
        -- Enhanced access control for dashboard with session validation
        if user_type == "is_none" or user_type == "is_guest" or user_type == "is_pending" then
            return ngx.redirect("/")
        end
        
        -- Validate session
        local session_valid, session_err = session_manager.validate_session(username, user_type:gsub("is_", ""))
        if not session_valid then
            ngx.log(ngx.WARN, string.format("Dashboard access denied - invalid session for %s '%s': %s", 
                user_type, username, session_err))
            return ngx.redirect("/?session_expired=1")
        end
        
        local manage_view_dash = require "manage_view_dash"
        return manage_view_dash.handle(user_type, username, user_data)
        
    elseif route_type == "login" then
        -- Enhanced login page - show session info if blocked
        if user_type == "is_admin" or user_type == "is_approved" then
            return ngx.redirect("/chat")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        
        -- Check if login is currently blocked by active session
        local active_session, session_err = session_manager.get_active_session()
        local login_blocked = false
        local blocking_info = nil
        
        if active_session then
            login_blocked = true
            blocking_info = {
                username = active_session.username,
                user_type = active_session.user_type,
                expires_at = active_session.expires_at,
                time_remaining = active_session.expires_at - ngx.time()
            }
        end
        
        local manage_view_auth = require "manage_view_auth"
        return manage_view_auth.handle_login(user_type, username, user_data, login_blocked, blocking_info)
        
    elseif route_type == "register" then
        -- Redirect authenticated users
        if user_type == "is_admin" or user_type == "is_approved" then
            return ngx.redirect("/chat")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local manage_view_auth = require "manage_view_auth"
        return manage_view_auth.handle_register(user_type, username, user_data)
        
    else
        -- Unknown route
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Route not found",
            route = route_type,
            user_type = user_type
        }))
    end
end

-- =============================================
-- ERROR HANDLERS (UNCHANGED)
-- =============================================

function M.handle_404()
    local manage_view_error = require "manage_view_error"
    return manage_view_error.handle_404()
end

function M.handle_429()
    local manage_view_error = require "manage_view_error"
    return manage_view_error.handle_429()
end

function M.handle_50x()
    local manage_view_error = require "manage_view_error"
    return manage_view_error.handle_50x()
end

return M