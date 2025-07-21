local function handle_chat_page()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_approved()
    local context = {
        page_title = "Chat",
        nav = is_who.render_nav("approved", username, nil),
        chat_features = is_who.get_chat_features("approved"),
        chat_placeholder = "Ask anything..."
    }
    template.render_template("/usr/local/openresty/nginx/dynamic_content/chat.html", context)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local template = require "template"
    local username = is_who.require_approved()
    
    local context = {
        page_title = "Approved Dashboard - ai.junder.uk",
        nav = "/usr/local/openresty/nginx/dynamic_content/nav.html",  -- Smart partial
        username = username or "guest",  -- Nav context
        dash_buttons = is_who.get_nav_buttons("is_approved", username, nil),  -- Nav context
        dashboard_content = is_who.get_dashboard_content("is_approved", username)
    }
    
    template.render_template("/usr/local/openresty/nginx/dynamic_content/dash.html", context)
end

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page
}