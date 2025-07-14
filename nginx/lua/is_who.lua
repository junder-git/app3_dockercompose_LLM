-- nginx/lua/is_who.lua - Server-side JWT validation and user identification
local jwt = require "resty.jwt"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local M = {}

-- Server-side JWT verification - ONLY source of truth
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
    
    -- Check for guest token
    local guest_token = ngx.var.cookie_guest_token
    if guest_token and string.match(guest_token, "^guest_") then
        local guest_username = string.gsub(guest_token, "guest_token_", "guest_")
        
        -- Validate guest session in shared memory
        local guest_data = server.get_guest_session(guest_username)
        if guest_data then
            return "guest", guest_username, guest_data
        end
    end
    
    return "none", nil, nil
end

-- Set nginx variables - SERVER CONTROLS EVERYTHING
function M.set_vars()
    local user_type, username, user_data = M.check()
    
    ngx.var.user_type = user_type
    ngx.var.username = username or "anonymous"
    
    -- Server-side permission flags - NEVER trust client
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

-- SECURITY: Admin access requires server-side verification
function M.require_admin()
    local user_type, username, user_data = M.check()
    
    -- CRITICAL: Must be admin type from server validation
    if user_type ~= "admin" then
        ngx.log(ngx.WARN, "Admin access denied for user_type: " .. (user_type or "none") .. ", user: " .. (username or "unknown"))
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say('{"error": "Admin access required", "user_type": "' .. (user_type or "none") .. '"}')
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
        local redirect_url = "/"
        
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

-- CLIENT API: Only returns what server permits
function M.get_user_info()
    local user_type, username, user_data = M.check()
    
    -- SERVER DETERMINES WHAT CLIENT SEES
    if user_type == "admin" then
        return {
            success = true,
            user_type = "admin",
            username = username,
            is_admin = true,
            is_approved = true,
            is_guest = false,
            dashboard_url = "/admin",
            permissions = {"admin", "approved", "chat", "export", "manage_users"}
        }
    elseif user_type == "approved" then
        return {
            success = true,
            user_type = "approved", 
            username = username,
            is_admin = false,
            is_approved = true,
            is_guest = false,
            dashboard_url = "/dashboard",
            permissions = {"approved", "chat", "export"}
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
            limits = limits,
            dashboard_url = "/chat",
            permissions = {"guest_chat"}
        }
    elseif user_type == "authenticated" then
        return {
            success = false,
            user_type = "pending",
            username = username,
            is_admin = false,
            is_approved = false,
            is_guest = false,
            error = "Account pending approval",
            dashboard_url = "/pending",
            permissions = {}
        }
    else
        return {
            success = false,
            user_type = "none",
            is_admin = false,
            is_approved = false,
            is_guest = false,
            error = "Not authenticated",
            dashboard_url = "/login",
            permissions = {}
        }
    end
end

-- Helper: Get dashboard URL based on SERVER validation
function M.get_dashboard_url()
    local user_type, username, user_data = M.check()
    
    if user_type == "admin" then
        return "/admin"
    elseif user_type == "approved" then
        return "/dashboard"
    elseif user_type == "authenticated" then
        return "/pending"
    elseif user_type == "guest" then
        return "/chat"
    else
        return "/"
    end
end

return M