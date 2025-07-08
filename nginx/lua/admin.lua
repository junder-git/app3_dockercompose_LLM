-- nginx/lua/admin.lua - OpenResty Lua admin functionality
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

local function handle_dashboard()
    local ok, payload = verify_admin()
    if not ok then
        ngx.status = 403
        ngx.say(cjson.encode({error = payload}))
        return
    end

    -- Simple admin dashboard HTML
    local dashboard_html = [[
        <div class="row mb-4">
            <div class="col-12">
                <h2><i class="bi bi-speedometer2"></i> Admin Dashboard</h2>
            </div>
        </div>
        
        <div class="row mb-4">
            <div class="col-md-3">
                <div class="card">
                    <div class="card-body text-center">
                        <h5 class="card-title">Admin Panel</h5>
                        <p class="card-text">Manage users and system settings.</p>
                    </div>
                </div>
            </div>
            <div class="col-md-9">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="bi bi-info-circle"></i> System Status</h5>
                    </div>
                    <div class="card-body">
                        <p>Admin functionality is active. Use the API endpoints to manage users:</p>
                        <ul>
                            <li><code>GET /api/admin/users</code> - List all users</li>
                            <li><code>POST /api/admin/users/approve</code> - Approve a user</li>
                            <li><code>POST /api/admin/users/reject</code> - Reject a user</li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
    ]]

    ngx.header.content_type = "text/html"
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
    -- In production, you'd implement proper Redis scanning
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

    -- Update user approval status
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

    -- Delete user
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