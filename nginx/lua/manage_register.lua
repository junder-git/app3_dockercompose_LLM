-- nginx/lua/manage_register.lua - SECURE user registration handler with pending user limits
local cjson = require "cjson"
local auth = require "manage_auth"
local redis = require "resty.redis"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"
local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local MAX_PENDING_USERS = 2  -- Maximum number of pending users allowed

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
        ngx.log(ngx.ERR, "Redis connection failed: " .. (err or "unknown"))
        return nil
    end
    return red
end

local function redis_to_lua(value)
    if value == ngx.null or value == nil then
        return nil
    end
    return value
end

-- Count pending users (is_approved = false, is_admin = false)
local function count_pending_users()
    local red = connect_redis()
    if not red then
        ngx.log(ngx.WARN, "Redis unavailable for pending user count")
        return 0, "Redis unavailable"
    end
    
    local user_keys = redis_to_lua(red:keys("username:*")) or {}
    local pending_count = 0
    local pending_usernames = {}
    
    for _, key in ipairs(user_keys) do
        if key ~= "username:" then -- Skip invalid keys
            local user_data = red:hgetall(key)
            if user_data and #user_data > 0 then
                local user = {}
                for i = 1, #user_data, 2 do
                    local field_key = user_data[i]
                    if string.sub(field_key, -1) == ":" then
                        field_key = string.sub(field_key, 1, -2)
                    end
                    user[field_key] = user_data[i + 1]
                end
                
                -- Count users who are pending
                if user.user_type == "is_pending" and user.username then
                    pending_count = pending_count + 1
                    table.insert(pending_usernames, user.username)
                end
            end
        end
    end
    
    red:close()
    
    ngx.log(ngx.INFO, "Pending users count: " .. pending_count .. 
            " (users: " .. table.concat(pending_usernames, ", ") .. ")")
    
    return pending_count, nil
end

-- SECURITY: Validate username format
local function validate_username(username)
    if not username or type(username) ~= "string" then
        return false, "Username must be a string"
    end
    
    if #username < 3 or #username > 20 then
        return false, "Username must be 3-20 characters long"
    end
    
    if not string.match(username, "^[a-zA-Z0-9_]+$") then
        return false, "Username can only contain letters, numbers, and underscores"
    end
    
    -- Reserved usernames (including guest patterns)
    local reserved = {"admin", "root", "system", "api", "www", "mail", "ftp", "guest", "anonymous", "test", "demo"}
    for _, reserved_name in ipairs(reserved) do
        if string.lower(username) == reserved_name then
            return false, "Username is reserved"
        end
    end
    
    -- Block guest-style usernames
    if string.match(string.lower(username), "^guest") then
        return false, "Usernames starting with 'guest' are reserved"
    end
    
    return true, "Valid username"
end

-- SECURITY: Validate password strength
local function validate_password(password)
    if not password or type(password) ~= "string" then
        return false, "Password must be a string"
    end
    
    if #password < 6 then
        return false, "Password must be at least 6 characters long"
    end
    
    if #password > 128 then
        return false, "Password is too long"
    end
    
    -- Check for common weak passwords
    local weak_passwords = {"password", "123456", "password123", "admin", "qwerty", "letmein", "welcome"}
    for _, weak in ipairs(weak_passwords) do
        if string.lower(password) == weak then
            return false, "Password is too weak"
        end
    end
    
    return true, "Valid password"
end

-- SECURE password hashing - same as login
local function hash_password(password)
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | awk '{print $2}'",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    return hash
end

-- Check if user already exists
local function user_exists(username)
    local user_data = auth.get_user(username)
    return user_data ~= nil
end

-- Create new user in Redis
local function create_user(username, password_hash, ip_address)
    local red = connect_redis()
    if not red then
        return false, "Database connection failed"
    end
    
    local user_key = "username:" .. username
    local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
    
    -- Create user with pending status
    local ok, err = red:hmset(user_key,
        "username", username,
        "password_hash", password_hash,
        "user_type", "is_pending",
        "created_at", now,
        "created_ip", ip_address or "unknown",
        "last_active", now
    )
    
    if not ok then
        red:close()
        return false, "Failed to create user: " .. (err or "unknown")
    end
    
    red:close()
    return true, "User created successfully"
end

-- CRITICAL: Registration with pending user limits
local function handle_register()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        send_json(400, { error = "Missing request body" })
    end

    local data = cjson.decode(body)
    local username = data.username
    local password = data.password

    if not username or not password then
        send_json(400, { error = "Username and password required" })
    end

    -- SECURITY: Rate limit registration attempts per IP
    local register_key = "register_attempts:" .. (ngx.var.remote_addr or "unknown")
    local attempts = ngx.shared.guest_sessions:get(register_key) or 0
    
    if attempts >= 3 then
        ngx.log(ngx.WARN, "Too many registration attempts from " .. (ngx.var.remote_addr or "unknown"))
        send_json(429, { error = "Too many registration attempts, please try again later" })
    end

    -- SECURITY: Validate input
    local username_valid, username_error = validate_username(username)
    if not username_valid then
        ngx.shared.guest_sessions:set(register_key, attempts + 1, 600) -- 10 minute lockout
        send_json(400, { error = username_error })
    end

    local password_valid, password_error = validate_password(password)
    if not password_valid then
        ngx.shared.guest_sessions:set(register_key, attempts + 1, 600)
        send_json(400, { error = password_error })
    end

    -- ANTI-SPAM: Check if user already exists
    if user_exists(username) then
        ngx.shared.guest_sessions:set(register_key, attempts + 1, 600)
        ngx.log(ngx.WARN, "Registration attempt with existing username: " .. username)
        send_json(409, { error = "Username already taken" })
    end

    -- ANTI-SPAM: Check pending user limit
    local pending_count, count_error = count_pending_users()
    if count_error then
        ngx.log(ngx.ERR, "Failed to count pending users: " .. count_error)
        send_json(503, { error = "Service temporarily unavailable" })
    end
    
    if pending_count >= MAX_PENDING_USERS then
        ngx.shared.guest_sessions:set(register_key, attempts + 1, 600)
        ngx.log(ngx.WARN, "Registration blocked - pending user limit reached (" .. pending_count .. "/" .. MAX_PENDING_USERS .. ")")
        send_json(429, { 
            error = "Registration temporarily unavailable",
            message = "Maximum number of pending registrations reached. Please try again later.",
            details = {
                pending_users = pending_count,
                max_pending = MAX_PENDING_USERS,
                retry_suggestion = "Please try again in a few hours when existing registrations are processed"
            }
        })
    end

    -- SECURITY: Hash password before storing
    local password_hash = hash_password(password)

    -- CRITICAL: Create user as PENDING (is_pending = true)
    local success, message = create_user(username, password_hash, ngx.var.remote_addr)
    
    if not success then
        ngx.shared.guest_sessions:set(register_key, attempts + 1, 600)
        ngx.log(ngx.ERR, "Registration failed for " .. username .. ": " .. message)
        send_json(500, { error = "Registration failed: " .. message })
    end

    -- SECURITY: Clear failed attempts on successful registration
    ngx.shared.guest_sessions:delete(register_key)

    -- Log successful registration with pending count
    ngx.log(ngx.INFO, "New user registered (pending approval): " .. username .. 
            " | Pending users: " .. (pending_count + 1) .. "/" .. MAX_PENDING_USERS)

    -- IMPORTANT: NO JWT TOKEN - user must be approved first
    send_json(200, { 
        success = true,
        message = "Registration successful! Your account is pending admin approval.",
        user = {
            username = username,
            status = "pending_approval",
            user_type = "is_pending",
            created_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
        },
        queue_info = {
            pending_users = pending_count + 1,
            max_pending = MAX_PENDING_USERS,
            position_in_queue = pending_count + 1
        },
        next_steps = {
            "Wait for administrator approval",
            "You will be able to login once approved",
            "Approval usually takes 24-48 hours"
        },
        redirect = "/login"
    })
end

-- SECURITY: Registration status check (for pending users)
local function handle_registration_status()
    local user_type, username, user_data = auth.check()
    
    if user_type == "is_pending" then
        -- User has JWT but not approved
        local pending_count, _ = count_pending_users()
        
        send_json(200, {
            success = false,
            status = "pending_approval",
            username = username,
            user_type = "is_pending",
            message = "Your account is pending administrator approval",
            created_at = user_data.created_at,
            queue_info = {
                total_pending = pending_count,
                max_pending = MAX_PENDING_USERS
            }
        })
    else
        send_json(401, {
            success = false,
            error = "Not authenticated",
            message = "Please login to check registration status"
        })
    end
end

-- Get registration statistics (for debugging/monitoring)
local function handle_registration_stats()
    local pending_count, count_error = count_pending_users()
    
    if count_error then
        send_json(500, { error = "Failed to get registration stats" })
    end
    
    send_json(200, {
        success = true,
        stats = {
            pending_users = pending_count,
            max_pending = MAX_PENDING_USERS,
            slots_available = MAX_PENDING_USERS - pending_count,
            registration_open = (pending_count < MAX_PENDING_USERS)
        },
        message = pending_count >= MAX_PENDING_USERS and 
                  "Registration temporarily closed" or 
                  "Registration open"
    })
end

-- SECURE registration routing
local function handle_register_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method

    if uri == "/api/register" and method == "POST" then
        handle_register()
    elseif uri == "/api/register/status" and method == "GET" then
        handle_registration_status()
    elseif uri == "/api/register/stats" and method == "GET" then
        handle_registration_stats()
    else
        send_json(404, { 
            error = "Registration endpoint not found",
            available_endpoints = {
                "POST /api/register - Create new user account",
                "GET /api/register/status - Check registration status",
                "GET /api/register/stats - Get registration statistics"
            }
        })
    end
end

return {
    handle_register = handle_register,
    handle_register_api = handle_register_api,
    count_pending_users = count_pending_users
}