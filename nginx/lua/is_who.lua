-- =============================================================================
-- nginx/lua/is_who.lua - WITH RESTORED ROUTE_TO_HANDLER FUNCTION AND 50X HOOK
-- =============================================================================

local jwt = require "resty.jwt"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

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
                        return "guest", guest_session.username, guest_session
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
-- Restored route_to_handler function
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
            ngx.redirect("/login")
        elseif route_type == "chat_api" then
            is_guest.handle_chat_api()
        else
            ngx.status = 404
            return ngx.exec("@custom_50x")
        end

    elseif ngx.var.user_type == "isnone" then
        ngx.log(ngx.INFO, "Anonymous user accessing " .. route_type .. " - creating guest session")
        local is_guest = require "is_guest"
        local session_data, err = is_guest.create_secure_guest_session()
        if session_data then
            ngx.log(ngx.INFO, "Guest session created: " .. session_data.username .. " [Slot " .. session_data.slot_number .. "]")
            if route_type == "chat" then
                return ngx.redirect("/chat")
            elseif route_type == "chat_api" then
                user_type, username, user_data = M.set_vars()
                if ngx.var.is_guest == "true" then
                    is_guest.handle_chat_api()
                else
                    ngx.status = 500
                    return ngx.exec("@custom_50x")
                end
            else
                ngx.status = 404
                return ngx.exec("@custom_50x")
            end
            else
                ngx.log(ngx.WARN, "Guest session creation failed: " .. (err or "unknown"))
                ngx.status = 429
                return ngx.exec("@custom_429")
            end
    else
        return ngx.redirect("/login")
    end
end

return M
