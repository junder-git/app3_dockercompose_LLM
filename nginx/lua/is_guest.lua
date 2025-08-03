-- =============================================================================
-- nginx/lua/manage_guest.lua - GUEST SESSION CREATION
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local auth = require "manage_auth"

local JWT_SECRET = os.getenv("JWT_SECRET") or "super-secret-key-CHANGE"

local M = {}

-- =============================================
-- GUEST NAME GENERATION
-- =============================================

local ADJECTIVES = {"Quick", "Silent", "Bright", "Swift", "Clever", "Bold", "Calm", "Sharp", "Wise", "Cool", "Neon", "Digital", "Cyber", "Quantum", "Electric", "Plasma", "Stellar", "Virtual", "Neural", "Cosmic"}
local ANIMALS = {"Fox", "Eagle", "Wolf", "Tiger", "Hawk", "Bear", "Lion", "Owl", "Cat", "Dog", "Phoenix", "Dragon", "Falcon", "Panther", "Raven", "Shark", "Viper", "Lynx", "Gecko", "Mantis"}

local function generate_guest_name()
    local adjective = ADJECTIVES[math.random(#ADJECTIVES)]
    local animal = ANIMALS[math.random(#ANIMALS)]
    local number = math.random(100, 999)
    return adjective .. animal .. number
end

-- =============================================
-- GUEST SESSION CREATION
-- =============================================

function M.handle_create_session()
    local now = ngx.time()
    local slot_number = 1
    local guest_username = "guest_user_" .. slot_number
    local display_name = generate_guest_name()
    
    -- Create guest user in Redis with proper structure
    local red = auth.connect_redis()
    if not red then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Database connection failed"
        }))
        return
    end
    
    local user_key = "username:" .. guest_username
    local ok, err = red:hmset(user_key,
        "username", guest_username,
        "user_type", "guest",
        "display_name", display_name,
        "created_at", os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "last_activity", now
    )
    
    -- Set expiration for guest user (1 hour)
    red:expire(user_key, 3600)
    red:close()
    
    if not ok then
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Failed to create guest session: " .. tostring(err)
        }))
        return
    end
    
    -- Create JWT token with username field (consistent with regular users)
    local payload = {
        username = guest_username, -- Actual username for Redis lookup
        display_name = display_name, -- What the client sees
        last_activity = now,
        iat = now,
        exp = now + 3600  -- 1 hour expiration for guests
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    ngx.log(ngx.INFO, "✅ Guest session created: " .. display_name .. " -> " .. guest_username .. " (slot " .. slot_number .. ")")
    
    -- Set cookie and return response
    ngx.header["Set-Cookie"] = "access_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600"
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        username = display_name,
        internal_username = guest_username,
        token = token,
        slot = slot_number,
        redirect = "/chat"
    }))
end

return M