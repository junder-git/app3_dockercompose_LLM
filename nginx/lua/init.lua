-- nginx/lua/init.lua - System initialization
local cjson = require "cjson"

-- Check if admin user exists
local res = ngx.location.capture("/redis-internal/exists/user:admin")
if res.status == 200 and res.body:match("1") then
    ngx.say(cjson.encode({
        success = true,
        message = "Admin user already exists"
    }))
    return
end

-- Create admin user
local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
local fields = {
    "id", "admin",
    "username", "admin", 
    "password_hash", "admin",
    "is_admin", "true",
    "is_approved", "true",
    "created_at", timestamp
}

local cmd = "hset/user:admin"
for i = 1, #fields do
    cmd = cmd .. "/" .. fields[i]
end

res = ngx.location.capture("/redis-internal/" .. cmd)
if res.status == 200 then
    ngx.say(cjson.encode({
        success = true,
        message = "Admin user created successfully",
        credentials = {
            username = "admin",
            password = "admin"
        }
    }))
else
    ngx.status = 500
    ngx.say(cjson.encode({
        success = false,
        error = "Failed to create admin user"
    }))
end