local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
    if not ok then
        send_json(500, { error = "Internal server error", details = "Redis connection failed" })
    end
    return red
end

local function verify_admin_token()
    local token = ngx.var.cookie_access_token
    if not token then
        send_json(401, { error = "Authentication required" })
    end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then
        send_json(401, { error = "Invalid token" })
    end

    local username = jwt_obj.payload.username
    
    -- Get user info from Redis to verify admin status
    local red = connect_redis()
    local user_key = "user:" .. username
    local user_data = red:hgetall(user_key)
    
    if not user_data or #user_data == 0 then
        send_json(401, { error = "User not found" })
    end

    local user = {}
    for i = 1, #user_data, 2 do
        user[user_data[i]] = user_data[i + 1]
    end

    if user.is_admin ~= "true" then
        send_json(403, { error = "Admin privileges required" })
    end

    return username, red
end

local function handle_approve_user()
    local admin_username, red = verify_admin_token()
    
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

    local user_key = "user:" .. username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        send_json(404, { error = "User not found" })
    end

    -- Update user approval status
    red:hset(user_key, "is_approved", "true")
    red:hset(user_key, "approved_by", admin_username)
    red:hset(user_key, "approved_at", os.date("!%Y-%m-%dT%TZ"))

    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " approved user ", username)

    send_json(200, { 
        success = true, 
        message = "User approved successfully",
        username = username
    })
end

local function handle_approve_all()
    local admin_username, red = verify_admin_token()
    
    -- Get all pending users
    local user_keys = red:keys("user:*")
    local approved_count = 0
    
    for _, key in ipairs(user_keys) do
        if key ~= "user:" then
            local user_data = red:hgetall(key)
            local user = {}
            for i = 1, #user_data, 2 do
                user[user_data[i]] = user_data[i + 1]
            end
            
            if user.is_approved ~= "true" then
                red:hset(key, "is_approved", "true")
                red:hset(key, "approved_by", admin_username)
                red:hset(key, "approved_at", os.date("!%Y-%m-%dT%TZ"))
                approved_count = approved_count + 1
            end
        end
    end

    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " approved ", approved_count, " users")

    send_json(200, { 
        success = true, 
        message = approved_count .. " users approved successfully",
        count = approved_count
    })
end

local function handle_delete_user()
    local admin_username, red = verify_admin_token()
    
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

    -- Prevent admin from deleting themselves
    if username == admin_username then
        send_json(400, { error = "Cannot delete your own account" })
    end

    local user_key = "user:" .. username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        send_json(404, { error = "User not found" })
    end

    -- Delete user and related data
    red:del(user_key)
    
    -- Delete user message counts and related data
    local today = os.date("%Y-%m-%d")
    local message_keys = red:keys("user_messages:" .. username .. ":*")
    for _, key in ipairs(message_keys) do
        red:del(key)
    end

    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " deleted user ", username)

    send_json(200, { 
        success = true, 
        message = "User deleted successfully",
        username = username
    })
end

local function handle_toggle_admin()
    local admin_username, red = verify_admin_token()
    
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

    -- Prevent admin from removing their own admin status
    if username == admin_username then
        send_json(400, { error = "Cannot modify your own admin status" })
    end

    local user_key = "user:" .. username
    local user_exists = red:exists(user_key)
    
    if user_exists == 0 then
        send_json(404, { error = "User not found" })
    end

    -- Get current admin status
    local current_admin_status = red:hget(user_key, "is_admin")
    local new_admin_status = (current_admin_status == "true") and "false" or "true"
    
    -- Update admin status
    red:hset(user_key, "is_admin", new_admin_status)
    red:hset(user_key, "admin_modified_by", admin_username)
    red:hset(user_key, "admin_modified_at", os.date("!%Y-%m-%dT%TZ"))

    local action = (new_admin_status == "true") and "granted" or "revoked"
    
    -- Log the action
    ngx.log(ngx.ERR, "Admin ", admin_username, " ", action, " admin privileges for user ", username)

    send_json(200, { 
        success = true, 
        message = "Admin status " .. action .. " successfully",
        username = username,
        is_admin = new_admin_status == "true"
    })
end

-- Route handler function
local function handle_admin_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/admin/approve-user" and method == "POST" then
        handle_approve_user()
    elseif uri == "/api/admin/approve-all" and method == "POST" then
        handle_approve_all()
    elseif uri == "/api/admin/delete-user" and method == "DELETE" then
        handle_delete_user()
    elseif uri == "/api/admin/toggle-admin" and method == "POST" then
        handle_toggle_admin()
    else
        send_json(404, { error = "Admin API endpoint not found" })
    end
end

return {
    handle_admin_api = handle_admin_api,
    handle_approve_user = handle_approve_user,
    handle_approve_all = handle_approve_all,
    handle_delete_user = handle_delete_user,
    handle_toggle_admin = handle_toggle_admin
}