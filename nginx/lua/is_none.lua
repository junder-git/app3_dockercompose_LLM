-- =============================================================================
-- nginx/lua/is_none.lua - GUEST SESSION CREATION WITH SERVER-SIDE REDIRECT FIX
-- =============================================================================

local cjson = require "cjson"
local jwt = require "resty.jwt"

local JWT_SECRET = os.getenv("JWT_SECRET")
local MAX_GUEST_SESSIONS = 2
local GUEST_SESSION_DURATION = 600  -- 10 minutes
local GUEST_MESSAGE_LIMIT = 10
local CHALLENGE_TIMEOUT = 8  -- 8 seconds for challenge response
local INACTIVE_THRESHOLD = 30  -- 30 seconds to be considered inactive

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
-- LUA SHARED MEMORY FOR GUEST SESSIONS AND CHALLENGES
-- =============================================

-- Get guest slot status with challenge detection
local function get_guest_slot_status()
    local active_sessions = 0
    local available_slot = nil
    local sessions = {}
    local challengeable_slot = nil
    
    -- Check both guest slots
    for i = 1, MAX_GUEST_SESSIONS do
        local slot_key = "guest_session_" .. i
        local session_data = ngx.shared.guest_sessions:get(slot_key)
        
        if session_data then
            local ok, session = pcall(cjson.decode, session_data)
            if ok and session.expires_at > ngx.time() then
                -- Session is still valid
                active_sessions = active_sessions + 1
                sessions[i] = session
                
                -- Check if user is inactive (potential challenge target)
                local inactive_time = ngx.time() - (session.last_activity or session.created_at)
                if inactive_time > INACTIVE_THRESHOLD and not challengeable_slot then
                    challengeable_slot = i
                end
            else
                -- Session expired, clear it
                ngx.shared.guest_sessions:delete(slot_key)
                if not available_slot then
                    available_slot = i
                end
            end
        else
            -- Slot is empty
            if not available_slot then
                available_slot = i
            end
        end
    end
    
    return {
        active_sessions = active_sessions,
        available_slots = MAX_GUEST_SESSIONS - active_sessions,
        available_slot = available_slot,
        challengeable_slot = challengeable_slot,
        slots_full = active_sessions >= MAX_GUEST_SESSIONS,
        sessions = sessions
    }
end

-- =============================================
-- CHALLENGE SYSTEM
-- =============================================

local function create_challenge(slot_number)
    if not slot_number then
        return false, "No slot number provided"
    end
    
    local challenge_key = "guest_challenge_" .. slot_number
    local existing_challenge = ngx.shared.guest_sessions:get(challenge_key)
    
    if existing_challenge then
        local ok, challenge_data = pcall(cjson.decode, existing_challenge)
        if ok and challenge_data.expires_at > ngx.time() then
            return false, "Challenge already active for slot " .. slot_number
        end
    end
    
    local challenge_id = "challenge_" .. slot_number .. "_" .. ngx.time() .. "_" .. math.random(1000, 9999)
    local challenge = {
        challenge_id = challenge_id,
        slot_number = slot_number,
        created_at = ngx.time(),
        expires_at = ngx.time() + CHALLENGE_TIMEOUT,
        status = "pending"
    }
    
    ngx.shared.guest_sessions:set(challenge_key, cjson.encode(challenge), CHALLENGE_TIMEOUT + 5)
    
    ngx.log(ngx.INFO, "🚨 Challenge created for slot " .. slot_number)
    return true, challenge_id
end

local function get_challenge_status(slot_number)
    if not slot_number then
        return nil
    end
    
    local challenge_key = "guest_challenge_" .. slot_number
    local challenge_data = ngx.shared.guest_sessions:get(challenge_key)
    
    if not challenge_data then
        return nil
    end
    
    local ok, challenge = pcall(cjson.decode, challenge_data)
    if not ok then
        ngx.shared.guest_sessions:delete(challenge_key)
        return nil
    end
    
    if challenge.expires_at <= ngx.time() then
        -- Challenge expired - inactive user gets auto-kicked when new session is created
        ngx.log(ngx.WARN, "🚨 Challenge expired for slot " .. slot_number .. " - slot will be overwritten")
        
        -- Clean up expired challenge (session will be overwritten naturally)
        ngx.shared.guest_sessions:delete(challenge_key)
        
        return nil
    end
    
    return challenge
end

local function respond_to_challenge(slot_number, response)
    if not slot_number then
        return false, "No slot number provided"
    end
    
    local challenge_key = "guest_challenge_" .. slot_number
    local challenge_data = ngx.shared.guest_sessions:get(challenge_key)
    
    if not challenge_data then
        return false, "No active challenge"
    end
    
    local ok, challenge = pcall(cjson.decode, challenge_data)
    if not ok then
        ngx.shared.guest_sessions:delete(challenge_key)
        return false, "Invalid challenge data"
    end
    
    if challenge.expires_at <= ngx.time() then
        ngx.shared.guest_sessions:delete(challenge_key)
        return false, "Challenge expired"
    end
    
    challenge.response = response
    challenge.responded_at = ngx.time()
    challenge.status = response == "accept" and "accepted" or "rejected"
    
    ngx.shared.guest_sessions:set(challenge_key, cjson.encode(challenge), 60)
    
    ngx.log(ngx.INFO, "✅ Challenge response for slot " .. slot_number .. ": " .. response)
    return true, challenge.status
end

-- =============================================
-- GUEST SESSION CREATION WITH CHALLENGE SUPPORT
-- =============================================

local function create_guest_session()
    local status = get_guest_slot_status()
    
    if not status.slots_full then
        -- Normal path - slot available
        local slot_number = status.available_slot
        local guest_username = "guest_user_" .. slot_number
        local display_name = generate_guest_name()
        local now = ngx.time()
        local expires_at = now + GUEST_SESSION_DURATION
        
        -- Create session data
        local session = {
            slot = slot_number,
            username = guest_username,
            display_name = display_name,
            created_at = now,
            expires_at = expires_at,
            message_count = 0,
            max_messages = GUEST_MESSAGE_LIMIT,
            last_activity = now
        }
        
        -- Store in Lua shared memory (overwrites any existing session in this slot)
        local slot_key = "guest_session_" .. slot_number
        local success, err = ngx.shared.guest_sessions:set(slot_key, cjson.encode(session), GUEST_SESSION_DURATION + 60)
        
        if not success then
            return nil, "Failed to store session: " .. (err or "unknown")
        end
        
        -- Create JWT token with ONLY client-facing data
        local payload = {
            display_username = display_name, -- What the client sees (QuickFox123)
            created_at = now,
            expires_at = expires_at,
            message_count = 0,
            max_messages = GUEST_MESSAGE_LIMIT,
            last_activity = now,
            iat = now,
            exp = expires_at
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
            expires_at = expires_at,
            message_limit = GUEST_MESSAGE_LIMIT,
            session_duration = GUEST_SESSION_DURATION,
            token = token,
            slot = slot_number
        }, nil
        
    elseif status.challengeable_slot then
        -- Challenge path - need to challenge inactive user
        local slot_number = status.challengeable_slot
        local success, challenge_id = create_challenge(slot_number)
        
        if success then
            return {
                challenge_required = true,
                challenge_id = challenge_id,
                slot_number = slot_number,
                timeout = CHALLENGE_TIMEOUT,
                message = "An inactive user is using this slot. They have " .. CHALLENGE_TIMEOUT .. " seconds to respond or will be disconnected."
            }, nil
        else
            return nil, "Failed to create challenge: " .. (challenge_id or "unknown")
        end
        
    else
        -- All slots busy with active users
        return nil, "All guest sessions are occupied with active users"
    end
end

-- =============================================
-- API HANDLERS
-- =============================================

local function handle_create_session()
    local session_data, error_msg = create_guest_session()
    
    if not session_data then
        if error_msg == "All guest sessions are occupied with active users" then
            ngx.status = 429
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                error = "slots_full",
                message = "All guest sessions are occupied with active users. Please try again in a few minutes."
            }))
        else
            ngx.status = 503
            ngx.header.content_type = 'application/json'
            ngx.say(cjson.encode({
                success = false,
                error = "service_error",
                message = error_msg or "Failed to create guest session"
            }))
        end
        return
    end
    
    if session_data.challenge_required then
        -- Challenge is required - return challenge info
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode(session_data))
        return
    end
    
    -- CRITICAL FIX: Normal session creation - SET COOKIE BEFORE REDIRECT
    -- Set the JWT cookie first
    ngx.header["Set-Cookie"] = "access_token=" .. session_data.token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
    
    ngx.log(ngx.INFO, "🍪 Cookie set for guest: " .. session_data.username)
    
    -- FIXED: Use HTTP 302 redirect instead of JSON response
    ngx.status = 302
    ngx.header["Location"] = "/chat"
    ngx.header.content_type = 'text/html'
    
    -- Optional: Simple HTML for browsers that don't follow redirects immediately
    ngx.say([[
        <!DOCTYPE html>
        <html>
        <head>
            <meta http-equiv="refresh" content="0;url=/chat">
            <title>Redirecting...</title>
        </head>
        <body>
            <p>Guest session created! Redirecting to chat...</p>
            <script>window.location.href = '/chat';</script>
        </body>
        </html>
    ]])
end

local function handle_challenge_status()
    local slot_number = tonumber(ngx.var.arg_slot)
    if not slot_number then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "slot parameter required" }))
        return
    end
    
    local challenge = get_challenge_status(slot_number)
    if challenge then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            challenge_active = true,
            challenge = challenge,
            remaining_time = challenge.expires_at - ngx.time()
        }))
    else
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            challenge_active = false,
            message = "No active challenge"
        }))
    end
end

local function handle_challenge_response()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "Request body required" }))
        return
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "Invalid JSON" }))
        return
    end
    
    local slot_number = data.slot_number
    local response = data.response
    
    if not slot_number or not response then
        ngx.status = 400
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({ error = "slot_number and response required" }))
        return
    end
    
    local success, result = respond_to_challenge(slot_number, response)
    if success then
        ngx.status = 200
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = true,
            challenge_result = result,
            message = result == "accepted" and "Challenge accepted" or "Challenge rejected"
        }))
    else
        ngx.status = 500
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = result,
            message = "Challenge response failed"
        }))
    end
end

local function handle_guest_stats()
    local status = get_guest_slot_status()
    
    -- Count active challenges
    local challenges_active = 0
    for i = 1, MAX_GUEST_SESSIONS do
        if get_challenge_status(i) then
            challenges_active = challenges_active + 1
        end
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        stats = {
            active_sessions = status.active_sessions,
            max_sessions = MAX_GUEST_SESSIONS,
            available_slots = status.available_slots,
            challenges_active = challenges_active,
            registration_available = not status.slots_full
        }
    }))
end

-- =============================================
-- MAIN API HANDLER FOR IS_NONE USERS
-- =============================================

function M.handle_guest_session_api()
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/guest/create-session" and method == "POST" then
        handle_create_session()
    elseif uri == "/api/guest/challenge-status" and method == "GET" then
        handle_challenge_status()
    elseif uri == "/api/guest/challenge-response" and method == "POST" then
        handle_challenge_response()
    elseif uri == "/api/guest/stats" and method == "GET" then
        handle_guest_stats()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Endpoint not found",
            available_endpoints = {
                "POST /api/guest/create-session",
                "GET /api/guest/challenge-status?slot=N",
                "POST /api/guest/challenge-response",
                "GET /api/guest/stats"
            }
        }))
    end
end

-- =============================================
-- HELPER FUNCTIONS FOR OTHER MODULES
-- =============================================

function M.get_guest_stats()
    local status = get_guest_slot_status()
    local challenges_active = 0
    for i = 1, MAX_GUEST_SESSIONS do
        if get_challenge_status(i) then
            challenges_active = challenges_active + 1
        end
    end
    
    return {
        active_sessions = status.active_sessions,
        max_sessions = MAX_GUEST_SESSIONS,
        available_slots = status.available_slots,
        challenges_active = challenges_active
    }
end

function M.get_session(slot_number)
    if not slot_number then
        return nil
    end
    
    local slot_key = "guest_session_" .. slot_number
    local session_data = ngx.shared.guest_sessions:get(slot_key)
    
    if not session_data then
        return nil
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        return nil
    end
    
    if session.expires_at <= ngx.time() then
        ngx.shared.guest_sessions:delete(slot_key)
        return nil
    end
    
    return session
end

function M.update_message_count(slot_number, current_count)
    if not slot_number then
        return false, "No slot number provided"
    end
    
    local slot_key = "guest_session_" .. slot_number
    local session_data = ngx.shared.guest_sessions:get(slot_key)
    
    if not session_data then
        return false, "Session not found"
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        return false, "Invalid session data"
    end
    
    if session.expires_at <= ngx.time() then
        ngx.shared.guest_sessions:delete(slot_key)
        return false, "Session expired"
    end
    
    local new_count = (current_count or session.message_count or 0) + 1
    
    if new_count > session.max_messages then
        return false, "Message limit exceeded"
    end
    
    -- Update session in shared memory
    session.message_count = new_count
    session.last_activity = ngx.time()
    
    ngx.shared.guest_sessions:set(slot_key, cjson.encode(session), GUEST_SESSION_DURATION + 60)
    
    -- Create new JWT with updated count
    local token = ngx.var.cookie_access_token
    if token then
        local jwt_obj = jwt:verify(JWT_SECRET, token)
        if jwt_obj.verified then
            local new_payload = {}
            for k, v in pairs(jwt_obj.payload) do
                new_payload[k] = v
            end
            new_payload.message_count = new_count
            new_payload.last_activity = ngx.time()
            
            local new_token = jwt:sign(JWT_SECRET, {
                header = { typ = "JWT", alg = "HS256" },
                payload = new_payload
            })
            
            -- Update cookie
            ngx.header["Set-Cookie"] = "access_token=" .. new_token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. GUEST_SESSION_DURATION
        end
    end
    
    ngx.log(ngx.INFO, "Guest message count updated: " .. new_count .. "/" .. session.max_messages .. " (slot " .. slot_number .. ")")
    
    return true, new_count
end

function M.update_session_activity(slot_number)
    if not slot_number then
        return false
    end
    
    local slot_key = "guest_session_" .. slot_number
    local session_data = ngx.shared.guest_sessions:get(slot_key)
    
    if not session_data then
        return false
    end
    
    local ok, session = pcall(cjson.decode, session_data)
    if not ok then
        return false
    end
    
    if session.expires_at <= ngx.time() then
        ngx.shared.guest_sessions:delete(slot_key)
        return false
    end
    
    -- Update last activity
    session.last_activity = ngx.time()
    ngx.shared.guest_sessions:set(slot_key, cjson.encode(session), GUEST_SESSION_DURATION + 60)
    
    return true
end

-- =============================================
-- ROUTE HANDLER
-- =============================================

function M.handle_route(route_type)
    if route_type == "guest_api" then
        return M.handle_guest_session_api()
    else
        ngx.status = 404
        return ngx.say("Route not found for anonymous users: " .. tostring(route_type))
    end
end

return M