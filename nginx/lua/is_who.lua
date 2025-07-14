-- =============================================================================
-- nginx/lua/is_who.lua - CORE AUTHENTICATION AND ROUTING CONTROLLER
-- =============================================================================

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
    if guest_token and string.match(guest_token, "^guest_token_") then
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
    
    -- Set core variables
    ngx.var.username = username or "anonymous"
    
    -- Set permission flags based on Redis data (ONLY source of truth)
    if user_data then
        ngx.var.is_admin = (user_type == "admin") and "true" or "false"
        ngx.var.is_approved = (user_type == "approved" or user_type == "admin") and "true" or "false"
        ngx.var.is_guest = (user_type == "guest") and "true" or "false"
    else
        ngx.var.is_admin = "false"
        ngx.var.is_approved = "false"
        ngx.var.is_guest = "false"
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
        -- PENDING: Redirect to pending page
        ngx.log(ngx.INFO, "Redirecting pending user " .. username .. " to /pending")
        return ngx.redirect("/pending")
        
    elseif ngx.var.is_guest == "true" or ngx.var.user_type == "isnone" then
        -- GUEST/PUBLIC: Route to is_guest handler
        local is_guest = require "is_guest"
        if route_type == "chat" then
            is_guest.handle_chat_page()
        elseif route_type == "dash" then
            -- Guests can't access dashboard
            ngx.log(ngx.INFO, "Guest user attempting to access dashboard, redirecting to /login")
            return ngx.redirect("/login")
        else
            ngx.status = 404
            ngx.say("Unknown guest route: " .. route_type)
            ngx.exit(404)
        end
        
    else
        -- FALLBACK: Something went wrong
        ngx.log(ngx.ERR, "Unknown user state for routing: " .. ngx.var.user_type)
        return ngx.redirect("/login")
    end
end

-- NAVIGATION GENERATOR: Creates nav HTML based on user permissions
function M.generate_nav()
    local user_type, username, user_data = M.set_vars()
    
    if ngx.var.is_admin == "true" then
        return [[
            <nav class="navbar navbar-expand-lg navbar-dark">
                <div class="container-fluid">
                    <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
                    <div class="navbar-nav ms-auto">
                        <a class="nav-link" href="/chat">Chat</a>
                        <a class="nav-link" href="/dash">Admin Dashboard</a>
                        <span class="navbar-text">]] .. username .. [[ (Admin)</span>
                        <button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>
                    </div>
                </div>
            </nav>
        ]]
        
    elseif ngx.var.is_approved == "true" then
        return [[
            <nav class="navbar navbar-expand-lg navbar-dark">
                <div class="container-fluid">
                    <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
                    <div class="navbar-nav ms-auto">
                        <a class="nav-link" href="/chat">Chat</a>
                        <a class="nav-link" href="/dash">Dashboard</a>
                        <span class="navbar-text">]] .. username .. [[</span>
                        <button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>
                    </div>
                </div>
            </nav>
        ]]
        
    elseif user_type == "guest" then
        return [[
            <nav class="navbar navbar-expand-lg navbar-dark">
                <div class="container-fluid">
                    <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
                    <div class="navbar-nav ms-auto">
                        <a class="nav-link" href="/chat">Guest Chat</a>
                        <a class="nav-link" href="/register">Register</a>
                        <span class="navbar-text">]] .. username .. [[</span>
                    </div>
                </div>
            </nav>
        ]]
        
    else
        return [[
            <nav class="navbar navbar-expand-lg navbar-dark">
                <div class="container-fluid">
                    <a class="navbar-brand" href="/"><i class="bi bi-lightning-charge-fill"></i> ai.junder.uk</a>
                    <div class="navbar-nav ms-auto">
                        <a class="nav-link" href="/login">Login</a>
                        <a class="nav-link" href="/register">Register</a>
                    </div>
                </div>
            </nav>
        ]]
    end
end

return M