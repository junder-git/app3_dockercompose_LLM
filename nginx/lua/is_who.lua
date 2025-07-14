-- nginx/lua/is_who.lua - Central user identification for all routes
local jwt = require "resty.jwt"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local M = {}

-- Check who the user is and return their type
function M.check()
    -- First, try JWT token (logged-in users)
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local username = jwt_obj.payload.username
            
            -- Get user info from Redis via server module
            local user_data = server.get_user(username)
            
            if user_data then
                -- Update last active
                server.update_user_activity(username)
                
                if user_data.is_admin == "true" then
                    return "admin", username, user_data
                elseif user_data.is_approved == "true" then
                    return "approved", username, user_data
                else
                    return "pending", username, user_data
                end
            end
        end
    end
    
    -- Check for guest token
    local guest_token = ngx.var.cookie_guest_token
    if guest_token and string.match(guest_token, "^guest_") then
        local guest_username = string.gsub(guest_token, "guest_token_", "guest_")
        
        -- Check if guest session is still valid via server module
        local guest_data = server.get_guest_session(guest_username)
        if guest_data then
            return "guest", guest_username, guest_data
        end
    end
    
    return "none", nil, nil
end

-- Set nginx variables for use in other modules
function M.set_vars()
    local user_type, username, user_data = M.check()
    
    ngx.var.user_type = user_type
    ngx.var.username = username or "anonymous"
    
    if user_data then
        ngx.var.is_admin = (user_type == "admin") and "true" or "false"
        ngx.var.is_approved = (user_type == "approved" or user_type == "admin") and "true" or "false"
        ngx.var.is_guest = (user_type == "guest") and "true" or "false"
    else
        ngx.var.is_admin = "false"
        ngx.var.is_approved = "false"
        ngx.var.is_guest = "false"
    end
    
    return user_type, username, user_data
end

-- Check if user can access admin functions
function M.require_admin()
    local user_type, username, user_data = M.check()
    
    if user_type ~= "admin" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Admin access required"}')
        ngx.exit(403)
    end
    
    ngx.var.auth_username = username
    return username, user_data
end

-- Check if user can access approved user functions
function M.require_approved()
    local user_type, username, user_data = M.check()
    
    if user_type ~= "admin" and user_type ~= "approved" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Approved user access required"}')
        ngx.exit(403)
    end
    
    ngx.var.auth_username = username
    return username, user_data
end

-- Get user info for API responses
function M.get_user_info()
    local user_type, username, user_data = M.check()
    
    if user_type == "admin" then
        return {
            success = true,
            user_type = "admin",
            username = username,
            is_admin = true,
            is_approved = true,
            is_guest = false
        }
    elseif user_type == "approved" then
        return {
            success = true,
            user_type = "approved",
            username = username,
            is_admin = false,
            is_approved = true,
            is_guest = false
        }
    elseif user_type == "guest" then
        local limits = server.get_guest_limits(username)
        return {
            success = true,
            user_type = "guest",
            username = username,
            is_admin = false,
            is_approved = false,
            is_guest = true,
            limits = limits
        }
    elseif user_type == "pending" then
        return {
            success = false,
            user_type = "pending",
            username = username,
            error = "Account pending approval"
        }
    else
        return {
            success = false,
            user_type = "none",
            error = "Not authenticated"
        }
    end
end

return M