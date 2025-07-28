-- =============================================================================
-- nginx/lua/aaa_is_who.lua - UPDATED WITH ENHANCED CHAT API ROUTING
-- =============================================================================

local jwt = require "resty.jwt"
local auth = require "manage_auth"
local views = require "manage_views"
local cjson = require "cjson"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

-- =============================================
-- CORE USER TYPE DETERMINATION - NO CHANGES NEEDED
-- =============================================

function M.set_user()
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_admin" and user_type ~= "is_approved" and user_type ~= "is_pending" and user_type ~= "is_guest" then
        username = "guest"
        user_type = "is_none"
    end
    return user_type, username, user_data
end

-- =============================================
-- ACCESS CONTROL HELPERS - NO CHANGES NEEDED
-- =============================================

function M.require_admin()
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_admin" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.require_approved()
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_admin" and user_type ~= "is_approved" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.require_guest()
    local user_type, username, user_data = auth.check()
    if user_type ~= "is_admin" and user_type ~= "is_approved" and user_type ~= "is_guest" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

-- =====================================================================
-- MAIN ROUTING HANDLER - UPDATED FOR ENHANCED CHAT API
-- =====================================================================

function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_user()
    
    -- Handle Ollama API endpoints first
    if route_type == "ollama_chat_api" then
        M.handle_ollama_chat_api()
        return
    end
    
    -- ROUTING LOGIC: Based on what each user type can see, using views module
    if user_type == "is_admin" then
        -- Can see: /chat, /dash, / 
        -- Redirect login/register to dash
        if route_type == "login" or route_type == "register" then
            return ngx.redirect("/dash")
        end
        
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        elseif route_type == "chat" then
            return views.handle_chat_page_admin()
        elseif route_type == "dash" then
            return views.handle_dash_page_admin()
        else
            -- Delegate to is_admin module for API endpoints
            local is_admin = require "is_admin"
            return is_admin.handle_route(route_type)
        end
        
    elseif user_type == "is_approved" then
        -- Can see: /chat, /dash, / 
        -- Redirect login/register to dash
        if route_type == "login" or route_type == "register" then
            return ngx.redirect("/dash")
        end
        
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        elseif route_type == "chat" then
            return views.handle_chat_page_approved()
        elseif route_type == "dash" then
            return views.handle_dash_page_approved()
        else
            -- Delegate to is_approved module for API endpoints
            local is_approved = require "is_approved"
            return is_approved.handle_route(route_type)
        end
        
    elseif user_type == "is_pending" then
        -- Can see: /, /dash (pending shows as dash)
        -- Block chat, login, register
        if route_type == "chat" or route_type == "login" or route_type == "register" then
            return ngx.redirect("/dash")
        end
        
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        elseif route_type == "dash" then
            return views.handle_dash_page_pending()
        else
            -- Delegate to is_pending module for API endpoints
            local is_pending = require "is_pending"
            return is_pending.handle_route(route_type)
        end
        
    elseif user_type == "is_guest" then
        if route_type == "dash" then
            return ngx.redirect("/")
        end
        
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        elseif route_type == "chat" then
            return views.handle_chat_page_guest()
        elseif route_type == "login" then
            return views.handle_login_page()
        elseif route_type == "register" then
            return views.handle_register_page()
        else
            -- Delegate to is_guest module for API endpoints
            local is_guest = require "is_guest"
            return is_guest.handle_route(route_type)
        end
        
    elseif user_type == "is_none" then
        -- Can see: /, /login, /register
        -- Block chat and dash (unless upgrading to guest through available logic)
        if route_type == "chat" or route_type == "dash" then
            return ngx.redirect("/")
        end
        
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        elseif route_type == "login" then
            return views.handle_login_page()
        elseif route_type == "register" then
            return views.handle_register_page()
        else
            -- Delegate to is_none module for API endpoints
            local is_none = require "is_none"
            return is_none.handle_route(route_type)
        end
    end
    
    -- Fallback redirect
    return ngx.redirect("/")
end

-- =====================================================================
-- ERROR PAGE HANDLERS - USE VIEWS MODULE
-- =====================================================================

function M.handle_404()
    return views.handle_404_page()
end

function M.handle_429()
    return views.handle_429_page()
end

function M.handle_50x()
    return views.handle_50x_page()
end

-- =====================================================================
-- ENHANCED OLLAMA API HANDLERS WITH FULL CHAT API ROUTING
-- =====================================================================

function M.handle_ollama_chat_api()
    local user_type, username, user_data = M.set_user()
    
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
    
    ngx.log(ngx.INFO, "🔄 Chat API request: " .. method .. " " .. uri .. " (user: " .. user_type .. ")")
    
    -- Route to appropriate user-specific chat handler
    if user_type == "is_admin" then
        local is_admin = require "is_admin"
        return is_admin.handle_chat_api()
    elseif user_type == "is_approved" then
        local is_approved = require "is_approved"
        return is_approved.handle_chat_api()
    elseif user_type == "is_guest" then
        local is_guest = require "is_guest"
        return is_guest.handle_chat_api()
    elseif user_type == "is_pending" then
        -- Pending users shouldn't have chat access
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Account pending approval - no chat access"
        }))
        return ngx.exit(403)
    else
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Invalid user type: " .. tostring(user_type)
        }))
        return ngx.exit(403)
    end
end

-- =============================================
-- SIMPLE API ROUTING FUNCTIONS - UPDATED FOR ENHANCED CHAT
-- =============================================

function M.handle_auth_api_status()
    local user_type = select(1, auth.check())

    if user_type == "is_admin" or user_type == "is_approved" or user_type == "is_guest" then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say('{"status":"success"}')
    else
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say('{"status":"fail"}')
    end
end

function M.handle_auth_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    -- IMPORTANT: Login and logout should be accessible without authentication checks
    if uri == "/api/auth/login" and method == "POST" then
        -- NO AUTH CHECK - anyone should be able to login
        auth.handle_login()
    elseif uri == "/api/auth/logout" and method == "POST" then
        -- NO AUTH CHECK - anyone should be able to logout
        auth.handle_logout()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ 
            error = "Auth endpoint not found",
            message = "Only login, logout, and user-info endpoints available",
            available_endpoints = {
                "POST /api/auth/login - User login",
                "POST /api/auth/logout - User logout"
            }
        }))
    end
end

function M.handle_register_api()
    local register = require "manage_register"
    register.handle_register_api()
end

function M.handle_admin_api()
    local is_admin = require "is_admin"
    is_admin.handle_admin_api()
end

function M.handle_guest_api()
    -- Use is_none module for guest session creation
    local is_none = require "is_none"
    is_none.handle_guest_session_api()
end

-- =============================================
-- COMPATIBILITY FUNCTIONS (IF NEEDED BY OTHER MODULES)
-- =============================================

-- Expose auth.check for other modules that might need it
function M.check()
    return auth.check()
end

return M