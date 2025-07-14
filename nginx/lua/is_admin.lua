-- nginx/lua/is_admin.lua - SECURE admin interface using nav.html template
local cjson = require "cjson"
local template = require "template"
local server = require "server"
local is_who = require "is_who"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- SECURE: Admin page only served to verified admins
local function handle_admin_page()
    -- CRITICAL: Server-side admin verification
    local username = is_who.require_admin()
    
    ngx.log(ngx.INFO, "Admin dashboard access granted to: " .. username)
    
    -- Build admin navigation using nav.html template
    local nav_links = [[
<a class="nav-link" href="/admin"><i class="bi bi-gear"></i> Admin</a>
<a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Chat</a>
<a class="nav-link" href="/dashboard"><i class="bi bi-speedometer2"></i> Dashboard</a>
]]

    local nav_user = string.format([[
<span class="navbar-text me-3">%s (Admin)</span>
<button class="btn btn-outline-light btn-sm" onclick="DevstralCommon.logout()"><i class="bi bi-box-arrow-right"></i> Logout</button>
]], username)

    template.render_template("/usr/local/openresty/nginx/html/dashboard.html", {
        nav_links = nav_links,
        nav_user = nav_user
    })
end

-- SECURE: Admin data only for verified admins
local function handle_get_users()
    -- CRITICAL: Server-side admin verification
    local admin_username = is_who.require_admin()
    
    -- Only admins can see user list
    local users = server.get_all_users()
    
    -- Format for frontend (admin gets full data)
    local formatted_users = {}
    for _, user in ipairs(users) do
        table.insert(formatted_users, {
            username = user.username,
            isApproved = user.is_approved == "true",
            isAdmin = user.is_admin == "true",
            createdAt = user.created_at or "Unknown",
            lastActive = user.last_active,
            approvedBy = user.approved_by,
            approvedAt = user.approved_at,
            -- Admin-only fields
            last_ip = user.last_ip,
            login_count = user.login_count or "0"
        })
    end
    
    ngx.log(ngx.INFO, "Admin " .. admin_username .. " accessed user list (" .. #formatted_users .. " users)")
    
    send_json(200, {
        success = true,
        users = formatted_users,
        count = #formatted_users,
        admin_user = admin_username,
        server_time = os.date("!%Y-%m-%dT%TZ"),
        permissions = {"admin", "manage_users", "view_all_data"}
    })
end

-- SECURE: Admin stats only for verified admins
local function handle_get_stats()
    -- CRITICAL: Server-side admin verification
    local admin_username = is_who.require_admin()
    
    local users = server.get_all_users()
    local sse_stats = server.get_sse_stats()
    
    local stats = {
        totalUsers = 0,
        pendingUsers = 0,
        approvedUsers = 0,
        adminUsers = 0,
        todayLogins = 0,
        activeToday = 0
    }
    
    local today = os.date("!%Y-%m-%d")
    
    for _, user in ipairs(users) do
        stats.totalUsers = stats.totalUsers + 1
        
        if user.is_admin == "true" then
            stats.adminUsers = stats.adminUsers + 1
        elseif user.is_approved == "true" then
            stats.approvedUsers = stats.approvedUsers + 1
        else
            stats.pendingUsers = stats.pendingUsers + 1
        end
        
        -- Check if user was active today
        if user.last_active and string.find(user.last_active, today) then
            stats.activeToday = stats.activeToday + 1
        end
    end
    
    ngx.log(ngx.INFO, "Admin " .. admin_username .. " accessed system stats")
    
    send_json(200, {
        success = true,
        stats = stats,
        sse_stats = sse_stats,
        admin_user = admin_username,
        server_info = {
            uptime = ngx.time(),
            memory_usage = collectgarbage("count"),
            nginx_version = ngx.var.nginx_version
        },
        permissions = {"admin", "view_stats", "system_info"}
    })
end

-- SECURE: Only admins can approve users
local function handle_approve_user()
    -- CRITICAL: Server-side admin verification
    local admin_username = is_who.require_admin()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username

    if not username then
        send_json(400, { error = "Username required" })
    end

    local success, message = server.approve_user(username, admin_username)
    
    if not success then
        send_json(404, { error = message })
    end

    ngx.log(ngx.INFO, "Admin " .. admin_username .. " approved user " .. username)

    send_json(200, { 
        success = true, 
        message = "User approved successfully",
        username = username,
        approved_by = admin_username,
        approved_at = os.date("!%Y-%m-%dT%TZ")
    })
end

-- SECURE: Only admins can toggle admin status
local function handle_toggle_admin()
    -- CRITICAL: Server-side admin verification
    local admin_username = is_who.require_admin()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username

    if not username then
        send_json(400, { error = "Username required" })
    end

    if username == admin_username then
        send_json(400, { error = "Cannot modify your own admin status" })
    end

    local success, message, is_admin = server.toggle_admin(username, admin_username)
    
    if not success then
        send_json(404, { error = message })
    end

    local action = is_admin and "granted" or "revoked"
    ngx.log(ngx.INFO, "Admin " .. admin_username .. " " .. action .. " admin privileges for " .. username)

    send_json(200, { 
        success = true, 
        message = "Admin status " .. action .. " successfully",
        username = username,
        is_admin = is_admin,
        modified_by = admin_username,
        modified_at = os.date("!%Y-%m-%dT%TZ")
    })
end

-- SECURE: Only admins can delete users
local function handle_delete_user()
    -- CRITICAL: Server-side admin verification
    local admin_username = is_who.require_admin()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username

    if not username then
        send_json(400, { error = "Username required" })
    end

    if username == admin_username then
        send_json(400, { error = "Cannot delete your own account" })
    end

    local success, message = server.delete_user(username)
    
    if not success then
        send_json(404, { error = message })
    end

    ngx.log(ngx.INFO, "Admin " .. admin_username .. " deleted user " .. username)

    send_json(200, { 
        success = true, 
        message = "User deleted successfully",
        username = username,
        deleted_by = admin_username,
        deleted_at = os.date("!%Y-%m-%dT%TZ")
    })
end

-- SECURE: Admin SSE session management
local function handle_get_sse_sessions()
    -- CRITICAL: Server-side admin verification
    local admin_username = is_who.require_admin()
    
    local sessions, count, max_sessions = server.get_all_sse_sessions()
    
    ngx.log(ngx.INFO, "Admin " .. admin_username .. " accessed SSE sessions (" .. count .. " active)")
    
    send_json(200, {
        success = true,
        sessions = sessions,
        count = count,
        max_sessions = max_sessions,
        admin_user = admin_username,
        server_time = os.date("!%Y-%m-%dT%TZ"),
        permissions = {"admin", "manage_sessions"}
    })
end

-- SECURE: Admin can kick SSE sessions
local function handle_kick_sse_session()
    -- CRITICAL: Server-side admin verification
    local admin_username = is_who.require_admin()
    
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local session_id = data.session_id

    if not session_id then
        send_json(400, { error = "Session ID required" })
    end

    local success, message = server.kick_sse_session(session_id, admin_username)
    
    if not success then
        send_json(404, { error = message })
    end

    ngx.log(ngx.INFO, "Admin " .. admin_username .. " kicked SSE session " .. session_id)

    send_json(200, { 
        success = true, 
        message = message,
        session_id = session_id,
        kicked_by = admin_username,
        kicked_at = os.date("!%Y-%m-%dT%TZ")
    })
end

-- SECURE API ROUTING - only admin endpoints
local function handle_admin_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/admin/users" and method == "GET" then
        handle_get_users()
    elseif uri == "/api/admin/stats" and method == "GET" then
        handle_get_stats()
    elseif uri == "/api/admin/approve-user" and method == "POST" then
        handle_approve_user()
    elseif uri == "/api/admin/toggle-admin" and method == "POST" then
        handle_toggle_admin()
    elseif uri == "/api/admin/delete-user" and method == "DELETE" then
        handle_delete_user()
    elseif uri == "/api/admin/sse-sessions" and method == "GET" then
        handle_get_sse_sessions()
    elseif uri == "/api/admin/kick-sse" and method == "POST" then
        handle_kick_sse_session()
    else
        send_json(404, { error = "Admin API endpoint not found" })
    end
end

return {
    handle_admin_page = handle_admin_page,
    handle_admin_api = handle_admin_api
}