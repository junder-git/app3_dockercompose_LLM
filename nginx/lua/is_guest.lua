-- =============================================================================
-- nginx/lua/is_guest.lua - FIXED TO PREVENT DUPLICATE SESSIONS
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local auth = require "manage_auth"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local M = {}

-- Helper function to send JSON response and exit
local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- Guest name generation
local ADJECTIVES = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural", "Cosmic"}
local ANIMALS = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}

local function generate_guest_name()
    local adjective = ADJECTIVES[math.random(#ADJECTIVES)]
    local animal = ANIMALS[math.random(#ANIMALS)]
    local number = math.random(100, 999)
    return adjective .. animal .. number
end

-- =============================================
-- FIND AVAILABLE GUEST SLOT OR REUSE INACTIVE SESSION
-- =============================================

local function find_or_create_guest_slot()
    local red = auth.connect_redis()
    if not red then
        return nil, nil, "Redis connection failed"
    end
    
    local current_time = ngx.time()
    
    -- Check guest_user_1 specifically (our single guest slot)
    local guest_username = "guest_user_1"
    local user_key = "username:" .. guest_username
    
    -- Check if guest_user_1 exists
    local existing_data = red:hgetall(user_key)
    
    if existing_data and #existing_data > 0 then
        -- Parse existing session data
        local session = {}
        for i = 1, #existing_data, 2 do
            local field = existing_data[i]
            local value = existing_data[i + 1]
            if value == ngx.null then value = nil end
            session[field] = value
        end
        
        local last_activity = tonumber(session.last_activity) or 0
        local is_active = session.is_active == "true"
        local session_age = current_time - last_activity
        
        ngx.log(ngx.INFO, string.format("🔍 Found existing guest_user_1: active=%s, age=%ds", 
            tostring(is_active), session_age))
        
        -- If session is active and recent (< 60 seconds), deny access
        if is_active and session_age <= 60 then
            red:close()
            return nil, nil, string.format("Guest session is currently active (last seen %ds ago)", session_age)
        end
        
        -- If session is inactive or old, we can reuse it
        if not is_active or session_age > 60 then
            ngx.log(ngx.INFO, string.format("♻️ Reusing inactive guest session (age: %ds)", session_age))
            -- We'll overwrite this session
            return guest_username, user_key, nil
        end
    else
        ngx.log(ngx.INFO, "✨ No existing guest_user_1 found, creating new session")
    end
    
    red:close()
    return guest_username, user_key, nil
end

-- =============================================
-- GUEST SESSION CREATION WITH COLLISION PREVENTION
-- =============================================

function M.handle_create_session()
    ngx.log(ngx.INFO, "✅ is_guest: Creating guest session (called by is_none.lua)")
    
    -- Find available guest slot or reuse inactive session
    local guest_username, user_key, error_msg = find_or_create_guest_slot()
    
    if not guest_username then
        ngx.log(ngx.WARN, "❌ Cannot create guest session: " .. (error_msg or "unknown error"))
        send_json(409, {
            success = false,
            error = "Guest session unavailable",
            message = error_msg or "Cannot create guest session",
            reason = "guest_slot_occupied"
        })
    end
    
    local now = ngx.time()
    local display_name = generate_guest_name()
    
    -- Create/overwrite guest user in Redis
    local red = auth.connect_redis()
    if not red then
        send_json(500, {
            success = false,
            error = "Database connection failed"
        })
    end
    
    -- CRITICAL: Always delete the old session first to prevent conflicts
    red:del(user_key)
    
    -- Create fresh session
    local ok, err = red:hmset(user_key,
        "username", guest_username,
        "user_type", "is_guest",
        "display_name", display_name,
        "created_at", os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "last_activity", now,
        "is_active", "true",  -- CRITICAL: Set as active
        "created_ip", ngx.var.remote_addr or "unknown",
        "session_id", tostring(now) .. "_" .. math.random(1000, 9999)  -- Unique session ID
    )
    
    if not ok then
        red:close()
        send_json(500, {
            success = false,
            error = "Failed to create guest session: " .. tostring(err)
        })
    end
    
    -- Set expiration for guest user (1 hour)
    red:expire(user_key, 3600)
    red:close()
    
    -- Create JWT token
    local payload = {
        username = guest_username,
        user_type = "is_guest",
        display_name = display_name,
        last_activity = now,
        iat = now,
        exp = now + 3600
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    ngx.log(ngx.INFO, "✅ Guest session created/reused: " .. display_name .. " -> " .. guest_username)
    
    -- Set cookie and return response
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600"
    
    send_json(200, {
        success = true,
        message = "Guest session created - cookie set",
        username = display_name,
        internal_username = guest_username,
        user_type = "is_guest",
        cookie_set = true,
        slot = 1,
        session_expires_in = 3600
    })
end

return M