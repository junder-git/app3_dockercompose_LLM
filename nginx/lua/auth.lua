-- nginx/lua/auth.lua - Simplified authentication handler with OpenSSL HMAC
local cjson = require "cjson"

-- Get configuration from environment variables
local MIN_USERNAME_LENGTH = tonumber(os.getenv("MIN_USERNAME_LENGTH")) or 3
local MAX_USERNAME_LENGTH = tonumber(os.getenv("MAX_USERNAME_LENGTH")) or 50
local MIN_PASSWORD_LENGTH = tonumber(os.getenv("MIN_PASSWORD_LENGTH")) or 6
local MAX_PASSWORD_LENGTH = tonumber(os.getenv("MAX_PASSWORD_LENGTH")) or 128
local SESSION_LIFETIME_DAYS = tonumber(os.getenv("SESSION_LIFETIME_DAYS")) or 7

-- JWT Secret (in production, this should be from environment variable)
local JWT_SECRET = os.getenv("JWT_SECRET") or "your-secret-key-change-this-in-production"

-- OpenSSL HMAC function using shell command (workaround)
local function hmac_sha256(key, message)
    local cmd = string.format("echo -n '%s' | openssl dgst -sha256 -hmac '%s' -binary | base64", 
                             message:gsub("'", "'\"'\"'"), key:gsub("'", "'\"'\"'"))
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result:gsub("\n", "")
end

-- Base64 URL-safe encoding
local function base64_url_encode(str)
    local base64 = ngx.encode_base64(str)
    -- Convert to URL-safe base64
    base64 = string.gsub(base64, "+", "-")
    base64 = string.gsub(base64, "/", "_")
    base64 = string.gsub(base64, "=", "")
    return base64
end

-- Base64 URL-safe decoding
local function base64_url_decode(str)
    -- Convert back from URL-safe base64
    str = string.gsub(str, "-", "+")
    str = string.gsub(str, "_", "/")
    -- Add padding if needed
    local padding = #str % 4
    if padding > 0 then
        str = str .. string.rep("=", 4 - padding)
    end
    return ngx.decode_base64(str)
end

-- JWT generation using OpenSSL
local function generate_jwt(payload)
    local header = {
        typ = "JWT",
        alg = "HS256"
    }
    
    local header_json = cjson.encode(header)
    local payload_json = cjson.encode(payload)
    
    local header_b64 = base64_url_encode(header_json)
    local payload_b64 = base64_url_encode(payload_json)
    
    local signature_input = header_b64 .. "." .. payload_b64
    
    -- Create HMAC SHA256 signature using OpenSSL
    local signature_b64_raw = hmac_sha256(JWT_SECRET, signature_input)
    -- Convert from regular base64 to URL-safe base64
    local signature_b64 = base64_url_encode(ngx.decode_base64(signature_b64_raw))
    
    return header_b64 .. "." .. payload_b64 .. "." .. signature_b64
end

-- JWT verification using OpenSSL
local function verify_jwt(token)
    if not token or type(token) ~= "string" then
        return nil, "Invalid token format"
    end
    
    -- Split token
    local parts = {}
    for part in string.gmatch(token, "[^%.]+") do
        table.insert(parts, part)
    end
    
    if #parts ~= 3 then
        return nil, "Invalid token structure"
    end
    
    local header_b64, payload_b64, signature_b64 = parts[1], parts[2], parts[3]
    
    -- Verify signature
    local signature_input = header_b64 .. "." .. payload_b64
    local expected_signature_b64_raw = hmac_sha256(JWT_SECRET, signature_input)
    local expected_signature_b64 = base64_url_encode(ngx.decode_base64(expected_signature_b64_raw))
    
    if signature_b64 ~= expected_signature_b64 then
        return nil, "Invalid signature"
    end
    
    -- Decode payload
    local payload_json = base64_url_decode(payload_b64)
    if not payload_json then
        return nil, "Invalid payload encoding"
    end
    
    local ok, payload = pcall(cjson.decode, payload_json)
    if not ok then
        return nil, "Invalid payload JSON"
    end
    
    -- Check expiration
    if payload.exp and payload.exp < ngx.time() then
        return nil, "Token expired"
    end
    
    return payload, nil
end

-- Store JWT in Redis
local function store_jwt_in_redis(user_id, jwt_token)
    local jwt_key = "jwt:" .. user_id
    local expiry = SESSION_LIFETIME_DAYS * 24 * 60 * 60 -- Convert to seconds
    
    -- Store JWT with expiration
    local store_result = ngx.location.capture("/redis-internal/setex/" .. jwt_key .. "/" .. expiry .. "/" .. jwt_token)
    
    if store_result.status == 200 then
        ngx.log(ngx.INFO, "JWT stored in Redis for user: " .. user_id)
        return true
    else
        ngx.log(ngx.ERR, "Failed to store JWT in Redis for user: " .. user_id)
        return false
    end
end

-- Retrieve JWT from Redis
local function get_jwt_from_redis(user_id)
    local jwt_key = "jwt:" .. user_id
    local result = ngx.location.capture("/redis-internal/get/" .. jwt_key)
    
    if result.status == 200 and result.body and result.body ~= "$-1" then
        -- Parse Redis response
        local lines = {}
        for line in result.body:gmatch("[^\r\n]+") do
            if line and line ~= "" then
                table.insert(lines, line)
            end
        end
        
        -- Extract JWT from Redis response
        if #lines >= 2 and lines[1]:match("^%$%d+$") then
            local jwt_token = lines[2]
            ngx.log(ngx.INFO, "JWT retrieved from Redis for user: " .. user_id)
            return jwt_token
        end
    end
    
    ngx.log(ngx.INFO, "No JWT found in Redis for user: " .. user_id)
    return nil
end

-- Delete JWT from Redis (for logout)
local function delete_jwt_from_redis(user_id)
    local jwt_key = "jwt:" .. user_id
    local result = ngx.location.capture("/redis-internal/del/" .. jwt_key)
    return result.status == 200
end

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

    -- Check if user already has a valid JWT in Redis
    local existing_jwt = get_jwt_from_redis(user.id)
    if existing_jwt then
        -- Verify the existing JWT
        local payload, err = verify_jwt(existing_jwt)
        if payload and payload.exp and payload.exp > ngx.time() then
            -- Valid JWT exists, return it
            ngx.log(ngx.INFO, "Returning existing valid JWT for user: " .. username)
            send_success_response({
                token = existing_jwt,
                user = {
                    id = user.id,
                    username = user.username,
                    is_admin = user.is_admin == "true"
                }
            })
            return
        end
    end

    -- Create new JWT
    local jwt_payload = {
        user_id = user.id,
        username = user.username,
        is_admin = user.is_admin == "true",
        exp = ngx.time() + (SESSION_LIFETIME_DAYS * 24 * 60 * 60),
        iat = ngx.time(),
        jti = tostring(ngx.time() * 1000 + math.random(1000, 9999)) -- JWT ID
    }

    local jwt_token = generate_jwt(jwt_payload)
    
    -- Store JWT in Redis
    local store_success = store_jwt_in_redis(user.id, jwt_token)
    if not store_success then
        send_error_response(500, "Failed to store session")
        return
    end

    ngx.log(ngx.INFO, "DEBUG: Successful login for user: " .. username .. " with new JWT")
    
    send_success_response({
        token = jwt_token,
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
    local payload, err = verify_jwt(token)
    
    if not payload then
        ngx.log(ngx.WARN, "DEBUG: Token verification failed: " .. (err or "unknown"))
        send_error_response(401, "Invalid or expired token: " .. (err or "unknown error"))
        return
    end

    -- Verify JWT exists in Redis
    local stored_jwt = get_jwt_from_redis(payload.user_id)
    if not stored_jwt or stored_jwt ~= token then
        send_error_response(401, "Token not found in session store")
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

-- Logout handler
local function handle_logout()
    local auth_header = ngx.var.http_authorization
    if not auth_header or not string.match(auth_header, "^Bearer ") then
        send_error_response(401, "No token provided")
        return
    end

    local token = string.sub(auth_header, 8)
    local payload, err = verify_jwt(token)
    
    if not payload then
        send_error_response(401, "Invalid token")
        return
    end

    -- Delete JWT from Redis
    local delete_success = delete_jwt_from_redis(payload.user_id)
    
    if delete_success then
        send_success_response({
            message = "Logged out successfully"
        })
    else
        send_error_response(500, "Failed to logout")
    end
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
elseif uri == "/api/auth/logout" and method == "POST" then
    handle_logout()
elseif uri == "/api/auth/debug" and method == "GET" then
    handle_debug()
else
    send_error_response(404, "Auth endpoint not found")
end