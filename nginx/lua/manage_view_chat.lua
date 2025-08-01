-- =============================================================================
-- nginx/lua/manage_view_chat.lua - CHAT PAGE HANDLER
-- =============================================================================

local view_base = require "manage_view_base"

local M = {}

-- =============================================
-- CHAT PAGE HANDLERS
-- =============================================

function M.handle(user_type, username, user_data)
    local display_name = view_base.get_display_username(user_type, username, user_data)
    
    -- Get appropriate page title and placeholder
    local page_title, chat_placeholder
    if user_type == "is_admin" then
        page_title = "Admin Chat - ai.junder.uk"
        chat_placeholder = "Admin console ready..."
    elseif user_type == "is_approved" then
        page_title = "Chat - ai.junder.uk"
        chat_placeholder = "Ask anything..."
    elseif user_type == "is_guest" then
        page_title = "Guest Chat - ai.junder.uk"
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 10 minutes)"
    else
        page_title = "Chat - ai.junder.uk"
        chat_placeholder = "Start typing..."
    end
    
    local context = {
        page_title = page_title,
        chat_features = view_base.get_chat_features(user_type, username, user_data),
        chat_placeholder = chat_placeholder,
        user_data = user_data
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/chat.html", user_type, "chat", context)
end

return M