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
-- MAIN ROUTING HANDLER - HANDLES REDIRECTS AND DELEGATES TO MODULES
-- =====================================================================

function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_vars()
    
    -- Handle Ollama API endpoints first
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
    
    -- NEW ROUTING LOGIC: Based on what each user type can see
    if user_type == "is_admin" or user_type == "is_approved" then
        -- Can see: /chat, /dash, / 
        -- Redirect login/register to dash
        if route_type == "login" or route_type == "register" then
            return ngx.redirect("/dash")
        end
        
    elseif user_type == "is_guest" then
        -- Can see: ALL routes (/, /chat, /dash, /login, /register)
        -- No redirects needed for guests
        
    elseif user_type == "is_pending" then
        -- Can see: /, /dash (pending shows as dash)
        -- Block chat, login, register
        if route_type == "chat" or route_type == "login" or route_type == "register" then
            return ngx.redirect("/dash")
        end
        
    elseif user_type == "is_none" then
        -- Can see: /, /login, /register
        -- Block chat and dash (unless upgrading to guest through available logic)
        if route_type == "chat" or route_type == "dash" then
            return ngx.redirect("/")
        end
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
-- OLLAMA API HANDLERS (KEEP THESE HERE AS THEY'RE CROSS-USER-TYPE)
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
    
    -- Delegate to user-type specific Ollama handler
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
    local MODEL_NAME = os.getenv("MODEL_NAME") or "devstral"
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        object = "list",
        data = {
            {
                id = MODEL_NAME,
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

-- =============================================
-- ERROR PAGE HANDLERS (KEPT IN is_who FOR CENTRAL HANDLING)
-- =============================================

function M.handle_404_page()
    local template = require "manage_template"
    local context = {
        page_title = "404 - Page Not Found",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/404.html", context)
end

function M.handle_429_page()
    local template = require "manage_template"
    local context = {
        page_title = "429 - Guest reached max sessions",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest", 
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/429.html", context)
end

function M.handle_50x_page()
    local template = require "manage_template"
    local context = {
        page_title = "Server Error",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",
        username = "guest",
        dash_buttons = '<a class="nav-link" href="/login">Login</a><a class="nav-link" href="/register">Register</a>'
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/50x.html", context)
end

return M