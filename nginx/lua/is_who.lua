-- =============================================================================
-- nginx/lua/is_who.lua - SIMPLIFIED AUTHENTICATION WITH SAFER VARIABLE HANDLING
-- =============================================================================

local jwt = require "resty.jwt"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local M = {}

-- Server-side JWT verification with enhanced guest validation
function M.check()
    -- First, try JWT token (logged-in users)
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local username = jwt_obj.payload.username
            
            -- CRITICAL: Always re-validate against Redis, never trust JWT claims alone
            local user_data = server.get_user(username)
            
            if user_data then
                -- Update last active
                server.update_user_activity(username)
                
                -- Server determines permissions from Redis, not JWT
                if user_data.is_admin == "true" then
                    return "admin", username, user_data
                elseif user_data.is_approved == "true" then
                    return "approved", username, user_data
                else
                    -- Authenticated but not approved = pending
                    return "authenticated", username, user_data
                end
            else
                -- JWT valid but user doesn't exist in Redis = invalid
                ngx.log(ngx.WARN, "Valid JWT for non-existent user: " .. username)
                return "none", nil, nil
            end
        else
            ngx.log(ngx.WARN, "Invalid JWT token: " .. (jwt_obj.reason or "unknown"))
        end
    end
    
    -- Check for guest token (ENHANCED with JWT lock validation)
    local guest_token = ngx.var.cookie_guest_token
    if guest_token then
        -- SECURITY: Validate guest session with anti-hijacking
        local guest_session, error_msg = server.validate_guest_session(guest_token)
        if guest_session then
            -- SECURITY: Use dynamic username from session, not JWT
            return "guest", guest_session.username, guest_session
        else
            ngx.log(ngx.WARN, "Guest session validation failed: " .. (error_msg or "unknown"))
            -- Clear invalid guest token
            ngx.header["Set-Cookie"] = "guest_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        end
    end
    
    return "none", nil, nil
end

-- Set nginx variables - SERVER CONTROLS EVERYTHING
function M.set_vars()
    local user_type, username, user_data = M.check()
    
    -- Set core variables (with fallback defaults)
    ngx.var.username = username or "anonymous"
    
    -- Set permission flags based on Redis data (ONLY source of truth)
    ngx.var.is_admin = (user_type == "admin") and "true" or "false"
    ngx.var.is_approved = (user_type == "approved" or user_type == "admin") and "true" or "false"
    ngx.var.is_guest = (user_type == "guest") and "true" or "false"
    
    -- SECURITY: For guests, store slot_id for JWT management (with safe fallback)
    if user_type == "guest" and user_data and user_data.slot_id then
        -- Use pcall to safely set guest_slot_id if it exists
        local ok, err = pcall(function()
            ngx.var.guest_slot_id = user_data.slot_id
        end)
        if not ok then
            ngx.log(ngx.WARN, "Failed to set guest_slot_id: " .. err)
        end
    else
        -- Safely clear guest_slot_id
        local ok, err = pcall(function()
            ngx.var.guest_slot_id = ""
        end)
        if not ok then
            ngx.log(ngx.DEBUG, "Failed to clear guest_slot_id: " .. err)
        end
    end
    
    -- Derive user_type from permission flags
    if ngx.var.is_admin == "true" then
        ngx.var.user_type = "isadmin"
    elseif ngx.var.is_approved == "true" then
        ngx.var.user_type = "isapproved"
    elseif ngx.var.is_guest == "true" then
        ngx.var.user_type = "isguest"
    elseif user_type == "authenticated" then
        ngx.var.user_type = "ispending"
    else
        ngx.var.user_type = "isnone"
    end
    
    return user_type, username, user_data
end

-- SECURITY: Admin access requires server-side verification
function M.require_admin()
    local user_type, username, user_data = M.check()
    
    -- CRITICAL: Must be admin type from server validation
    if user_type ~= "admin" then
        ngx.log(ngx.WARN, "Admin access denied for user_type: " .. (user_type or "none") .. ", user: " .. (username or "unknown"))
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Admin access required", "user_type": "' .. (user_type or "none") .. '", "redirect": "/login"}')
        ngx.exit(403)
    end
    
    -- Double-check Redis permissions
    if not user_data or user_data.is_admin ~= "true" then
        ngx.log(ngx.ERR, "SECURITY VIOLATION: Admin claim without Redis permission for user: " .. (username or "unknown"))
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Insufficient permissions"}')
        ngx.exit(403)
    end
    
    return username, user_data
end

-- SECURITY: Approved access requires server-side verification
function M.require_approved()
    local user_type, username, user_data = M.check()
    
    -- CRITICAL: Must be admin or approved from server validation
    if user_type ~= "admin" and user_type ~= "approved" then
        local error_msg = "Approved user access required"
        local redirect_url = "/login"
        
        if user_type == "authenticated" then
            error_msg = "Account pending approval - access denied"
            redirect_url = "/pending"
        elseif user_type == "guest" then
            error_msg = "Guest users cannot access this feature"
            redirect_url = "/register"
        elseif user_type == "none" then
            error_msg = "Authentication required"
            redirect_url = "/login"
        end
        
        ngx.log(ngx.WARN, "Approved access denied for user_type: " .. (user_type or "none") .. ", user: " .. (username or "unknown"))
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "' .. error_msg .. '", "user_type": "' .. (user_type or "none") .. '", "redirect": "' .. redirect_url .. '"}')
        ngx.exit(403)
    end
    
    -- Double-check Redis permissions for non-admin users
    if user_type == "approved" and (not user_data or user_data.is_approved ~= "true") then
        ngx.log(ngx.ERR, "SECURITY VIOLATION: Approved claim without Redis permission for user: " .. (username or "unknown"))
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Insufficient permissions"}')
        ngx.exit(403)
    end
    
    return username, user_data
end

-- ENHANCED: Guest validation with JWT lock checking
function M.require_guest()
    local user_type, username, user_data = M.check()
    
    if user_type ~= "guest" then
        ngx.log(ngx.WARN, "Guest access denied for user_type: " .. (user_type or "none"))
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Guest access required", "user_type": "' .. (user_type or "none") .. '", "redirect": "/"}')
        ngx.exit(403)
    end
    
    -- Additional guest validation
    if not user_data or not user_data.slot_id then
        ngx.log(ngx.ERR, "Invalid guest session data")
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Invalid guest session"}')
        ngx.exit(403)
    end
    
    return username, user_data
end

-- ENHANCED: Get user info with guest session details
function M.get_user_info()
    local user_type, username, user_data = M.check()
    
    if user_type == "none" then
        return {
            success = false,
            user_type = "none",
            authenticated = false,
            message = "Not authenticated"
        }
    end
    
    local response = {
        success = true,
        username = username,
        user_type = user_type,
        authenticated = true,
        is_admin = (user_type == "admin"),
        is_approved = (user_type == "approved" or user_type == "admin"),
        is_guest = (user_type == "guest")
    }
    
    -- Add type-specific information
    if user_type == "admin" then
        response.permissions = {"chat", "dashboard", "admin", "unlimited_messages"}
        response.storage_type = "redis"
        response.message_limit = "unlimited"
        
    elseif user_type == "approved" then
        response.permissions = {"chat", "dashboard", "unlimited_messages"}
        response.storage_type = "redis"
        response.message_limit = "unlimited"
        
    elseif user_type == "guest" then
        response.permissions = {"chat"}
        response.storage_type = "none"
        
        -- Add guest-specific session info
        if user_data then
            local limits, err = server.get_guest_limits(user_data.slot_id)
            if limits then
                response.message_limit = limits.max_messages
                response.messages_used = limits.used_messages
                response.messages_remaining = limits.remaining_messages
                response.session_remaining = limits.session_remaining
                response.slot_number = limits.slot_number
                response.priority = limits.priority
            else
                response.message_limit = 10
                response.session_error = err
            end
        end
        
    elseif user_type == "authenticated" then
        response.permissions = {}
        response.storage_type = "none"
        response.message_limit = 0
        response.status = "pending_approval"
        response.message = "Account pending administrator approval"
    end
    
    return response
end

-- ROUTING CONTROLLER: Determines which handler should process the request
function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_vars()
    
    ngx.log(ngx.INFO, "Routing " .. route_type .. " for user_type: " .. ngx.var.user_type .. ", user: " .. (username or "unknown"))
    
    -- SYSTEMATIC ROUTING based on permission flags
    if ngx.var.is_admin == "true" then
        -- ADMIN: Route to is_admin handler
        local is_admin = require "is_admin"
        if route_type == "chat" then
            is_admin.handle_chat_page()
        elseif route_type == "dash" then
            is_admin.handle_dash_page()
        else
            ngx.status = 404
            ngx.say("Unknown admin route: " .. route_type)
            ngx.exit(404)
        end
        
    elseif ngx.var.is_approved == "true" then
        -- APPROVED: Route to is_approved handler
        local is_approved = require "is_approved"
        if route_type == "chat" then
            is_approved.handle_chat_page()
        elseif route_type == "dash" then
            is_approved.handle_dash_page()
        else
            ngx.status = 404
            ngx.say("Unknown approved route: " .. route_type)
            ngx.exit(404)
        end
        
    elseif ngx.var.user_type == "ispending" then
        -- PENDING: Show pending status on dashboard, redirect chat to dash
        if route_type == "chat" then
            ngx.log(ngx.INFO, "Redirecting pending user " .. username .. " to /dash (pending approval)")
            return ngx.redirect("/dash")
        elseif route_type == "dash" then
            local is_pending = require "is_pending"
            is_pending.handle_dash_page()
        else
            ngx.status = 404
            ngx.say("Unknown pending route: " .. route_type)
            ngx.exit(404)
        end
        
    elseif ngx.var.is_guest == "true" then
        -- ACTIVE GUEST: Route to guest handler
        local is_guest = require "is_guest"
        if route_type == "chat" then
            is_guest.handle_chat_page()
        elseif route_type == "dash" then
            -- Guests get redirected to login from dashboard
            ngx.log(ngx.INFO, "Guest user attempting to access dashboard, redirecting to /login")
            return ngx.redirect("/login")
        else
            ngx.status = 404
            ngx.say("Unknown guest route: " .. route_type)
            ngx.exit(404)
        end
        
    elseif ngx.var.user_type == "isnone" then
        -- ANONYMOUS: Special handling for chat vs dash
        if route_type == "chat" then
            -- Try to create guest session automatically
            local session_data, error_msg = server.create_secure_guest_session()
            if session_data then
                ngx.log(ngx.INFO, "Auto-created guest session for anonymous user: " .. session_data.username)
                -- Redirect to chat with new guest session
                return ngx.redirect("/chat")
            else
                ngx.log(ngx.WARN, "Failed to create guest session for anonymous user: " .. (error_msg or "unknown"))
                -- Redirect to dashboard with guest unavailable message
                return ngx.redirect("/dash?guest_unavailable=true")
            end
        elseif route_type == "dash" then
            -- Show dashboard with guest session info or login prompt
            local is_public = require "is_public"
            is_public.handle_dash_page_with_guest_info()
        else
            ngx.status = 404
            ngx.say("Unknown anonymous route: " .. route_type)
            ngx.exit(404)
        end
        
    else
        -- FALLBACK: Something went wrong
        ngx.log(ngx.ERR, "Unknown user state for routing: " .. ngx.var.user_type)
        return ngx.redirect("/login")
    end
end

return M