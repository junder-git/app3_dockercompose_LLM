-- nginx/lua/init.lua - System initialization with environment variables
local cjson = require "cjson"

-- Get admin credentials from environment variables
local admin_username = os.getenv("ADMIN_USERNAME") or "admin"
local admin_password = os.getenv("ADMIN_PASSWORD") or "admin"
local admin_user_id = os.getenv("ADMIN_USER_ID") or "admin"

-- Log the values being used
ngx.log(ngx.ERR, "Init: Checking admin user: " .. admin_username .. " with ID: " .. admin_user_id)

-- Check if admin user exists
local res = ngx.location.capture("/redis-internal/exists/user:" .. admin_username)
if res.status == 200 and res.body:match("1") then
    ngx.log(ngx.ERR, "Init: Admin user '" .. admin_username .. "' already exists")
    ngx.say(cjson.encode({
        success = true,
        message = "Admin user '" .. admin_username .. "' already exists"
    }))
    return
end

ngx.log(ngx.ERR, "Init: Creating admin user '" .. admin_username .. "'")

-- Create admin user with environment variables
local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
local fields = {
    "id", admin_user_id,
    "username", admin_username, 
    "password_hash", admin_password,
    "is_admin", "true",
    "is_approved", "true",
    "created_at", timestamp
}

local cmd = "hset/user:" .. admin_username
for i = 1, #fields do
    cmd = cmd .. "/" .. fields[i]
end

ngx.log(ngx.ERR, "Init: Executing Redis command: " .. cmd)

res = ngx.location.capture("/redis-internal/" .. cmd)
if res.status == 200 then
    ngx.log(ngx.ERR, "Init: Admin user created successfully")
    ngx.say(cjson.encode({
        success = true,
        message = "Admin user '" .. admin_username .. "' created successfully",
        credentials = {
            username = admin_username,
            password = admin_password,
            user_id = admin_user_id
        }
    }))
else
    ngx.log(ngx.ERR, "Init: Failed to create admin user. Redis response: " .. (res.body or "no body"))
    ngx.status = 500
    ngx.say(cjson.encode({
        success = false,
        error = "Failed to create admin user '" .. admin_username .. "'",
        redis_status = res.status,
        redis_body = res.body
    }))
end