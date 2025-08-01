-- =============================================================================
-- nginx/lua/manage_view_auth.lua - AUTH PAGES HANDLER
-- =============================================================================

local view_base = require "manage_view_base"

local M = {}

-- =============================================
-- LOGIN PAGE HANDLER
-- =============================================

function M.handle_login(user_type, username, user_data)
    local context = {
        page_title = "Login - ai.junder.uk",
        auth_title = "Sign In",
        auth_subtitle = "Welcome back to ai.junder.uk",
        user_data = user_data
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/login.html", user_type, "auth", context)
end

-- =============================================
-- REGISTER PAGE HANDLER
-- =============================================

function M.handle_register(user_type, username, user_data)
    local context = {
        page_title = "Register - ai.junder.uk",
        auth_title = "Create Account",
        auth_subtitle = "Join ai.junder.uk today",
        user_data = user_data
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/register.html", user_type, "auth", context)
end

return M