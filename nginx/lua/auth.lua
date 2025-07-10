-- nginx/lua/auth.lua - Simplified authentication handler
local cjson = require "cjson"

-- Get configuration from environment variables
local MIN_USERNAME_LENGTH = tonumber(os.getenv("MIN_USERNAME_LENGTH")) or 3
local MAX_USERNAME_LENGTH = tonumber(os.getenv("MAX_USERNAME_LENGTH")) or 50
local MIN_PASSWORD_LENGTH = tonumber(os.getenv("MIN_PASSWORD_LENGTH")) or 6
local MAX_PASSWORD_LENGTH = tonumber(os.getenv("MAX_PASSWORD_LENGTH")) or 128
local SESSION_LIFETIME_DAYS = tonumber(os.getenv("SESSION_LIFETIME_DAYS")) or 7

-- JWT Secret (in production, this should be from environment variable)
local JWT_SECRET = os.getenv("JWT_SECRET") or "your-secret-key-change-this-in-production"

-- Debug function to log Redis operations
local function debug_redis_operation(operation, uri, result)
    ngx.log(ngx.INFO, "DEBUG REDIS: Operation=" .. operation .. ", URI=" .. uri .. ", Status=" .. result.status)
    if result.body then
        ngx.log(ngx.INFO, "DEBUG REDIS: Body length=" .. #result.body)
        ngx.log(ngx.INFO, "DEBUG REDIS: Body preview=" .. string.sub(result.body, 1, 200))
    end
end

-- Simple sanitization
local function sanitize_input(input)
    if not input or type(input) ~= "string" then
        return ""
    end
    
    local result = ""
    for i = 1, #input do
        local char = string.sub(input, i, i)
        local byte = string.byte(char)
        
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
    
    if #username < MIN_USERNAME_LENGTH then
        return false, "Username must be at least " .. MIN_USERNAME_LENGTH .. " characters"
    end
    if #username > MAX_USERNAME_LENGTH then
        return false, "Username must be less than " .. MAX_USERNAME_LENGTH .. " characters"
    end
    
    local clean_username = sanitize_input(username)
    
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

-- Simple token generation (for now, we'll use the original base64 approach)
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

-- Parse Redis HGETALL response
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

-- Error response
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

-- Login handler
local function handle_login()
    ngx.log(ngx.INFO, "DEBUG: Login request received")
    
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

    ngx.log(ngx.INFO, "DEBUG: Login attempt for username: " .. tostring(data.username))

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
    debug_redis_operation("HGETALL user:" .. username, "/redis-internal/hgetall/user:" .. username, res)
    
    if res.status ~= 200 then
        ngx.log(ngx.WARN, "DEBUG: User not found in Redis: " .. username)
        send_error_response(401, "Invalid credentials")
        return
    end

    local user = parse_redis_hgetall(res.body)
    
    if not user.username or user.username ~= username then
        ngx.log(ngx.WARN, "DEBUG: Username mismatch for: " .. username)
        send_error_response(401, "Invalid credentials")
        return
    end

    -- Password comparison
    if user.password_hash ~= password then
        ngx.log(ngx.WARN, "DEBUG: Password mismatch for: " .. username)
        send_error_response(401, "Invalid credentials")
        return
    end

    -- Check if user is approved
    if user.is_approved ~= "true" then
        ngx.log(ngx.WARN, "DEBUG: User not approved: " .. username)
        send_error_response(403, "Account pending approval")
        return
    end

    -- Generate token
    local token = generate_token({
        id = user.id,
        username = user.username,
        is_admin = user.is_admin == "true"
    })

    ngx.log(ngx.INFO, "DEBUG: Successful login for user: " .. username)
    
    send_success_response({
        token = token,
        user = {
            id = user.id,
            username = user.username,
            is_admin = user.is_admin == "true"
        }
    })
end

-- Verify handler
local function handle_verify()
    ngx.log(ngx.INFO, "DEBUG: Verify request received")
    
    local auth_header = ngx.var.http_authorization
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        send_error_response(401, "No token provided")
        return
    end

    local token = string.sub(auth_header, 8)
    local payload, err = verify_token(token)
    
    if not payload then
        ngx.log(ngx.WARN, "DEBUG: Token verification failed: " .. (err or "unknown"))
        send_error_response(401, "Invalid or expired token")
        return
    end

    -- Verify user still exists and is approved
    local res = ngx.location.capture("/redis-internal/hgetall/user:" .. payload.username)
    debug_redis_operation("HGETALL user:" .. payload.username, "/redis-internal/hgetall/user:" .. payload.username, res)
    
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

-- Debug endpoint
local function handle_debug()
    ngx.log(ngx.INFO, "DEBUG: Auth debug endpoint called")
    
    -- Test Redis connection
    local redis_res = ngx.location.capture("/redis-internal/ping")
    debug_redis_operation("PING", "/redis-internal/ping", redis_res)
    
    -- Try to get admin user
    local admin_res = ngx.location.capture("/redis-internal/hgetall/user:admin1")
    debug_redis_operation("HGETALL user:admin1", "/redis-internal/hgetall/user:admin1", admin_res)
    
    local admin_data = {}
    if admin_res.status == 200 then
        admin_data = parse_redis_hgetall(admin_res.body)
    end
    
    send_success_response({
        redis_ping = redis_res.status == 200,
        admin_user_exists = admin_data.username ~= nil,
        admin_data = admin_data
    })
end

-- Route handling
local uri = ngx.var.uri
local method = ngx.var.request_method

ngx.log(ngx.INFO, "DEBUG: Auth.lua handling " .. method .. " " .. uri)

if uri == "/api/auth/login" and method == "POST" then
    handle_login()
elseif uri == "/api/auth/verify" and method == "GET" then
    handle_verify()
elseif uri == "/api/auth/debug" and method == "GET" then
    handle_debug()
else
    send_error_response(404, "Auth endpoint not found")
end