local function handle_chat_page()
    local username = is_who.require_admin()
    local template = require "template"
    
    template.render_template("/usr/local/openresty/nginx/html/app.html", {
        page_title = "Admin Chat",
        username = username,
        css = template.read_partial("/usr/local/openresty/nginx/html/partials/css.html"),
        nav = template.read_partial("/usr/local/openresty/nginx/html/partials/nav_admin.html"),
        content = template.read_partial("/usr/local/openresty/nginx/html/partials/chat_admin.html"),
        js = [[
            <script src="/js/lib/jquery.min.js"></script>
            <script src="/js/lib/bootstrap.min.js"></script>
            <script src="/js/guest.js"></script>
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]]
    }, 3)  -- Template depth 3
end

local function handle_dash_page()
    local username = is_who.require_admin()
    local template = require "template"
    
    template.render_template("/usr/local/openresty/nginx/html/app.html", {
        page_title = "Admin Dashboard",
        username = username,
        css = template.read_partial("/usr/local/openresty/nginx/html/partials/css.html"),
        nav = template.read_partial("/usr/local/openresty/nginx/html/partials/nav_admin.html"),
        content = template.read_partial("/usr/local/openresty/nginx/html/partials/dash_admin.html"),
        js = [[
            <script src="/js/lib/jquery.min.js"></script>
            <script src="/js/lib/bootstrap.min.js"></script>
            <script src="/js/guest.js"></script>
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]]
    }, 3)  -- Template depth 3
end

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page
}