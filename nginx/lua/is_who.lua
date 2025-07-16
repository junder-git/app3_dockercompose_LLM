-- =============================================================================
-- nginx/lua/is_who.lua - SIMPLIFIED AUTHENTICATION WITH AUTO-GUEST AND FIXED TOKEN HANDLING
-- =============================================================================

local jwt = require "resty.jwt"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local M = {}

-- Server-side JWT verification with enhanced guest validation
function M.check()
    -- First, try JWT token (logged-in users AND guests)
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local username = jwt_obj.payload.username
            local user_type_claim = jwt_obj.payload.user_type
            
            -- CRITICAL: Always re-validate against Redis, never trust JWT claims alone
            local user_data = server.get_user(username)
            
            if user_data then
                -- Check if this is a guest account
                if user_data.is_guest_account == "true" or user_type_claim == "guest" then
                    -- Additional guest session validation
                    local is_guest = require "is_guest"
                    local guest_session, error_msg = is_guest.validate_guest_session(token)
                    if guest_session then
                        -- Valid guest session
                        return "guest", guest_session.username, guest_session
                    else
                        ngx.log(ngx.WARN, "Guest session validation failed: " .. (error_msg or "unknown"))
                        -- Clear invalid token
                        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
                        return "none", nil, nil
                    end
                else
                    -- Regular user authentication
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
    
    -- SECURITY: For guests, store slot_number for consistency
    if user_type == "guest" and user_data and user_data.slot_number then
        -- Use pcall to safely set guest slot number
        local ok, err = pcall(function()
            ngx.var.guest_slot_id = tostring(user_data.slot_number)
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
    if not user_data or not user_data.slot_number then
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
            response.message_limit = user_data.max_messages or 10
            response.messages_used = user_data.message_count or 0
            response.messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
            response.session_remaining = (user_data.expires_at or 0) - ngx.time()
            response.slot_number = user_data.slot_number
            response.priority = user_data.priority or 3
        else
            response.message_limit = 10
            response.session_error = "No user data"
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
        elseif route_type == "chat_api" then
            is_admin.handle_chat_api()
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
        elseif route_type == "chat_api" then
            is_approved.handle_chat_api()
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
        elseif route_type == "chat_api" then
            -- Block pending users from chat API
            ngx.status = 403
            ngx.header.content_type = 'application/json'
            ngx.say('{"error": "Account pending approval - chat access denied", "redirect": "/pending"}')
            ngx.exit(403)
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
        elseif route_type == "chat_api" then
            is_guest.handle_chat_api()
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
        -- ANONYMOUS: Special handling for chat vs dash with AUTO-GUEST
        if route_type == "chat" or route_type == "chat_api" then
            -- AUTO-GUEST: Try to create guest session automatically
            ngx.log(ngx.INFO, "Anonymous user accessing " .. route_type .. " - attempting auto-guest session creation")
            
            local is_guest = require "is_guest"
            
            -- First check if guest slots are available
            local guest_stats, stats_err = is_guest.get_guest_stats()
            if not guest_stats or guest_stats.available_slots <= 0 then
                ngx.log(ngx.WARN, "Auto-guest failed: No slots available (" .. 
                    (guest_stats and guest_stats.available_slots or "unknown") .. "/" .. 
                    (guest_stats and guest_stats.max_sessions or "unknown") .. ")")
                
                if route_type == "chat" then
                    -- Redirect to dashboard with guest unavailable message
                    return ngx.redirect("/dash?guest_unavailable=true")
                else -- chat_api
                    ngx.status = 503
                    ngx.header.content_type = 'application/json'
                    ngx.say('{"error": "No guest slots available", "suggestion": "Try again later or register"}')
                    ngx.exit(503)
                end
            end
            
            -- Try to create guest session
            local session_data, error_msg = is_guest.create_secure_guest_session()
            if session_data then
                ngx.log(ngx.INFO, "Auto-guest session created successfully: " .. session_data.username .. 
                    " [Slot " .. session_data.slot_number .. "] from " .. (ngx.var.remote_addr or "unknown"))
                
                if route_type == "chat" then
                    -- Session created and cookie set - redirect to reload with guest authentication
                    return ngx.redirect("/chat")
                else -- chat_api
                    -- Re-check auth and continue with API handling
                    user_type, username, user_data = M.set_vars()
                    is_guest.handle_chat_api()
                end
            else
                ngx.log(ngx.WARN, "Auto-guest session creation failed: " .. (error_msg or "unknown"))
                
                if route_type == "chat" then
                    -- Redirect to dashboard with guest unavailable message
                    return ngx.redirect("/dash?guest_unavailable=true")
                else -- chat_api
                    ngx.status = 503
                    ngx.header.content_type = 'application/json'
                    ngx.say('{"error": "Guest session creation failed", "message": "' .. (error_msg or "unknown") .. '"}')
                    ngx.exit(503)
                end
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

-- NEW: Helper function to manually trigger guest session creation (for API endpoints)
function M.create_auto_guest_session()
    local user_type, username, user_data = M.check()
    
    -- Only create for anonymous users
    if user_type ~= "none" then
        return nil, "User already authenticated as: " .. user_type
    end
    
    local is_guest = require "is_guest"
    
    -- Check availability first
    local guest_stats, stats_err = is_guest.get_guest_stats()
    if not guest_stats or guest_stats.available_slots <= 0 then
        return nil, "No guest slots available"
    end
    
    -- Create session
    local session_data, error_msg = is_guest.create_secure_guest_session()
    if session_data then
        ngx.log(ngx.INFO, "Manual auto-guest session created: " .. session_data.username)
        return session_data, nil
    else
        return nil, error_msg or "Guest session creation failed"
    end
end

return M