local function handle_chat_page()
    local username = is_who.require_admin()
    local template = require "template"
    
    -- Read the single nav partial
    local nav = template.read_partial("/usr/local/openresty/nginx/html/partials/nav.html")
    
    template.render_template("/usr/local/openresty/nginx/html/app.html", {
        username = username,
        nav = nav,
        
        -- Nav content based on is_who variables (admin gets ALL)
        if_admin_nav = '<a class="nav-link" href="/dash">Admin Dashboard</a>',
        if_approved_nav = '<a class="nav-link" href="/dash">Dashboard</a><a class="nav-link" href="/chat">Chat</a>',
        if_guest_nav = '',  -- Admin doesn't need guest nav
        user_badge = ' (Admin)',
        auth_buttons = '<button class="btn btn-outline-light btn-sm ms-2" onclick="logout()">Logout</button>',
        
        -- Rest of template data...
        css = template.read_partial("/usr/local/openresty/nginx/html/partials/css.html"),
        content = template.read_partial("/usr/local/openresty/nginx/html/partials/chat_admin.html"),
        js = [[
            <script src="/js/lib/jquery.min.js"></script>
            <script src="/js/lib/bootstrap.min.js"></script>
            <script src="/js/guest.js"></script>
            <script src="/js/approved.js"></script>
            <script src="/js/admin.js"></script>
        ]]
    }, 3)
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