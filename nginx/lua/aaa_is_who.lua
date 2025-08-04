-- =============================================================================
-- nginx/lua/aaa_is_who.lua - MAIN ROUTER MODULE - COMPLETE AND FIXED
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
    local user_type, username, user_data = auth.check_user_type()
    
    if user_type == "is_admin" or user_type == "is_approved" or user_type == "is_pending" or user_type == "is_guest" then
        -- Check if session is active for authenticated users
        if not auth.check_is_active(username, user_type) then
            username = "guest"
            user_type = "is_none"
            user_data = nil
        end
    else
        username = "guest"
        user_type = "is_none"
        user_data = nil
    end
    return user_type, username, user_data
end

-- =============================================================================
-- GUEST API HANDLER
-- =============================================================================

function M.handle_guest_api(user_type, username, user_data)
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "🎮 Guest API: " .. method .. " " .. uri .. " (user: " .. tostring(user_type) .. ")")
    
    -- Only is_none users can access guest API
    if user_type ~= "is_none" then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Already authenticated",
            current_user_type = user_type,
            message = "You are already logged in. Please logout first to start a guest session."
        }))
        return
    end
    
    -- Delegate to is_none.lua for smart session management
    local success, result = pcall(function()
        local is_none = require "is_none"
        return is_none.handle_api(uri, method)
    end)
    
    if not success then
        ngx.log(ngx.ERR, "❌ is_none API handler failed: " .. tostring(result))
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Internal server error",
            message = "Smart session management failed. Please try again."
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
-- AUTH API HANDLER
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
        local user_type, username, user_data = M.set_user()
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            user_type = user_type,
            username = username,
            authenticated = user_type ~= "is_none"
        }))
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Auth API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/auth/login",
                "POST /api/auth/logout",
                "POST /api/auth/register",
                "GET /api/auth/status"
            }
        }))
    end
end

-- =============================================
-- ADMIN API WITH SESSION VALIDATION
-- =============================================

function M.handle_admin_api()
    -- Check if user is admin
    local user_type, username, user_data = M.set_user()
    if user_type ~= "is_admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Admin access required",
            current_user_type = user_type
        }))
        return
    end
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    -- Handle session management API requests
    if uri == "/api/admin/session/status" and method == "GET" then
        return auth.handle_session_status()
    elseif uri == "/api/admin/session/force-logout" and method == "POST" then
        return auth.handle_force_logout()
    elseif uri == "/api/admin/session/all" and method == "GET" then
        return auth.handle_all_sessions()
    elseif uri == "/api/admin/session/cleanup" and method == "POST" then
        return auth.handle_cleanup_sessions()
    
    -- Handle other admin API requests
    elseif uri == "/api/admin/users" and method == "GET" then
        local is_admin = require "is_admin"
        return is_admin.handle_get_all_users()
    elseif uri == "/api/admin/users/pending" and method == "GET" then
        local is_admin = require "is_admin"
        return is_admin.handle_get_pending_users()
    elseif uri == "/api/admin/users/approve" and method == "POST" then
        local is_admin = require "is_admin"
        return is_admin.handle_approve_user()
    elseif uri == "/api/admin/users/reject" and method == "POST" then
        local is_admin = require "is_admin"
        return is_admin.handle_reject_user()
    elseif uri == "/api/admin/stats" and method == "GET" then
        local is_admin = require "is_admin"
        return is_admin.handle_system_stats()
    elseif uri == "/api/admin/guests/clear" and method == "POST" then
        local is_admin = require "is_admin"
        return is_admin.handle_clear_guest_sessions()
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
        return M.handle_admin_api()
    elseif route_type == "auth_api" then
        return M.handle_auth_api()
    elseif route_type == "guest_api" then
        return M.handle_guest_api(user_type, username, user_data)
    end
    
    -- Handle page routes - delegate to page managers with access control
    if route_type == "index" then
        local view_index = require "view_index"
        return view_index.handle(user_type, username, user_data)
        
    elseif route_type == "chat" then
        -- Access control for chat page
        if user_type == "is_none" then
            return ngx.redirect("/")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local view_chat = require "view_chat"
        return view_chat.handle(user_type, username, user_data)
        
    elseif route_type == "dash" then
        -- Access control for dashboard
        if user_type == "is_none" or user_type == "is_guest" or user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local view_dash = require "view_dash"
        return view_dash.handle(user_type, username, user_data)
        
    elseif route_type == "login" then
        -- Redirect authenticated users
        if user_type == "is_admin" or user_type == "is_approved" then
            return ngx.redirect("/chat")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local view_auth = require "view_auth"
        return view_auth.handle_login(user_type, username, user_data)
        
    elseif route_type == "register" then
        -- Redirect authenticated users
        if user_type == "is_admin" or user_type == "is_approved" then
            return ngx.redirect("/chat")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local view_auth = require "view_auth"
        return view_auth.handle_register(user_type, username, user_data)
        
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
    local view_error = require "view_error"
    return view_error.handle_404()
end

function M.handle_429()
    local view_error = require "view_error"
    return view_error.handle_429()
end

function M.handle_50x()
    local view_error = require "view_error"
    return view_error.handle_50x()
end


return M