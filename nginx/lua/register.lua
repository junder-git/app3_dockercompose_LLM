-- nginx/lua/register.lua - Dedicated registration handler with Redis debugging
local cjson = require "cjson"

-- Get configuration from environment variables
local MIN_USERNAME_LENGTH = tonumber(os.getenv("MIN_USERNAME_LENGTH")) or 3
local MAX_USERNAME_LENGTH = tonumber(os.getenv("MAX_USERNAME_LENGTH")) or 50
local MIN_PASSWORD_LENGTH = tonumber(os.getenv("MIN_PASSWORD_LENGTH")) or 6
local MAX_PASSWORD_LENGTH = tonumber(os.getenv("MAX_PASSWORD_LENGTH")) or 128
local MAX_PENDING_USERS = tonumber(os.getenv("MAX_PENDING_USERS")) or 2

-- Password hashing function using JWT_SECRET (consistent with Redis init)
local function hash_password(password)
    local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-jwt-key-change-this-in-production-min-32-chars"
    
    -- Use JWT_SECRET as salt for consistency with Redis init
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2", 
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET:gsub("'", "'\"'\"'"))
    local hash_handle = io.popen(hash_cmd)
    local hash = hash_handle:read("*a"):gsub("\n", "")
    hash_handle:close()
    
    return "jwt_secret:" .. hash
end

-- Password verification function using JWT_SECRET (consistent with Redis init)
local function verify_password(password, stored_hash)
    if not stored_hash then
        return false
    end
    
    -- Check if it's a JWT_SECRET-based hash
    if string.find(stored_hash, "jwt_secret:") then
        local stored_hash_part = stored_hash:match("jwt_secret:([^:]+)")
        if not stored_hash_part then
            return false
        end
        
        local JWT_SECRET = os.getenv("JWT_SECRET") or "your-super-secret-jwt-key-change-this-in-production-min-32-chars"
        
        -- Hash the provided password with JWT_SECRET
        local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2", 
                                       password:gsub("'", "'\"'\"'"), JWT_SECRET:gsub("'", "'\"'\"'"))
        local hash_handle = io.popen(hash_cmd)
        local computed_hash = hash_handle:read("*a"):gsub("\n", "")
        hash_handle:close()
        
        return computed_hash == stored_hash_part
    end
    
    -- Legacy format: salt:hash
    if string.find(stored_hash, ":") then
        local salt, hash = stored_hash:match("([^:]+):([^:]+)")
        if not salt or not hash then
            return false
        end
        
        local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2", 
                                       password:gsub("'", "'\"'\"'"), salt)
        local hash_handle = io.popen(hash_cmd)
        local computed_hash = hash_handle:read("*a"):gsub("\n", "")
        hash_handle:close()
        
        return computed_hash == hash
    end
    
    -- Legacy plain text password (for backward compatibility)
    return password == stored_hash
end

-- Debug function to log Redis operations
local function debug_redis_operation(operation, uri, result)
    ngx.log(ngx.INFO, "DEBUG REDIS: Operation=" .. operation .. ", URI=" .. uri .. ", Status=" .. result.status)
    if result.body then
        ngx.log(ngx.INFO, "DEBUG REDIS: Body length=" .. #result.body)
        ngx.log(ngx.INFO, "DEBUG REDIS: Body preview=" .. string.sub(result.body, 1, 200))
    end
end

-- Test Redis connectivity
local function test_redis_connection()
    ngx.log(ngx.INFO, "DEBUG: Testing Redis connection...")
    local result = ngx.location.capture("/redis-internal/ping")
    
    debug_redis_operation("PING", "/redis-internal/ping", result)
    
    if result.status == 200 then
        ngx.log(ngx.INFO, "DEBUG: Redis PING successful")
        return true, "Redis connected"
    else
        ngx.log(ngx.ERR, "DEBUG: Redis PING failed with status: " .. result.status)
        return false, "Redis connection failed"
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

-- Parse Redis KEYS response
local function parse_redis_keys(body)
    if not body or body == "" or body == "$-1" then
        return {}
    end
    
    local lines = {}
    for line in body:gmatch("[^\r\n]+") do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end
    
    local keys = {}
    local i = 1
    
    -- Skip array count
    if lines[i] and string.match(lines[i], "^%*%d+$") then
        i = i + 1
    end
    
    -- Parse each key
    while i <= #lines do
        if lines[i] and string.match(lines[i], "^%$%d+$") then
            i = i + 1
            if lines[i] then
                table.insert(keys, lines[i])
            end
        end
        i = i + 1
    end
    
    return keys
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

-- Count pending users
local function count_pending_users()
    ngx.log(ngx.INFO, "DEBUG: Counting pending users...")
    
    local res = ngx.location.capture("/redis-internal/keys/user:*")
    debug_redis_operation("KEYS user:*", "/redis-internal/keys/user:*", res)
    
    if res.status ~= 200 then
        ngx.log(ngx.ERR, "DEBUG: Failed to get user keys from Redis")
        return 0
    end
    
    local keys = parse_redis_keys(res.body)
    ngx.log(ngx.INFO, "DEBUG: Found " .. #keys .. " user keys")
    
    local pending_count = 0
    
    for _, user_key in ipairs(keys) do
        ngx.log(ngx.INFO, "DEBUG: Checking user key: " .. user_key)
        
        local user_res = ngx.location.capture("/redis-internal/hgetall/" .. user_key)
        debug_redis_operation("HGETALL " .. user_key, "/redis-internal/hgetall/" .. user_key, user_res)
        
        if user_res.status == 200 then
            local user_data = parse_redis_hgetall(user_res.body)
            ngx.log(ngx.INFO, "DEBUG: User data for " .. user_key .. ": is_approved=" .. tostring(user_data.is_approved) .. ", is_admin=" .. tostring(user_data.is_admin))
            
            if user_data.is_approved == "false" and user_data.is_admin ~= "true" then
                pending_count = pending_count + 1
            end
        end
    end
    
    ngx.log(ngx.INFO, "DEBUG: Total pending users: " .. pending_count)
    return pending_count
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
    ngx.log(ngx.WARN, "Register error: " .. tostring(message) .. " from " .. ngx.var.remote_addr)
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

-- Debug endpoint
local function handle_debug()
    ngx.log(ngx.INFO, "DEBUG: Registration debug endpoint called")
    
    -- Test Redis connection
    local redis_ok, redis_msg = test_redis_connection()
    
    -- Test basic Redis operations
    local test_results = {}
    
    -- Test 1: Simple SET/GET
    local set_result = ngx.location.capture("/redis-internal/hset/debug_test/test_field/test_value")
    local get_result = ngx.location.capture("/redis-internal/hget/debug_test/test_field")
    
    test_results.set_status = set_result.status
    test_results.get_status = get_result.status
    test_results.get_body = get_result.body
    
    debug_redis_operation("SET TEST", "/redis-internal/hset/debug_test/test_field/test_value", set_result)
    debug_redis_operation("GET TEST", "/redis-internal/hget/debug_test/test_field", get_result)
    
    -- Test 2: Check if we can see the test data
    local hgetall_result = ngx.location.capture("/redis-internal/hgetall/debug_test")
    test_results.hgetall_status = hgetall_result.status
    test_results.hgetall_body = hgetall_result.body
    
    debug_redis_operation("HGETALL TEST", "/redis-internal/hgetall/debug_test", hgetall_result)
    
    -- Clean up test data
    local del_result = ngx.location.capture("/redis-internal/del/debug_test")
    debug_redis_operation("DEL TEST", "/redis-internal/del/debug_test", del_result)
    
    -- Count users
    local pending_count = count_pending_users()
    
    -- Try to get a specific user (admin)
    local admin_test = ngx.location.capture("/redis-internal/hgetall/user:admin1")
    debug_redis_operation("HGETALL user:admin1", "/redis-internal/hgetall/user:admin1", admin_test)
    
    local admin_data = {}
    if admin_test.status == 200 then
        admin_data = parse_redis_hgetall(admin_test.body)
    end
    
    -- Test Redis info
    local info_result = ngx.location.capture("/redis-internal/info")
    debug_redis_operation("INFO", "/redis-internal/info", info_result)
    
    -- Test database size
    local dbsize_result = ngx.location.capture("/redis-internal/dbsize")
    debug_redis_operation("DBSIZE", "/redis-internal/dbsize", dbsize_result)
    
    send_success_response({
        redis_status = redis_ok,
        redis_message = redis_msg,
        test_results = test_results,
        pending_users = pending_count,
        max_pending = MAX_PENDING_USERS,
        admin_user_exists = admin_data.username ~= nil,
        admin_user_data = admin_data,
        redis_info_status = info_result.status,
        redis_dbsize_status = dbsize_result.status
    })
end user (admin)
    local admin_test = ngx.location.capture("/redis-internal/hgetall/user:admin1")
    debug_redis_operation("HGETALL user:admin1", "/redis-internal/hgetall/user:admin1", admin_test)
    
    local admin_data = {}
    if admin_test.status == 200 then
        admin_data = parse_redis_hgetall(admin_test.body)
    end
    
    send_success_response({
        redis_status = redis_ok,
        redis_message = redis_msg,
        pending_users = pending_count,
        max_pending = MAX_PENDING_USERS,
        admin_user_exists = admin_data.username ~= nil,
        admin_user_data = admin_data
    })
end

-- Main registration handler
local function handle_register()
    ngx.log(ngx.INFO, "DEBUG: Registration request received")
    
    if ngx.var.request_method ~= "POST" then
        send_error_response(405, "Method not allowed")
        return
    end

    local content_type = ngx.var.content_type
    if not content_type or not string.match(content_type, "application/json") then
        send_error_response(400, "Invalid content type")
        return
    end

    -- Test Redis connection first
    local redis_ok, redis_msg = test_redis_connection()
    if not redis_ok then
        send_error_response(503, "Service unavailable: " .. redis_msg)
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

    ngx.log(ngx.INFO, "DEBUG: Received registration data for username: " .. tostring(data.username))

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

    ngx.log(ngx.INFO, "DEBUG: Validation passed for username: " .. username)

    -- Check if user already exists
    local exists_res = ngx.location.capture("/redis-internal/exists/user:" .. username)
    debug_redis_operation("EXISTS user:" .. username, "/redis-internal/exists/user:" .. username, exists_res)
    
    if exists_res.status == 200 and exists_res.body:match("1") then
        send_error_response(409, "Username already exists")
        return
    end

    -- Check pending user limit
    local pending_count = count_pending_users()
    ngx.log(ngx.INFO, "DEBUG: Current pending users: " .. pending_count .. ", Max allowed: " .. MAX_PENDING_USERS)
    
    if pending_count >= MAX_PENDING_USERS then
        send_error_response(429, "Registration temporarily unavailable - too many pending approvals (" .. pending_count .. "/" .. MAX_PENDING_USERS .. ")")
        return
    end

    -- Create user
    local user_id = tostring(ngx.time() * 1000 + math.random(1000, 9999))
    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    
    ngx.log(ngx.INFO, "DEBUG: Creating user with ID: " .. user_id)
    
    -- Try a single HSET command first to test Redis connectivity
    local test_key = "test_user_creation"
    local test_result = ngx.location.capture("/redis-internal/hset/" .. test_key .. "/test_field/test_value")
    debug_redis_operation("HSET TEST", "/redis-internal/hset/" .. test_key .. "/test_field/test_value", test_result)
    
    if test_result.status ~= 200 then
        ngx.log(ngx.ERR, "DEBUG: Redis test HSET failed")
        send_error_response(500, "Redis connectivity test failed")
        return
    end
    
    -- Clean up test key
    local cleanup_result = ngx.location.capture("/redis-internal/del/" .. test_key)
    debug_redis_operation("DEL TEST", "/redis-internal/del/" .. test_key, cleanup_result)
    
    -- Now try creating the user with a simpler approach
    ngx.log(ngx.INFO, "DEBUG: Redis test passed, creating user...")
    
    -- Hash the password
    local hashed_password = hash_password(password)
    ngx.log(ngx.INFO, "DEBUG: Password hashed successfully")
    
    -- Create user key
    local user_key = "user:" .. username
    ngx.log(ngx.INFO, "DEBUG: User key: " .. user_key)
    
    -- Try HMSET instead of individual HSET commands
    local hmset_path = "/redis-internal/hmset/" .. user_key .. 
                      "/id/" .. user_id ..
                      "/username/" .. username ..
                      "/password_hash/" .. hashed_password ..
                      "/is_admin/false" ..
                      "/is_approved/false" ..
                      "/created_at/" .. timestamp ..
                      "/last_login/" .. timestamp
    
    ngx.log(ngx.INFO, "DEBUG: HMSET path: " .. hmset_path)
    
    local hmset_result = ngx.location.capture(hmset_path)
    debug_redis_operation("HMSET user:" .. username, hmset_path, hmset_result)
    
    if hmset_result.status ~= 200 then
        ngx.log(ngx.ERR, "DEBUG: HMSET failed for user " .. username)
        send_error_response(500, "Failed to create user - HMSET failed")
        return
    end
    
    -- Verify user was created
    local verify_result = ngx.location.capture("/redis-internal/hgetall/user:" .. username)
    debug_redis_operation("HGETALL VERIFY", "/redis-internal/hgetall/user:" .. username, verify_result)
    
    if verify_result.status ~= 200 then
        ngx.log(ngx.ERR, "DEBUG: User verification failed")
        send_error_response(500, "User creation verification failed")
        return
    end

    ngx.log(ngx.INFO, "DEBUG: User creation successful: " .. username)
    
    ngx.status = 201
    send_success_response({
        message = "User created successfully. Pending admin approval (" .. (pending_count + 1) .. "/" .. MAX_PENDING_USERS .. " pending users).",
        user = {
            id = user_id,
            username = username,
            is_approved = false
        },
        pending_info = {
            current_pending = pending_count + 1,
            max_pending = MAX_PENDING_USERS
        }
    })
end

-- Route handling
local uri = ngx.var.uri
local method = ngx.var.request_method

ngx.log(ngx.INFO, "DEBUG: Register.lua handling " .. method .. " " .. uri)

if uri == "/api/register" and method == "POST" then
    handle_register()
elseif uri == "/api/register/debug" and method == "GET" then
    handle_debug()
else
    send_error_response(404, "Registration endpoint not found")
end