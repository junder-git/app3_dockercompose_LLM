-- =============================================================================
-- nginx/lua/aaa_is_who.lua - CENTRALIZED CHAT API ROUTING
-- =============================================================================

local jwt = require "resty.jwt"
local auth = require "manage_auth"
local views = require "manage_views"
local cjson = require "cjson"
local manage_chat = require "manage_chat"

local JWT_SECRET = os.getenv("JWT_SECRET")

local M = {}

-- =============================================
-- CORE USER TYPE DETERMINATION - NO CHANGES NEEDED
-- =============================================

function M.set_user()
    local user_type, username, user_data = auth.check()
    if user_type == "is_admin" or user_type == "is_approved" or user_type == "is_pending" or user_type == "is_guest" then
       return user_type, username, user_data
    else
        username = "guest"
        user_type = "is_none"
    end
    return user_type, username, user_data
end

 err = chat_history.search_history(username, query)
    
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Search failed: " .. err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        query = query,
        results = results,
        result_count = #results,
        user_type = user_type
    }))
end

-- Chat Stats Handler
local function handle_chat_stats(user_type, username, user_data)
    if user_type ~= "is_approved" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat stats only available for approved users"
        }))
        return ngx.exit(403)
    end
    
    local stats, err = chat_history.get_user_stats(username)
    
    if err then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to get stats: " .. err
        }))
        return
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        stats = stats,
        user_type = user_type
    }))
end

-- Chat Stream Handler
local function handle_chat_stream(user_type, username, user_data)
    if user_type ~= "is_admin" and user_type ~= "is_approved" and user_type ~= "is_guest" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Chat streaming not available for " .. user_type
        }))
        return ngx.exit(403)
    end
    
    -- Use shared Ollama streaming
    local stream_ollama = require "manage_stream_ollama"
    
    -- Set different limits based on user type
    local max_tokens = 2048  -- Default for guests
    if user_type == "is_admin" then
        max_tokens = tonumber(os.getenv("MODEL_NUM_PREDICT")) or 4096
    elseif user_type == "is_approved" then
        max_tokens = 3072
    end
    
    local stream_context = {
        user_type = user_type,
        username = username,
        user_data = user_data,
        include_history = (user_type == "is_admin" or user_type == "is_approved"),
        history_limit = (user_type == "is_admin" and 100) or (user_type == "is_approved" and 50) or 0,
        default_options = {
            model = os.getenv("MODEL_NAME") or "devstral",
            temperature = tonumber(os.getenv("MODEL_TEMPERATURE")) or 0.7,
            max_tokens = max_tokens
        },
        -- Save messages to Redis for admin and approved users
        on_user_message = function(message)
            if user_type == "is_admin" or user_type == "is_approved" then
                chat_history.save_message(username, "user", message)
            end
        end,
        on_assistant_message = function(message)
            if user_type == "is_admin" or user_type == "is_approved" then
                chat_history.save_message(username, "assistant", message)
            end
        end
    }
    
    return stream_ollama.handle_chat_stream_common(stream_context)
end

-- Guest Session Creation Handler
local function handle_create_guest_session()
    -- Import guest session logic from is_none
    local ADJECTIVES = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural", "Cosmic"}
    local ANIMALS = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}
    
    local function generate_guest_name()
        local adjective = ADJECTIVES[math.random(#ADJECTIVES)]
        local animal = ANIMALS[math.random(#ANIMALS)]
        local number = math.random(100, 999)
        return adjective .. animal .. number
    end
    
    local now = ngx.time()
    local slot_number = 1
    local guest_username = "guest_user_" .. slot_number
    local display_name = generate_guest_name()
    
    -- Create JWT token with client-facing data
    local payload = {
        display_username = display_name,
        last_activity = now
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    ngx.log(ngx.INFO, "✅ Guest session created: " .. display_name .. " -> " .. guest_username .. " (slot " .. slot_number .. ")")
    
    -- Set cookie and return response
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600"
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        username = display_name,
        internal_username = guest_username,
        token = token,
        slot = slot_number,
        redirect = "/chat"
    }))
end

-- =====================================================================
-- MAIN ROUTING HANDLER - UPDATED FOR CENTRALIZED ROUTING
-- =====================================================================
function M.route_to_handler(route_type)
    local user_type, username, user_data = M.set_user()
    
    -- Handle Ollama API endpoints first
    if route_type == "ollama_chat_api" then
        M.handle_ollama_chat_api()
        return
    end
    
    -- Handle guest session creation for is_none users - delegate to is_guest module
    if route_type == "create_guest_session" and user_type == "is_none" then
        local is_guest = require "is_guest"
        return is_guest.handle_create_guest_session()
    end
    
    -- ROUTING LOGIC: Based on what each user type can see, using views module
    if user_type == "is_admin" then
        -- Can see: /chat, /dash, / 
        -- Redirect login/register to chat
        if route_type == "login" or route_type == "register" then
            return ngx.redirect("/chat")
        end
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        elseif route_type == "chat" then
            return views.handle_chat_page_admin()
        elseif route_type == "dash" then
            return views.handle_dash_page_admin()
        else
            -- Return 404 for unknown routes
            ngx.status = 404
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Route not found",
                route = route_type,
                user_type = user_type
            }))
        end        
    elseif user_type == "is_approved" then
        -- Can see: /chat, / 
        if route_type == "dash" then
            return ngx.redirect("/")
        end
        if route_type == "login" or route_type == "register" then
            return ngx.redirect("/chat")
        end
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        elseif route_type == "chat" then
            return views.handle_chat_page_approved()
        else
            ngx.status = 404
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Route not found",
                route = route_type,
                user_type = user_type
            }))
        end
    elseif user_type == "is_pending" then
        -- Can see: / only
        if route_type == "chat" or route_type == "dash" then
            return ngx.redirect("/")
        end
        if route_type == "login" or route_type == "register" then
            return ngx.redirect("/")
        end
        -- Route to appropriate view handler
        if route_type == "index" then
            return views.handle_index_page()
        else
            ngx.status = 404
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Route not found",
                route = route_type,
                user_type = user_type
            }))
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
            ngx.status = 404
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Route not found",
                route = route_type,
                user_type = user_type
            }))
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
            ngx.status = 404
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                error = "Route not found",
                route = route_type,
                user_type = user_type
            }))
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
-- CENTRALIZED CHAT API ROUTING - ALL ENDPOINTS HANDLED HERE
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
    
    -- CENTRALIZED ROUTING: Handle all chat endpoints here - delegate to manage_chat module
    if uri == "/api/chat/history" and method == "GET" then
        manage_chat.handle_chat_history(user_type, username, user_data)
        
    elseif uri == "/api/chat/clear" and method == "POST" then
        manage_chat.handle_clear_chat(user_type, username, user_data)
        
    elseif uri == "/api/chat/export" and method == "GET" then
        manage_chat.handle_export_chat(user_type, username, user_data)
        
    elseif uri == "/api/chat/search" and method == "GET" then
        manage_chat.handle_search_chat(user_type, username, user_data)
        
    elseif uri == "/api/chat/stats" and method == "GET" then
        manage_chat.handle_chat_stats(user_type, username, user_data)
        
    elseif uri == "/api/chat/stream" and method == "POST" then
        manage_chat.handle_chat_stream(user_type, username, user_data)
        -- Unknown chat endpoint
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            error = "Chat API endpoint not found",
            requested = method .. " " .. uri,
            user_type = user_type,
            available_endpoints = {
                "GET /api/chat/history - Chat history (admin/approved)",
                "POST /api/chat/clear - Clear chat (admin/approved)",
                "GET /api/chat/export - Export chat (admin/approved)",
                "GET /api/chat/search - Search chat (admin/approved)",
                "GET /api/chat/stats - Chat stats (approved)",
                "POST /api/chat/stream - Chat streaming (admin/approved/guest)"
            }
        }))
        return ngx.exit(404)
    end
end

function M.handle_auth()
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

return M