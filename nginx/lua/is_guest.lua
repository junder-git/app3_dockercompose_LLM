-- =============================================================================
-- nginx/lua/is_guest.lua - HARDCODED JWT WITH RANDOM UI USERNAMES + PERSISTENT CHAT
-- =============================================================================

local cjson = require "cjson"
local redis = require "resty.redis"
local jwt = require "resty.jwt"

local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

-- Configuration
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 120  -- 2 minutes
local GUEST_MESSAGE_LIMIT = 10
local GUEST_CHAT_RETENTION = 259200  -- 3 days

local USERNAME_POOLS = {
    {
        adjectives = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool"},
        animals = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog"}
    },
    {
        adjectives = {"Cosmic", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural"},
        animals = {"Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}
    }
}

-- HARDCODED GUEST ACCOUNTS - Simple username-based like regular users
local GUEST_ACCOUNTS = {
    {
        slot_number = 1,
        username = "guest_slot_1",
        password = "placeholder_token_1",  -- Fixed password for this slot
        token = ""  -- JWT token will be generated/retrieved
    },
    {
        slot_number = 2,
        username = "guest_slot_2",
        password = "placeholder_token_2",  -- Fixed password for this slot
        token = ""  -- JWT token will be generated/retrieved
    }
}

local function generate_guest_jwts()
    for i, guest_data in ipairs(GUEST_ACCOUNTS) do
        local payload = {
            username = guest_data.username,
            user_type = "guest",
            priority = 3,
            slot_number = guest_data.slot_number,
            iat = ngx.time(),
            exp = 9999999999
        }
        local token = jwt:sign(JWT_SECRET, {
            header = { typ = "JWT", alg = "HS256" },
            payload = payload
        })
        GUEST_ACCOUNTS[i].token = token
        ngx.log(ngx.INFO, "Generated JWT for " .. guest_data.username)
    end
end

generate_guest_jwts()

local function redis_to_lua(value)
    if value == ngx.null or value == nil then return nil end
    return value
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

local function generate_display_username(slot_number)
    local red = connect_redis()
    if not red then
        local pool = USERNAME_POOLS[slot_number] or USERNAME_POOLS[1]
        return pool.adjectives[math.random(#pool.adjectives)] ..
               pool.animals[math.random(#pool.animals)] ..
               tostring(math.random(100, 999))
    end

    local pool = USERNAME_POOLS[slot_number] or USERNAME_POOLS[1]
    local max_attempts, attempts = 3, 0

    while attempts < max_attempts do
        local adjective = pool.adjectives[math.random(#pool.adjectives)]
        local animal = pool.animals[math.random(#pool.animals)]
        local number = math.random(100, 999)
        local candidate = adjective .. animal .. number
        local key = "guest_username_blacklist:" .. candidate

        if not redis_to_lua(red:get(key)) then
            red:set(key, "1")
            red:expire(key, GUEST_CHAT_RETENTION + 3600)
            ngx.log(ngx.INFO, "Generated unique session username: " .. candidate)
            return candidate
        end

        attempts = attempts + 1
    end

    local adjective = pool.adjectives[math.random(#pool.adjectives)]
    local animal = pool.animals[math.random(#pool.animals)]
    local fallback = adjective .. animal .. tostring(ngx.time()):sub(-4)
    local key = "guest_username_blacklist:" .. fallback
    red:set(key, "1")
    red:expire(key, GUEST_CHAT_RETENTION + 3600)
    ngx.log(ngx.WARN, "Used fallback username: " .. fallback)
    return fallback
end

local function find_available_guest_slot()
    local red = connect_redis()
    if not red then return nil, "Service unavailable" end

    for i = 1, MAX_GUEST_SESSIONS do
        local key = "guest_active_session:" .. i
        local data = redis_to_lua(red:get(key))

        if not data then
            return GUEST_ACCOUNTS[i], nil
        else
            local ok, session = pcall(cjson.decode, data)
            if ok and session.expires_at and ngx.time() >= session.expires_at then
                red:del(key)
                return GUEST_ACCOUNTS[i], nil
            end
        end
    end
    return nil, "All guest slots occupied"
end

local function create_secure_guest_session()
    ngx.log(ngx.INFO, "=== GUEST SESSION CREATION START ===")

    local account, err = find_available_guest_slot()
    if not account then
        ngx.log(ngx.WARN, "No available guest slot: " .. (err or "unknown"))
        return nil, err
    end

    local red = connect_redis()
    if not red then return nil, "Service unavailable" end

    local display_name = generate_display_username(account.slot_number)
    local now = ngx.time()
    local expires_at = now + GUEST_SESSION_DURATION

    local session = {
        username = account.username,
        user_type = "guest",
        jwt_token = account.token,
        slot_number = account.slot_number,
        session_id = display_name,
        display_username = display_name,
        created_at = now,
        expires_at = expires_at,
        message_count = 0,
        max_messages = GUEST_MESSAGE_LIMIT,
        created_ip = ngx.var.remote_addr or "unknown",
        last_activity = now,
        priority = 3,
        chat_storage = "redis",
        chat_retention_until = now + GUEST_CHAT_RETENTION
    }

    local key = "guest_active_session:" .. account.slot_number
    red:set(key, cjson.encode(session))
    red:expire(key, GUEST_SESSION_DURATION)

    local user_key = "guest_session:" .. account.username
    red:set(user_key, cjson.encode(session))
    red:expire(user_key, GUEST_SESSION_DURATION)

    local chat_key = "chat_history:guest:" .. display_name
    local chat_record = {
        session_id = display_name,
        internal_username = account.username,
        display_username = display_name,
        slot_number = account.slot_number,
        user_type = "guest",
        created_at = now,
        created_ip = ngx.var.remote_addr or "unknown",
        expires_at = expires_at,
        chat_retention_until = now + GUEST_CHAT_RETENTION,
        messages = {},
        last_activity = now,
        session_active = true
    }
    red:set(chat_key, cjson.encode(chat_record))
    red:expire(chat_key, GUEST_CHAT_RETENTION)

    red:set("current_chat_session:" .. account.username, display_name)
    red:expire("current_chat_session:" .. account.username, GUEST_SESSION_DURATION)

    local admin_key = "admin:guest_sessions"
    red:sadd(admin_key, display_name)
    red:expire(admin_key, GUEST_CHAT_RETENTION)

    ngx.header["Set-Cookie"] = "access_token=" .. account.token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION

    ngx.log(ngx.INFO, "=== GUEST SESSION CREATION SUCCESS ===")
    ngx.log(ngx.INFO, "Created session: " .. display_name .. " -> " .. account.username .. " [Slot " .. account.slot_number .. "]")

    return {
        success = true,
        username = display_name,
        internal_username = account.username,
        session_id = display_name,
        token = account.token,
        expires_at = expires_at,
        message_limit = GUEST_MESSAGE_LIMIT,
        session_duration = GUEST_SESSION_DURATION,
        priority = 3,
        slot_number = account.slot_number,
        storage_type = "redis",
        chat_retention_days = math.floor(GUEST_CHAT_RETENTION / 86400)
    }, nil
end

local function validate_guest_session(token)
    if not token then return nil, "No token provided" end

    local valid_account
    for _, acc in ipairs(GUEST_ACCOUNTS) do
        if acc.token == token then
            valid_account = acc
            break
        end
    end
    if not valid_account then return nil, "Invalid guest token" end

    local jwt_obj = jwt:verify(JWT_SECRET, token)
    if not jwt_obj.verified then return nil, "JWT verification failed" end

    local payload = jwt_obj.payload
    if payload.username ~= valid_account.username or payload.user_type ~= "guest" then
        return nil, "JWT payload mismatch"
    end

    local red = connect_redis()
    if not red then return nil, "Service unavailable" end

    local key = "guest_session:" .. valid_account.username
    local data = redis_to_lua(red:get(key))
    if not data then return nil, "No active session" end

    local ok, session = pcall(cjson.decode, data)
    if not ok then return nil, "Invalid session data" end

    if ngx.time() >= session.expires_at then
        return nil, "Session expired"
    end

    session.last_activity = ngx.time()
    red:set(key, cjson.encode(session))
    red:expire(key, GUEST_SESSION_DURATION)

    return session, nil
end

return {
    create_secure_guest_session = create_secure_guest_session,
    validate_guest_session = validate_guest_session,
    generate_display_username = generate_display_username
}
