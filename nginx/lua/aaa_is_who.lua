-- =============================================================================
-- nginx/lua/aaa_is_who.lua - FIXED - NO CIRCULAR DEPENDENCIES
-- =============================================================================

local jwt = require "resty.jwt"
local auth = require "manage_auth"
local cjson = require "cjson"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

-- =============================================
-- USER TYPE DETERMINATION WITH SESSION VALIDATION
-- =============================================

function M.set_user()
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
-- GUEST API WITH SESSION CHECKING
-- =============================================

function M.handle_guest_api(user_type, username, user_data)
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "🎮 Guest API: " .. method .. " " .. uri .. " (user: " .. user_type .. ")")
    
    if (uri == "/api/guest/create" or uri == "/api/guest/create-session") and method == "POST" then
        -- Check if guest sessions are allowed
        local current_session, _ = auth.get_current_session()
        if current_session and (current_session.user_type == "admin" or current_session.user_type == "approved") then
            ngx.status = 409
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Sessions are currently full",
                message = string.format("%s '%s' is logged in", 
                    current_session.user_type, current_session.username),
                reason = "sessions_full"
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
        
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Guest API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/guest/create-session"
            }
        }))
    end
end

-- =============================================
-- CHAT API WITH SESSION VALIDATION
-- =============================================

function M.handle_chat_api(user_type, username, user_data)
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
-- ADMIN API WITH SESSION VALIDATION
-- =============================================

function M.handle_admin_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    -- Handle session management API requests
    if uri == "/api/admin/session/status" and method == "GET" then
        return M.handle_session_status()
    elseif uri == "/api/admin/session/force-logout" and method == "POST" then
        return M.handle_force_logout()
    elseif uri == "/api/admin/session/all" and method == "GET" then
        return M.handle_all_sessions()
    elseif uri == "/api/admin/session/cleanup" and method == "POST" then
        return M.handle_cleanup_sessions()
    
    -- Handle other admin API requests
    elseif uri == "/api/admin/users" and method == "GET" then
        return M.handle_get_all_users()
    elseif uri == "/api/admin/users/pending" and method == "GET" then
        return M.handle_get_pending_users()
    elseif uri == "/api/admin/users/approve" and method == "POST" then
        return M.handle_approve_user()
    elseif uri == "/api/admin/users/reject" and method == "POST" then
        return M.handle_reject_user()
    elseif uri == "/api/admin/stats" and method == "GET" then
        return M.handle_system_stats()
    elseif uri == "/api/admin/guests/clear" and method == "POST" then
        return M.handle_clear_guest_sessions()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Admin API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "User Management:",
                "GET /api/admin/users",
                "GET /api/admin/users/pending",
                "POST /api/admin/users/approve",
                "POST /api/admin/users/reject",
                "System:",
                "GET /api/admin/stats",
                "POST /api/admin/guests/clear",
                "Session Management (Redis):",
                "GET /api/admin/session/status",
                "POST /api/admin/session/force-logout",
                "GET /api/admin/session/all",
                "POST /api/admin/session/cleanup"
            }
        }))
    end
end

-- =============================================
-- MAIN ROUTING HANDLER
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
        -- Access control for chat page
        if user_type == "is_none" then
            return ngx.redirect("/")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local manage_view_chat = require "manage_view_chat"
        return manage_view_chat.handle(user_type, username, user_data)
        
    elseif route_type == "dash" then
        -- Access control for dashboard
        if user_type == "is_none" or user_type == "is_guest" or user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local manage_view_dash = require "manage_view_dash"
        return manage_view_dash.handle(user_type, username, user_data)
        
    elseif route_type == "login" then
        -- Redirect authenticated users
        if user_type == "is_admin" or user_type == "is_approved" then
            return ngx.redirect("/chat")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local manage_view_auth = require "manage_view_auth"
        return manage_view_auth.handle_login(user_type, username, user_data)
        
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
-- ERROR HANDLERS
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