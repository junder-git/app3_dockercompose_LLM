-- nginx/lua/auth.lua - Safe version with no regex pattern issues
local cjson = require "cjson"

-- Get configuration from environment variables
local MIN_USERNAME_LENGTH = tonumber(os.getenv("MIN_USERNAME_LENGTH")) or 3
local MAX_USERNAME_LENGTH = tonumber(os.getenv("MAX_USERNAME_LENGTH")) or 50
local MIN_PASSWORD_LENGTH = tonumber(os.getenv("MIN_PASSWORD_LENGTH")) or 6
local MAX_PASSWORD_LENGTH = tonumber(os.getenv("MAX_PASSWORD_LENGTH")) or 128
local SESSION_LIFETIME_DAYS = tonumber(os.getenv("SESSION_LIFETIME_DAYS")) or 7

-- SAFE: Simple sanitization without regex patterns
local function sanitize_input(input)
    if not input or type(input) ~= "string" then
        return ""
    end
    
    -- Simple character-by-character sanitization
    local result = ""
    for i = 1, #input do
        local char = string.sub(input, i, i)
        local byte = string.byte(char)
        
        -- Keep only safe characters: letters, numbers, underscore, dash
        if (byte >= 48 and byte <= 57) or  -- 0-9
           (byte >= 65 and byte <= 90) or  -- A-Z
           (byte >= 97 and byte <= 122) or -- a-z
           (byte == 95) or                 -- _
           (byte == 45) then               -- -
            result = result .. char
        end
    end
    
    return result
end

local function validate_username(username)
    if not username or type(username) ~= "string" then
        return false, "Username must be a string"
    end
    
    -- Basic length check before sanitization
    if #username < MIN_USERNAME_LENGTH then
        return false, "Username must be at least " .. MIN_USERNAME_LENGTH .. " characters"
    end
    if #username > MAX_USERNAME_LENGTH then
        return false, "Username must be less than " .. MAX_USERNAME_LENGTH .. " characters"
    end
    
    -- Sanitize input
    local clean_username = sanitize_input(username)
    
    -- Check if sanitization removed characters (indicating invalid chars)
    if #clean_username ~= #username then
        return false, "Username can only contain letters, numbers, underscore, and dash"
    end
    
    return true, clean_username
end

local function validate_password(password)
    if not password or type(password) ~= "string" then
        return false, "Password must be a string"
    end
    if #password < MIN_PASSWORD_LENGTH then
        return false, "Password must be at least " .. MIN_PASSWORD_LENGTH .. " characters"
    end
    if #password > MAX_PASSWORD_LENGTH then
        return false, "Password must be less than " .. MAX_PASSWORD_LENGTH .. " characters"
    end
    return true, password
end

-- Token generation
local function generate_token(user)
    local payload = {
        user_id = user.id,
        username = user.username,
        is_admin = user.is_admin,
        exp = ngx.time() + (SESSION_LIFETIME_DAYS * 24 * 60 * 60),
        iat = ngx.time()
    }
    return ngx.encode_base64(cjson.encode(payload))
end

-- Token verification
local function verify_token(token)
    if not token or type(token) ~= "string" then
        return nil, "Invalid token format"
    end
    
    local ok, payload = pcall(function()
        return cjson.decode(ngx.decode_base64(token))
    end)
    
    if not ok then
        return nil, "Invalid token encoding"
    end
    
    if not payload.exp or not payload.iat then
        return nil, "Invalid token structure"
    end
    
    if payload.exp < ngx.time() then
        return nil, "Token expired"
    end
    
    return payload, nil
end

-- Simplified Redis RESP parser (no debug logging)
local function parse_redis_hgetall(body)
    if not body or body == "" or body == "$-1" then
        return {}
    end
    
    local lines = {}
    for line in body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end
    
    local result = {}
    local i = 1
    
    -- Skip array count
    if lines[i] and string.match(lines[i], "^%*%d+$") then
        i = i + 1
    end
    
    -- Parse key-value pairs
    while i <= #lines do
        if lines[i] and string.match(lines[i], "^%$%d+$") then
            i = i + 1
            if lines[i] then
                local key = lines[i]
                i = i + 1
                
                if lines[i] and string.match(lines[i], "^%$%d+$") then
                    i = i + 1
                    if lines[i] then
                        local value = lines[i]
                        result[key] = value
                    end
                end
            end
        end
        i = i + 1
    end
    
    return result
end

-- SAFE: Error response without sanitization
local function send_error_response(status, message)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.header["X-Content-Type-Options"] = "nosniff"
    
    local response = {
        error = tostring(message),
        timestamp = ngx.utctime()
    }
    
    ngx.say(cjson.encode(response))
    ngx.log(ngx.WARN, "Auth error: " .. tostring(message) .. " from " .. ngx.var.remote_addr)
end

-- Success response
local function send_success_response(data)
    ngx.header.content_type = "application/json"
    ngx.header["X-Content-Type-Options"] = "nosniff"
    
    local response = {
        success = true,
        timestamp = ngx.utctime()
    }
    
    for k, v in pairs(data) do
        response[k] = v
    end
    
    ngx.say(cjson.encode(response))
end

local function handle_login()
    if ngx.var.request_method ~= "POST" then
        send_error_response(405, "Method not allowed")
        return
    end

    local content_type = ngx.var.content_type
    if not content_type or not string.match(content_type, "application/json") then
        send_error_response(400, "Invalid content type")
        return
    end

    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        send_error_response(400, "Request body required")
        return
    end

    if #body > 1024 then
        send_error_response(400, "Request body too large")
        return
    end

    local ok, data = pcall(cjson.decode, body)
    if not ok then
        send_error_response(400, "Invalid JSON")
        return
    end

    -- Input validation
    local valid, username = validate_username(data.username)
    if not valid then
        send_error_response(400, username)
        return
    end

    valid, password = validate_password(data.password)
    if not valid then
        send_error_response(400, password)
        return
    end

    -- Get user from Redis
    local res = ngx.location.capture("/redis-internal/hgetall/user:" .. username)
    
    if res.status ~= 200 then
        send_error_response(401, "Invalid credentials")
        return
    end

    local user = parse_redis_hgetall(res.body)
    
    if not user.username or user.username ~= username then
        send_error_response(401, "Invalid credentials")
        return
    end

    -- Password comparison
    if user.password_hash ~= password then
        send_error_response(401, "Invalid credentials")
        return
    end

    -- Check if user is approved
    if user.is_approved ~= "true" then
        send_error_response(403, "Account pending approval")
        return
    end

    -- Generate token
    local token = generate_token({
        id = user.id,
        username = user.username,
        is_admin = user.is_admin == "true"
    })

    ngx.log(ngx.INFO, "Successful login for user: " .. username)
    
    send_success_response({
        token = token,
        user = {
            id = user.id,
            username = user.username,
            is_admin = user.is_admin == "true"
        }
    })
end

local function handle_register()
    if ngx.var.request_method ~= "POST" then
        send_error_response(405, "Method not allowed")
        return
    end

    local content_type = ngx.var.content_type
    if not content_type or not string.match(content_type, "application/json") then
        send_error_response(400, "Invalid content type")
        return
    end

    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        send_error_response(400, "Request body required")
        return
    end

    if #body > 1024 then
        send_error_response(400, "Request body too large")
        return
    end

    local ok, data = pcall(cjson.decode, body)
    if not ok then
        send_error_response(400, "Invalid JSON")
        return
    end

    -- Input validation
    local valid, username = validate_username(data.username)
    if not valid then
        send_error_response(400, username)
        return
    end

    valid, password = validate_password(data.password)
    if not valid then
        send_error_response(400, password)
        return
    end

    -- Check if user already exists
    local res = ngx.location.capture("/redis-internal/exists/user:" .. username)
    if res.status == 200 and res.body:match("1") then
        send_error_response(409, "Username already exists")
        return
    end

    -- Create user
    local user_id = tostring(ngx.time() * 1000 + math.random(1000, 9999))
    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    
    local res = ngx.location.capture("/redis-internal/hmset/user:" .. username .. 
        "/id/" .. user_id ..
        "/username/" .. username ..
        "/password_hash/" .. password ..
        "/is_admin/false" ..
        "/is_approved/false" ..
        "/created_at/" .. timestamp ..
        "/last_login/" .. timestamp)
    
    if res.status ~= 200 then
        send_error_response(500, "Failed to create user")
        return
    end

    ngx.log(ngx.INFO, "User registration successful: " .. username)
    
    ngx.status = 201
    send_success_response({
        message = "User created successfully. Pending admin approval.",
        user = {
            id = user_id,
            username = username,
            is_approved = false
        }
    })
end

local function handle_verify()
    local auth_header = ngx.var.http_authorization
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        send_error_response(401, "No token provided")
        return
    end

    local token = string.sub(auth_header, 8)
    local payload, err = verify_token(token)
    
    if not payload then
        send_error_response(401, "Invalid or expired token")
        return
    end

    -- Verify user still exists and is approved
    local res = ngx.location.capture("/redis-internal/hgetall/user:" .. payload.username)
    if res.status ~= 200 then
        send_error_response(401, "User not found")
        return
    end

    local user = parse_redis_hgetall(res.body)
    if not user.username or user.is_approved ~= "true" then
        send_error_response(401, "User not found or not approved")
        return
    end

    send_success_response({
        user = {
            id = payload.user_id,
            username = payload.username,
            is_admin = payload.is_admin
        }
    })
end

-- Route handling
local uri = ngx.var.uri

if uri == "/api/auth/login" then
    handle_login()
elseif uri == "/api/auth/register" then
    handle_register()
elseif uri == "/api/auth/verify" then
    handle_verify()
else
    send_error_response(404, "Auth endpoint not found")
end