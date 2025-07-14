-- nginx/lua/register.lua - User registration handler
local cjson = require "cjson"
local server = require "server"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

local function hash_password(password)
    local hash_cmd = string.format("printf '%%s%%s' '%s' '%s' | openssl dgst -sha256 -hex | cut -d' ' -f2",
                                   password:gsub("'", "'\"'\"'"), JWT_SECRET)
    local handle = io.popen(hash_cmd)
    local hash = handle:read("*a"):gsub("\n", "")
    handle:close()
    return hash
end

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

    -- Validate username format
    if not string.match(username, "^[a-zA-Z0-9_]{3,20}$") then
        send_json(400, { error = "Username must be 3-20 characters, letters/numbers/underscore only" })
    end

    -- Validate password length
    if string.len(password) < 6 then
        send_json(400, { error = "Password must be at least 6 characters" })
    end

    -- Hash password
    local password_hash = hash_password(password)

    -- Create user (is_approved = false, pending admin approval)
    local success, message = server.create_user(username, password_hash)
    
    if not success then
        if message == "User already exists" then
            send_json(409, { error = "Username already taken" })
        else
            send_json(500, { error = message })
        end
    end

    send_json(200, { 
        message = "User registered successfully. Your account is pending admin approval.",
        username = username,
        status = "pending_approval"
    })
end

return {
    handle_register = handle_register
}