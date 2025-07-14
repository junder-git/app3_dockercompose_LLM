-- nginx/lua/register.lua - SECURE user registration handler
local cjson = require "cjson"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- SECURE password hashing - same as login
local function hash_password(password)
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    return hash
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
    
    -- Reserved usernames
    local reserved = {"admin", "root", "system", "api", "www", "mail", "ftp", "guest", "anonymous"}
    for _, reserved_name in ipairs(reserved) do
        if string.lower(username) == reserved_name then
            return false, "Username is reserved"
        end
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
    local weak_passwords = {"password", "123456", "password123", "admin", "qwerty", "letmein"}
    for _, weak in ipairs(weak_passwords) do
        if string.lower(password) == weak then
            return false, "Password is too weak"
        end
    end
    
    return true, "Valid password"
end

-- CRITICAL: Registration creates pending user (NO JWT until approved)
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

    -- SECURITY: Rate limit registration attempts
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

    -- SECURITY: Hash password before storing
    local password_hash = hash_password(password)

    -- CRITICAL: Create user as PENDING (is_approved = false)
    local success, message = server.create_user(username, password_hash)
    
    if not success then
        ngx.shared.guest_sessions:set(register_key, attempts + 1, 600)
        
        if message == "User already exists" then
            ngx.log(ngx.WARN, "Registration attempt with existing username: " .. username)
            send_json(409, { error = "Username already taken" })
        else
            ngx.log(ngx.ERR, "Registration failed for " .. username .. ": " .. message)
            send_json(500, { error = "Registration failed" })
        end
    end

    -- SECURITY: Clear failed attempts on successful registration
    ngx.shared.guest_sessions:delete(register_key)

    ngx.log(ngx.INFO, "New user registered (pending approval): " .. username)

    -- IMPORTANT: NO JWT TOKEN - user must be approved first
    send_json(200, { 
        success = true,
        message = "User registered successfully. Your account is pending admin approval.",
        user = {
            username = username,
            status = "pending_approval",
            is_approved = false,
            is_admin = false,
            created_at = os.date("!%Y-%m-%dT%TZ")
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
    local is_who = require "is_who"
    local user_type, username, user_data = is_who.check()
    
    if user_type == "authenticated" then
        -- User has JWT but not approved
        send_json(200, {
            success = false,
            status = "pending_approval",
            username = username,
            is_approved = false,
            message = "Your account is pending administrator approval",
            created_at = user_data.created_at
        })
    else
        send_json(401, {
            success = false,
            error = "Not authenticated",
            message = "Please login to check registration status"
        })
    end
end

-- SECURE registration routing
local function handle_register_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method

    if uri == "/api/register" and method == "POST" then
        handle_register()
    elseif uri == "/api/register/status" and method == "GET" then
        handle_registration_status()
    else
        send_json(404, { error = "Registration endpoint not found" })
    end
end

return {
    handle_register = handle_register,
    handle_register_api = handle_register_api
}