-- =============================================================================
-- nginx/lua/manage_view_index.lua - INDEX PAGE HANDLER
-- =============================================================================

local view_base = require "manage_view_base"

local M = {}

-- =============================================
-- INDEX PAGE HANDLER
-- =============================================

function M.handle(user_type, username, user_data)
    -- Different start chat button based on user type
    local start_chat_button = ""
    if user_type == "is_none" then
        start_chat_button = [[
            <button class="btn btn-primary btn-lg me-3" onclick="startGuestSession()">
                <i class="bi bi-chat-dots"></i> Start Guest Chat
            </button>
        ]]
    else
        start_chat_button = [[
            <a href="/chat" class="btn btn-primary btn-lg me-3">
                <i class="bi bi-chat-dots"></i> Start Chat
            </a>
        ]]
    end
    
    local context = {
        page_title = "ai.junder.uk - Advanced AI Chat",
        body_class = "index-page",  -- Add CSS class for index page styling
        start_chat_button = start_chat_button,
        user_data = user_data
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/index.html", user_type, "index", context)
end

return M