-- =============================================================================
-- nginx/lua/aaa_is_who.lua - MAIN ROUTER MODULE - UPDATED FOR REDIS SESSIONS
-- =============================================================================

local jwt = require "resty.jwt"
local auth = require "manage_auth"
local cjson = require "cjson"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

-- =============================================
-- USER TYPE DETERMINATION WITH REDIS SESSION VALIDATION
-- =============================================

function M.set_user()
    local user_type, username, user_data = auth.check_user_type()
    
    if user_type == "is_admin" or user_type == "is_approved" or user_type == "is_pending" or user_type == "is_guest" then
        -- DELEGATE session check to Redis session manager
        local session_manager = require "manage_redis_sessions"
        local session_active = session_manager.check_session_active(username, user_type)
        
        if not session_active then
            ngx.log(ngx.WARN, string.format("Session not active for %s '%s' - reverting to is_none", 
                user_type, username or "unknown"))
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
-- ENHANCED GUEST API HANDLER - WITH REDIS SESSION COLLISION DETECTION
-- =============================================================================

function M.handle_guest_api(user_type, username, user_data)
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    ngx.log(ngx.INFO, "🎮 Guest API: " .. method .. " " .. uri .. " (user: " .. tostring(user_type) .. ")")
    
    if (uri == "/api/guest/create" or uri == "/api/guest/create-session") and method == "POST" then
        -- Only is_none users can create guest sessions
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
        
        -- ENHANCED: Check session manager for collision detection before delegating to is_none.lua
        local session_manager = require "manage_redis_sessions"
        local active_user, err = session_manager.get_active_user()
        
        if active_user then
            local blocking_type = active_user.user_type
            local blocking_username = active_user.username
            
            -- If there's an active admin or approved user, deny guest session
            if blocking_type == "is_admin" or blocking_type == "is_approved" then
                ngx.log(ngx.INFO, string.format("❌ Guest session blocked by active %s '%s'", 
                    blocking_type, blocking_username))
                
                ngx.status = 409
                ngx.header.content_type = 'application/json'
                ngx.say(cjson.encode({
                    success = false,
                    error = "Sessions are currently full",
                    message = string.format("%s '%s' is currently active", 
                        blocking_type == "is_admin" and "Administrator" or "Approved User", 
                        blocking_username),
                    reason = "high_priority_user_active",
                    blocking_info = {
                        user_type = blocking_type,
                        username = blocking_username,
                        priority = blocking_type == "is_admin" and 1 or 2
                    },
                    suggestion = "Please try again when the current session becomes inactive"
                }))
                return
            end
            
            -- If there's an active guest, check activity to prevent collision
            if blocking_type == "is_guest" then
                local last_activity = tonumber(active_user.last_activity) or 0
                local current_time = ngx.time()
                local session_age = current_time - last_activity
                
                -- If guest session is recently active (within 60 seconds), block
                if session_age <= 60 then
                    ngx.log(ngx.INFO, string.format("❌ Guest session blocked - another guest active %ds ago", 
                        session_age))
                    
                    ngx.status = 409
                    ngx.header.content_type = 'application/json'
                    ngx.say(cjson.encode({
                        success = false,
                        error = "Guest session already active",
                        message = string.format("Another guest user is currently active (last seen %d seconds ago). Please wait a moment.", 
                            session_age),
                        reason = "guest_session_active",
                        session_info = {
                            session_age = session_age,
                            time_until_available = math.max(0, 60 - session_age)
                        },
                        suggestion = "Please try again in " .. math.max(1, math.ceil((60 - session_age) / 60)) .. " minute(s)"
                    }))
                    return
                end
                
                ngx.log(ngx.INFO, string.format("♻️ Guest session allowed - previous guest inactive for %ds", session_age))
            end
        end
        
        -- CRITICAL: Use is_none.lua for smart session management with Redis collision detection
        ngx.log(ngx.INFO, "✅ Delegating to is_none.lua for smart session management with Redis validation")
        
        local success, result = pcall(function()
            local is_none = require "is_none"
            return is_none.handle_create_session()  -- This will call is_guest.lua with Redis integration
        end)
        
        if not success then
            ngx.log(ngx.ERR, "❌ is_none handler failed: " .. tostring(result))
            ngx.status = 500
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                error = "Internal server error",
                message = "Smart session management failed. Please try again."
            }))
        end
        
    else
        -- Return proper JSON error for unknown endpoints
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Guest API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/guest/create-session"
            }
        }))
    end
end

-- =============================================
-- CHAT API WITH REDIS SESSION VALIDATION
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
-- AUTH API HANDLER (DELEGATES TO SIMPLIFIED AUTH)
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
-- ADMIN API WITH REDIS SESSION VALIDATION
-- =============================================

function M.handle_admin_api()
    -- Check if user is admin using Redis session validation
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
    
    -- Handle Redis session management API requests (DELEGATE TO SESSION MANAGER)
    if uri == "/api/admin/session/status" and method == "GET" then
        return auth.handle_session_status()  -- This now delegates to session manager
    elseif uri == "/api/admin/session/force-logout" and method == "POST" then
        return auth.handle_force_logout()    -- This now delegates to session manager
    elseif uri == "/api/admin/session/all" and method == "GET" then
        return auth.handle_all_sessions()    -- This now delegates to session manager
    elseif uri == "/api/admin/session/cleanup" and method == "POST" then
        return auth.handle_cleanup_sessions() -- This now delegates to session manager
    
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
                "Redis Session Management:",
                "GET /api/admin/session/status",
                "POST /api/admin/session/force-logout",
                "GET /api/admin/session/all",
                "POST /api/admin/session/cleanup"
            }
        }))
    end
end

-- =============================================
-- MAIN ROUTING HANDLER WITH REDIS SESSION INTEGRATION
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
        -- Access control for chat page with Redis session validation
        if user_type == "is_none" then
            return ngx.redirect("/")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local view_chat = require "view_chat"
        return view_chat.handle(user_type, username, user_data)
        
    elseif route_type == "dash" then
        -- Access control for dashboard with Redis session validation
        if user_type == "is_none" or user_type == "is_guest" or user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local view_dash = require "view_dash"
        return view_dash.handle(user_type, username, user_data)
        
    elseif route_type == "login" then
        -- Redirect authenticated users (with Redis session validation)
        if user_type == "is_admin" or user_type == "is_approved" then
            return ngx.redirect("/chat")
        elseif user_type == "is_pending" then
            return ngx.redirect("/")
        end
        local view_auth = require "view_auth"
        return view_auth.handle_login(user_type, username, user_data)
        
    elseif route_type == "register" then
        -- Redirect authenticated users (with Redis session validation)
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