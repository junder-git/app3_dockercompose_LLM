-- =============================================================================
-- nginx/lua/is_who.lua - RESTRUCTURED: ROUTING ONLY, NO PAGE HANDLERS
-- =============================================================================

local jwt = require "resty.jwt"
local auth = require "manage_auth"
local cjson = require "cjson"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

-- =============================================
-- CORE USER TYPE DETERMINATION
-- =============================================

function M.set_vars()
    local user_type, username, guest_slot_number, user_data = auth.check()
    ngx.var.username = username or "guest"
    ngx.var.user_type = user_type or "is_none"
    ngx.var.guest_slot_number = guest_slot_number or "1"    
    
    if user_type == "is_guest" and user_data and user_data.guest_slot_number then
        local ok, err = pcall(function()
            ngx.var.guest_slot_number = tostring(user_data.guest_slot_number)
        end)
        if not ok then 
            ngx.log(ngx.WARN, "Failed to set guest_slot_id: " .. err) 
        end
    end    
    
    return user_type, username, user_data
end

-- =============================================
-- ACCESS CONTROL HELPERS
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
    if user_type ~= "is_guest" then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    if not user_data or not user_data.guest_slot_number then
        ngx.status = 403
        return ngx.exec("@custom_50x")
    end
    return username, user_data
end

function M.get_user_info()
    local user_type, username, user_data = auth.check()
    
    if user_type == "is_none" then
        return { success = false, user_type = "is_none", authenticated = false, message = "Not authenticated" }
    end
    
    local response = {
        success = true,
        username = username,
        user_type = user_type,
        authenticated = true
    }
    
    if user_type == "is_guest" and user_data then
        response.message_limit = user_data.max_messages or 10
        response.messages_used = user_data.message_count or 0
        response.messages_remaining = (user_data.max_messages or 10) - (user_data.message_count or 0)
        response.session_remaining = (user_data.expires_at or 0) - ngx.time()
        response.guest_slot_number = user_data.guest_slot_number
        response.priority = user_data.priority or 3
    end
    
    return response
end

-- =====================================================================
-- MAIN ROUTING HANDLER - DELEGATES TO APPROPRIATE MODULES
-- =====================================================================

function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_vars()
    
    -- Handle ollama API endpoints first
    if route_type == "ollama_chat_api" then
        M.handle_ollama_chat_api()
        return
    elseif route_type == "ollama_models_api" then
        M.handle_ollama_models_api()
        return
    elseif route_type == "ollama_completions_api" then
        M.handle_ollama_completions_api()
        return
    end
    
    -- Route to user-type specific handlers
    if ngx.var.user_type == "is_admin" then
        local is_admin = require "is_admin"
        is_admin.handle_route(route_type)
        
    elseif ngx.var.user_type == "is_approved" then
        local is_approved = require "is_approved"
        is_approved.handle_route(route_type)
        
    elseif ngx.var.user_type == "is_guest" then
        local is_guest = require "is_guest"
        is_guest.handle_route(route_type)
        
    elseif ngx.var.user_type == "is_pending" then
        local is_pending = require "is_pending"
        is_pending.handle_route(route_type)
        
    elseif ngx.var.user_type == "is_none" then
        local is_none = require "is_none"
        is_none.handle_route(route_type)
        
    else
        ngx.log(ngx.ERROR, "Unknown user type: " .. ngx.var.user_type)
        return ngx.redirect("/login")
    end
end

-- =====================================================================
-- ollama API HANDLERS (KEEP THESE HERE AS THEY'RE CROSS-USER-TYPE)
-- =====================================================================

function M.handle_ollama_chat_api()
    local user_type, username, user_data = M.set_vars()
    
    if user_type == "is_none" then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    end
    
    -- Delegate to user-type specific ollama handler
    if user_type == "is_admin" then
        local is_admin = require "is_admin"
        is_admin.handle_ollama_chat_stream()
    elseif user_type == "is_approved" then
        local is_approved = require "is_approved"
        is_approved.handle_ollama_chat_stream()
    elseif user_type == "is_guest" then
        local is_guest = require "is_guest"
        is_guest.handle_ollama_chat_stream()
    else
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Invalid user type"
        }))
        return ngx.exit(403)
    end
end

function M.handle_ollama_models_api()
    local user_type, username, user_data = M.set_vars()
    
    if user_type == "is_none" then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    end
    
    -- Simple models endpoint - return available model info
    local ollama_MODEL = os.getenv("ollama_MODEL") or "devstral"
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        object = "list",
        data = {
            {
                id = ollama_MODEL,
                object = "model",
                created = ngx.time(),
                owned_by = "ai.junder.uk"
            }
        }
    }))
end

function M.handle_ollama_completions_api()
    local user_type, username, user_data = M.set_vars()
    
    if user_type == "is_none" then
        ngx.status = 401
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Authentication required",
            message = "Please login or start a guest session"
        }))
        return ngx.exit(401)
    end
    
    -- Delegate to user-type specific completions handler
    if user_type == "is_admin" then
        local is_admin = require "is_admin"
        is_admin.handle_ollama_completions_stream()
    elseif user_type == "is_approved" then
        local is_approved = require "is_approved"
        is_approved.handle_ollama_completions_stream()
    elseif user_type == "is_guest" then
        local is_guest = require "is_guest"
        is_guest.handle_ollama_completions_stream()
    else
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Invalid user type"
        }))
        return ngx.exit(403)
    end
end

-- =============================================
-- SIMPLE API ROUTING FUNCTIONS (DELEGATES ONLY)
-- =============================================

function M.handle_auth_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/auth/login" and method == "POST" then
        auth.handle_login()
    elseif uri == "/api/auth/logout" and method == "POST" then
        auth.handle_logout()
    elseif uri == "/api/auth/check" and method == "GET" then
        auth.handle_check_auth()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "Auth endpoint not found" }))
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
    local is_guest = require "is_guest"
    is_guest.handle_guest_api()
end

return M