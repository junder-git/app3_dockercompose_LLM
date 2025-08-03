-- =============================================================================
-- nginx/lua/view_chat.lua - CHAT PAGE HANDLER - FIXED
-- =============================================================================

local view_base = require "view_base"

local M = {}

-- =============================================
-- CHAT PAGE HANDLERS
-- =============================================

function M.handle(user_type, username, user_data)
    local display_name = view_base.get_display_username(user_type, username, user_data)
    
    -- Get appropriate page title, placeholder, and body class
    local page_title, chat_placeholder, body_class
    if user_type == "is_admin" then
        page_title = "Admin Chat - ai.junder.uk"
        chat_placeholder = "Admin console ready..."
        body_class = "chat-page admin-chat"
    elseif user_type == "is_approved" then
        page_title = "Chat - ai.junder.uk"
        chat_placeholder = "Ask anything..."
        body_class = "chat-page approved-chat"
    elseif user_type == "is_guest" then
        page_title = "Guest Chat - ai.junder.uk"
        chat_placeholder = "Ask me anything... (Guest: 10 messages, 10 minutes)"
        body_class = "chat-page guest-chat"
    else
        page_title = "Chat - ai.junder.uk"
        chat_placeholder = "Start typing..."
        body_class = "chat-page"
    end
    
    local context = {
        page_title = page_title,
        body_class = body_class,
        chat_features = view_base.get_chat_features(user_type, username, user_data),
        chat_placeholder = chat_placeholder,
        user_data = user_data
    }
    
    view_base.render_page("/usr/local/openresty/nginx/dynamic_content/chat.html", user_type, "chat", context)
end

return M