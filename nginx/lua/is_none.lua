-- =============================================================================
-- nginx/lua/is_none.lua - GUEST SESSION CREATION WITH SERVER-SIDE REDIRECT FIX
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"
local JWT_SECRET = os.getenv("JWT_SECRET")
local MAX_GUEST_SESSIONS = 1
local INACTIVE_THRESHOLD = 60  -- 60 seconds to be considered inactive
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

local function create_guest_session()
    local slot_number = 1
    local guest_username = "guest_user_" .. slot_number
    local display_name = generate_guest_name()
    
    -- Create session data
    local session = {
        slot = slot_number,
        username = guest_username,
        display_name = display_name,
        last_activity = now
    }
    
    -- Store in Lua shared memory (overwrites any existing session in this slot)
    local slot_key = "guest_session_" .. slot_number
    
    -- Create JWT token with ONLY client-facing data
    local payload = {
        display_username = display_name, -- What the client sees (QuickFox123)
        last_activity = now
    }
    
    local token = jwt:sign(JWT_SECRET, {
        header = { typ = "JWT", alg = "HS256" },
        payload = payload
    })
    
    ngx.log(ngx.INFO, "✅ Guest session created: " .. display_name .. " -> " .. guest_username .. " (slot " .. slot_number .. ")")
    
    return {
        success = true,
        username = display_name,
        internal_username = guest_username,
        token = token,
        slot = slot_number
    }

return M