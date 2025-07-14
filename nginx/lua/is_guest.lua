local function handle_chat_page()
    local user_type, username = is_who.set_vars()
    local template = require "template"
    
    if user_type ~= "guest" then
        username = "Anonymous"
    end
    
    template.render_template("/usr/local/openresty/nginx/html/app.html", {
        page_title = "Guest Chat",
        username = username,
        css = template.read_partial("/usr/local/openresty/nginx/html/partials/css.html"),
        nav = template.read_partial("/usr/local/openresty/nginx/html/partials/nav_guest.html"),
        content = template.read_partial("/usr/local/openresty/nginx/html/partials/chat_guest.html"),
        js = [[
            <script src="/js/lib/jquery.min.js"></script>
            <script src="/js/lib/bootstrap.min.js"></script>
            <script src="/js/guest.js"></script>
        ]]
    }, 3)  -- Template depth 3
end

return {
    handle_chat_page = handle_chat_page
}
