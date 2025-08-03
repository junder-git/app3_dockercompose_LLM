-- =============================================================================
-- nginx/lua/view_error.lua - ERROR PAGE HANDLERS - FIXED
-- =============================================================================

local view_base = require "view_base"

local M = {}

-- =============================================
-- ERROR PAGE HANDLERS
-- =============================================

function M.handle_404()
    local context = {
        page_title = "404 - Page Not Found",
        user_data = nil
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/404.html", "is_none", "error", context)
end

function M.handle_429()
    local context = {
        page_title = "429 - Guest Slots Full",
        user_data = nil
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/429.html", "is_none", "error", context)
end

function M.handle_50x()
    local context = {
        page_title = "Server Error",
        user_data = nil
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/50x.html", "is_none", "error", context)
end

return M