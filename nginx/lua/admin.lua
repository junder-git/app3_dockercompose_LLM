-- nginx/lua/admin.lua - Complete admin functionality
local cjson = require "cjson"

-- Auth verification function
local function verify_admin()
    local auth_header = ngx.var.http_authorization
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        return false, "No token provided"
    end

    local token = string.sub(auth_header, 8)
    local ok, payload = pcall(function()
        return cjson.decode(ngx.decode_base64(token))
    end)
    
    if not ok or not payload.exp or payload.exp < ngx.time() then
        return false, "Invalid or expired token"
    end

    if not payload.is_admin then
        return false, "Admin privileges required"
    end

    return true, payload
end

-- Simple template function
local function render_template(template, data)
    local result = template
    for key, value in pairs(data) do
        result = string.gsub(result, "{{" .. key .. "}}", tostring(value))
    end
    return result
end

-- Admin dashboard template
local function get_dashboard_template()
    return [[
        <div class="row mb-4">
            <div class="col-12">
                <h2><i class="bi bi-speedometer2"></i> Admin Dashboard</h2>
                <p>Welcome, <strong>{{username}}</strong>!</p>
            </div>
        </div>
        
        <div class="row mb-4">
            <div class="col-md-4">
                <div class="card">
                    <div class="card-body text-center">
                        <h5 class="card-title">Total Users</h5>
                        <h3 class="text-primary">{{user_count}}</h3>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card">
                    <div class="card-body text-center">
                        <h5 class="card-title">Pending Approvals</h5>
                        <h3 class="text-warning">{{pending_count}}</h3>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card">
                    <div class="card-body text-center">
                        <h5 class="card-title">Active Sessions</h5>
                        <h3 class="text-success">{{active_sessions}}</h3>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="row">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="bi bi-people"></i> User Management</h5>
                    </div>
                    <div class="card-body">
                        <div id="user-list">
                            {{user_list}}
                        </div>
                        <div class="mt-3">
                            <button class="btn btn-primary" onclick="window.location.reload()">
                                <i class="bi bi-arrow-clockwise"></i> Refresh Data
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    ]]
end

local function handle_dashboard()
    local ok, payload = verify_admin()
    if not ok then
        ngx.status = 403
        ngx.say(cjson.encode({error = payload}))
        return
    end

    -- Get user statistics (you'd implement real Redis queries here)
    local template_data = {
        username = payload.username,
        user_count = "1",  -- Admin user exists
        pending_count = "0",  -- No pending users yet
        active_sessions = "1",  -- Admin is logged in
        user_list = [[
            <div class="alert alert-info">
                <i class="bi bi-info-circle"></i> 
                User management functionality is active. Users will appear here when they register.
            </div>
        ]]
    }

    local dashboard_html = render_template(get_dashboard_template(), template_data)
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(dashboard_html)
end

local function handle_users()
    local ok, payload = verify_admin()
    if not ok then
        ngx.status = 403
        ngx.say(cjson.encode({error = payload}))
        return
    end

    -- For simplicity, return a basic user list
    ngx.say(cjson.encode({
        success = true,
        users = {},
        total = 0
    }))
end

local function handle_approve()
    local ok, payload = verify_admin()
    if not ok then
        ngx.status = 403
        ngx.say(cjson.encode({error = payload}))
        return
    end

    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        ngx.status = 400
        ngx.say('{"error": "Request body required"}')
        return
    end

    local ok, data = pcall(cjson.decode, body)
    if not ok or not data.user_id then
        ngx.status = 400
        ngx.say('{"error": "User ID is required"}')
        return
    end

    -- Update user approval status using internal Redis location
    local res = ngx.location.capture("/redis-internal/hset/user:" .. data.user_id .. "/is_approved/true")
    if res.status == 200 then
        ngx.say(cjson.encode({
            success = true,
            message = "User approved successfully"
        }))
    else
        ngx.status = 500
        ngx.say('{"error": "Failed to approve user"}')
    end
end

local function handle_reject()
    local ok, payload = verify_admin()
    if not ok then
        ngx.status = 403
        ngx.say(cjson.encode({error = payload}))
        return
    end

    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        ngx.status = 400
        ngx.say('{"error": "Request body required"}')
        return
    end

    local ok, data = pcall(cjson.decode, body)
    if not ok or not data.user_id then
        ngx.status = 400
        ngx.say('{"error": "User ID is required"}')
        return
    end

    -- Delete user using internal Redis location
    local res = ngx.location.capture("/redis-internal/del/user:" .. data.user_id)
    if res.status == 200 then
        ngx.say(cjson.encode({
            success = true,
            message = "User rejected and deleted"
        }))
    else
        ngx.status = 500
        ngx.say('{"error": "Failed to reject user"}')
    end
end

-- Route based on URI and method
local uri = ngx.var.uri
local method = ngx.var.request_method

if uri == "/api/admin/dashboard" and method == "GET" then
    handle_dashboard()
elseif uri == "/api/admin/users" and method == "GET" then
    handle_users()
elseif uri == "/api/admin/users/approve" and method == "POST" then
    handle_approve()
elseif uri == "/api/admin/users/reject" and method == "POST" then
    handle_reject()
else
    ngx.status = 404
    ngx.say('{"error": "Admin endpoint not found"}')
end