-- nginx/lua/auth.lua - OpenResty Lua authentication with environment variables
local cjson = require "cjson"

-- Get configuration from environment variables
local MIN_USERNAME_LENGTH = tonumber(os.getenv("MIN_USERNAME_LENGTH")) or 3
local MAX_USERNAME_LENGTH = tonumber(os.getenv("MAX_USERNAME_LENGTH")) or 50
local MIN_PASSWORD_LENGTH = tonumber(os.getenv("MIN_PASSWORD_LENGTH")) or 6
local MAX_PASSWORD_LENGTH = tonumber(os.getenv("MAX_PASSWORD_LENGTH")) or 128
local SESSION_LIFETIME_DAYS = tonumber(os.getenv("SESSION_LIFETIME_DAYS")) or 7

-- Helper functions
local function generate_token(user)
    local payload = {
        user_id = user.id,
        username = user.username,
        is_admin = user.is_admin,
        exp = ngx.time() + (SESSION_LIFETIME_DAYS * 24 * 60 * 60) -- configurable session lifetime
    }
    return ngx.encode_base64(cjson.encode(payload))
end

local function verify_token(token)
    local ok, payload = pcall(function()
        return cjson.decode(ngx.decode_base64(token))
    end)
    
    if not ok or not payload.exp or payload.exp < ngx.time() then
        return nil
    end
    
    return payload
end

local function validate_username(username)
    if not username or username == "" then
        return false, "Username is required"
    end
    if #username < MIN_USERNAME_LENGTH then
        return false, "Username must be at least " .. MIN_USERNAME_LENGTH .. " characters"
    end
    if #username > MAX_USERNAME_LENGTH then
        return false, "Username must be less than " .. MAX_USERNAME_LENGTH .. " characters"
    end
    if not string.match(username, "^[a-zA-Z0-9_-]+$") then
        return false, "Username can only contain letters, numbers, underscore, and dash"
    end
    return true, ""
end

local function validate_password(password)
    if not password or password == "" then
        return false, "Password is required"
    end
    if #password < MIN_PASSWORD_LENGTH then
        return false, "Password must be at least " .. MIN_PASSWORD_LENGTH .. " characters"
    end
    if #password > MAX_PASSWORD_LENGTH then
        return false, "Password must be less than " .. MAX_PASSWORD_LENGTH .. " characters"
    end
    return true, ""
end

local function handle_login()
    if ngx.var.request_method ~= "POST" then
        ngx.status = 405
        ngx.say('{"error": "Method not allowed"}')
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
    if not ok then
        ngx.status = 400
        ngx.say('{"error": "Invalid JSON"}')
        return
    end

    local username = data.username
    local password = data.password

    -- Validate input
    local valid, err = validate_username(username)
    if not valid then
        ngx.status = 400
        ngx.say(cjson.encode({error = err}))
        return
    end

    valid, err = validate_password(password)
    if not valid then
        ngx.status = 400
        ngx.say(cjson.encode({error = err}))
        return
    end

    -- Get user from Redis
    local res = ngx.location.capture("/redis-internal/hgetall/user:" .. username)
    if res.status ~= 200 or not res.body or res.body == "" then
        ngx.status = 401
        ngx.say('{"error": "Invalid credentials"}')
        return
    end

    -- Parse Redis response
    local lines = {}
    for line in res.body:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    local user = {}
    for i = 1, #lines, 2 do
        if lines[i+1] then
            user[lines[i]] = lines[i+1]
        end
    end

    if not user.username then
        ngx.status = 401
        ngx.say('{"error": "Invalid credentials"}')
        return
    end

    -- Check password
    if user.password_hash ~= password then
        ngx.status = 401
        ngx.say('{"error": "Invalid credentials"}')
        return
    end

    -- Check if approved
    if user.is_approved ~= "true" then
        ngx.status = 403
        ngx.say('{"error": "Account pending approval"}')
        return
    end

    -- Generate token
    local token = generate_token({
        id = user.id,
        username = user.username,
        is_admin = user.is_admin == "true"
    })

    ngx.say(cjson.encode({
        success = true,
        token = token,
        user = {
            id = user.id,
            username = user.username,
            is_admin = user.is_admin == "true"
        }
    }))
end

local function handle_register()
    if ngx.var.request_method ~= "POST" then
        ngx.status = 405
        ngx.say('{"error": "Method not allowed"}')
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
    if not ok then
        ngx.status = 400
        ngx.say('{"error": "Invalid JSON"}')
        return
    end

    local username = data.username
    local password = data.password

    -- Validate input
    local valid, err = validate_username(username)
    if not valid then
        ngx.status = 400
        ngx.say(cjson.encode({error = err}))
        return
    end

    valid, err = validate_password(password)
    if not valid then
        ngx.status = 400
        ngx.say(cjson.encode({error = err}))
        return
    end

    -- Check if user exists
    local res = ngx.location.capture("/redis-internal/exists/user:" .. username)
    if res.status == 200 and res.body:match("1") then
        ngx.status = 409
        ngx.say('{"error": "Username already exists"}')
        return
    end

    -- Create user
    local user_id = tostring(ngx.time() * 1000)
    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    
    -- Set user fields
    local fields = {
        "id", user_id,
        "username", username,
        "password_hash", password,
        "is_admin", "false",
        "is_approved", "false",
        "created_at", timestamp
    }
    
    local cmd = "hset/user:" .. username
    for i = 1, #fields do
        cmd = cmd .. "/" .. fields[i]
    end
    
    res = ngx.location.capture("/redis-internal/" .. cmd)
    if res.status ~= 200 then
        ngx.status = 500
        ngx.say('{"error": "Failed to create user"}')
        return
    end

    ngx.status = 201
    ngx.say(cjson.encode({
        success = true,
        message = "User created successfully. Pending admin approval.",
        user = {
            id = user_id,
            username = username,
            is_approved = false
        }
    }))
end

local function handle_verify()
    local auth_header = ngx.var.http_authorization
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        ngx.status = 401
        ngx.say('{"error": "No token provided"}')
        return
    end

    local token = string.sub(auth_header, 8)
    local payload = verify_token(token)
    
    if not payload then
        ngx.status = 401
        ngx.say('{"error": "Invalid or expired token"}')
        return
    end

    -- Get user to verify still exists and approved
    local res = ngx.location.capture("/redis-internal/hgetall/user:" .. payload.username)
    if res.status ~= 200 or not res.body or res.body == "" then
        ngx.status = 401
        ngx.say('{"error": "User not found"}')
        return
    end

    ngx.say(cjson.encode({
        success = true,
        user = {
            id = payload.user_id,
            username = payload.username,
            is_admin = payload.is_admin
        }
    }))
end

-- Route based on URI
local uri = ngx.var.uri
if uri == "/api/auth/login" then
    handle_login()
elseif uri == "/api/auth/register" then
    handle_register()
elseif uri == "/api/auth/verify" then
    handle_verify()
else
    ngx.status = 404
    ngx.say('{"error": "Auth endpoint not found"}')
end