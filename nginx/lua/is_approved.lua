local function handle_chat_page()
    local is_who = require "is_who"
    local username = is_who.require_approved()
    local template = require "template"
    local login = require "login"
    
    -- Use login module's nav rendering
    local nav_html = login.render_nav_for_user("approved", username, nil)
    
    template.render_template("/usr/local/openresty/nginx/html/app.html", {
        page_title = "Chat",
        username = username,
        css = [[
            <link href="/css/bootstrap.min.css" rel="stylesheet">
            <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
            <link rel="stylesheet" href="/css/common.css">
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        ]],
        nav = nav_html,
        content = [[
            <div class="chat-container">
                <div class="user-features approved-features">
                    <h6><i class="bi bi-check-circle text-success"></i> Full Chat Access</h6>
                    <p>Unlimited messages • Redis storage • Export history</p>
                </div>
                
                <div class="chat-messages" id="chat-messages"></div>
                
                <div class="chat-input-container">
                    <form id="chat-form">
                        <textarea class="form-control chat-input" id="chat-input" 
                                placeholder="Ask anything..." required></textarea>
                        <button type="submit" class="btn btn-primary">
                            <i class="bi bi-send"></i>
                        </button>
                    </form>
                </div>
            </div>
        ]],
        js = [[
            <script src="/js/lib/jquery.min.js"></script>
            <script src="/js/lib/bootstrap.min.js"></script>
            <script src="/js/guest.js"></script>
            <script src="/js/approved.js"></script>
        ]]
    }, 3)
end

local function handle_dash_page()
    local is_who = require "is_who"
    local username = is_who.require_approved()
    local template = require "template"
    local login = require "login"
    
    -- Use login module's nav rendering
    local nav_html = login.render_nav_for_user("approved", username, nil)
    
    template.render_template("/usr/local/openresty/nginx/html/app.html", {
        page_title = "Dashboard",
        username = username,
        css = [[
            <link href="/css/bootstrap.min.css" rel="stylesheet">
            <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
            <link rel="stylesheet" href="/css/common.css">
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        ]],
        nav = nav_html,
        content = [[
            <div class="dashboard-container">
                <div class="dashboard-header">
                    <h2><i class="bi bi-speedometer2"></i> Dashboard</h2>
                    <p>Welcome back, ]] .. username .. [[!</p>
                </div>
                
                <div class="dashboard-content" id="dashboard-content">
                    <!-- Populated by approved.js -->
                </div>
            </div>
        ]],
        js = [[
            <script src="/js/lib/jquery.min.js"></script>
            <script src="/js/lib/bootstrap.min.js"></script>
            <script src="/js/guest.js"></script>
            <script src="/js/approved.js"></script>
        ]]
    }, 3)
end

return {
    handle_chat_page = handle_chat_page,
    handle_dash_page = handle_dash_page
}