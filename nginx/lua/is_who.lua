-- =============================================================================
-- nginx/lua/is_who.lua - FIXED ROUTING WITH PROPER GUEST SESSION HANDLING
-- =============================================================================

local jwt = require "resty.jwt"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

-- Server-side JWT verification with enhanced guest validation
function M.check()
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local username = jwt_obj.payload.username
            local user_type_claim = jwt_obj.payload.user_type
            
            local user_data = server.get_user(username)
            
            if user_data then
                if user_data.is_guest_account == "true" or user_type_claim == "guest" then
                    local is_guest = require "is_guest"
                    local guest_session, error_msg = is_guest.validate_guest_session(token)
                    if guest_session then
                        return "guest", guest_session.display_username or guest_session.username, guest_session
                    else
                        ngx.log(ngx.WARN, "Guest session validation failed: " .. (error_msg or "unknown"))
                        ngx.header["Set-Cookie"] = "access_token=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
                        return "none", nil, nil
                    end
                else
                    server.update_user_activity(username)
                    
                    if user_data.is_admin == "true" then
                        return "admin", username, user_data
                    elseif user_data.is_approved == "true" then
                        return "approved", username, user_data
                    else
                        return "authenticated", username, user_data
                    end
                end
            else
                ngx.log(ngx.WARN, "Valid JWT for non-existent user: " .. username)
                return "none", nil, nil
            end
        else
            ngx.log(ngx.WARN, "Invalid JWT token: " .. (jwt_obj.reason or "unknown"))
        end
    end
    
    return "none", nil, nil
end

function M.set_vars()
    local user_type, username, user_data = M.check()
    
    ngx.var.username = username or "anonymous"
    ngx.var.is_admin = (user_type == "admin") and "true" or "false"
    ngx.var.is_approved = (user_type == "approved" or user_type == "admin") and "true" or "false"
    ngx.var.is_guest = (user_type == "guest") and "true" or "false"
    
    if user_type == "guest" and user_data and user_data.slot_number then
        local ok, err = pcall(function()
            ngx.var.guest_slot_id = tostring(user_data.slot_number)
        end)
        if not ok then ngx.log(ngx.WARN, "Failed to set guest_slot_id: " .. err) end
    else
        local ok, err = pcall(function()
            ngx.var.guest_slot_id = ""
        end)
        if not ok then ngx.log(ngx.DEBUG, "Failed to clear guest_slot_id: " .. err) end
    end
    
    if ngx.var.is_admin == "true" then
        ngx.var.user_type = "is_admin"
    elseif ngx.var.is_approved == "true" then
        ngx.var.user_type = "is_approved"
    elseif ngx.var.is_guest == "true" then
        ngx.var.user_type = "is_guest"
    elseif user_type == "authenticated" then
        ngx.var.user_type = "is_pending"
    else
        ngx.var.user_type = "is_none"
    end
    
    return user_type, username, user_data
end

function M.require_admin()
    local user_type, username, user_data = M.check()
    if user_type ~= "admin" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    if not user_data or user_data.is_admin ~= "true" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.require_approved()
    local user_type, username, user_data = M.check()
    if user_type ~= "admin" and user_type ~= "approved" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    if user_type == "approved" and (not user_data or user_data.is_approved ~= "true") then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.require_guest()
    local user_type, username, user_data = M.check()
    if user_type ~= "guest" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    if not user_data or not user_data.slot_number then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.get_user_info()
    local user_type, username, user_data = M.check()
    
    if user_type == "none" then
        return { success = false, user_type = "none", authenticated = false, message = "Not authenticated" }
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
    
    if user_type == "guest" and user_data then
        response.message_limit = user_data.max_messages or 10
        response.messages_used = user_data.message_count or 0
        response.messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
        response.session_remaining = (user_data.expires_at or 0) - ngx.time()
        response.slot_number = user_data.slot_number
        response.priority = user_data.priority or 3
    end
    
    return response
end

-- =====================================================================
-- FIXED route_to_handler function with proper guest session creation
-- =====================================================================
function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_vars()
    ngx.log(ngx.INFO, "Routing " .. route_type .. " for user_type: " .. ngx.var.user_type .. ", user: " .. (username or "unknown"))

    if ngx.var.is_admin == "true" then
        local is_admin = require "is_admin"
        if route_type == "chat" then
            is_admin.handle_chat_page()
        elseif route_type == "dash" then
            is_admin.handle_dash_page()
        elseif route_type == "chat_api" then
            is_admin.handle_chat_api()
        elseif uri == "/api/chat/stream" and method == "POST" then
            is_admin.handle_chat_stream() -- Admin-specific implementation
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end

    elseif ngx.var.is_approved == "true" then
        local is_approved = require "is_approved"
        if route_type == "chat" then
            is_approved.handle_chat_page()
        elseif route_type == "dash" then
            is_approved.handle_dash_page()
        elseif route_type == "chat_api" then
            is_approved.handle_chat_api()
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end

    elseif ngx.var.is_guest == "true" then
        local is_guest = require "is_guest"
        if route_type == "chat" then
            is_guest.handle_chat_page()
        elseif route_type == "dash" then
            -- Guests can't access dashboard - redirect to main page
            return ngx.redirect("/?guest_dashboard_redirect=1")
        elseif route_type == "chat_api" then
            is_guest.handle_chat_api()
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end

    elseif ngx.var.user_type == "is_pending" then
        -- Pending users
        local is_pending = require "is_pending"
        if route_type == "dash" then
            is_pending.handle_dash_page()
        else
            -- Pending users can only access dashboard
            return ngx.redirect("/pending")
        end

    elseif ngx.var.user_type == "is_none" then
        -- Anonymous users
        if route_type == "chat" then
            -- FIXED: Check if user is explicitly requesting guest chat
            local start_guest_chat = ngx.var.arg_start_guest_chat
            if start_guest_chat == "1" then
                -- Redirect to guest session creation
                ngx.log(ngx.INFO, "Anonymous user requesting guest chat - redirecting to guest session creation")
                return ngx.redirect("/?guest_session_requested=1")
            else
                -- Regular chat access without guest session - redirect to home
                ngx.log(ngx.INFO, "Anonymous user trying to access chat - redirecting to home")
                return ngx.redirect("/?start_guest_chat=1")
            end
            
        elseif route_type == "dash" then
            -- Show public dashboard with guest session option
            local is_public = require "is_public"
            is_public.handle_dash_page_with_guest_info()
            
        elseif route_type == "chat_api" then
            -- API access without auth should return 401
            ngx.status = 401
            ngx.header.content_type = 'application/json'
            ngx.say('{"error":"Authentication required","message":"Please login or start a guest session"}')
            return ngx.exit(401)
            
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end
    else
        -- Unknown user type
        ngx.log(ngx.ERROR, "Unknown user type: " .. ngx.var.user_type)
        return ngx.redirect("/login")
    end
end

return M