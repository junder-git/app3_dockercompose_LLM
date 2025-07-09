-- nginx/lua/admin.lua - Updated with simple templating
local cjson = require "cjson"

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
                <p>Welcome, {{username}}!</p>
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

    -- Get user statistics (simplified)
    local template_data = {
        username = payload.username,
        user_count = "5",  -- You'd get this from Redis
        pending_count = "2",  -- You'd get this from Redis
        active_sessions = "3",  -- You'd get this from Redis
        user_list = "<p>User list would go here...</p>"
    }

    local dashboard_html = render_template(get_dashboard_template(), template_data)
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(dashboard_html)
end