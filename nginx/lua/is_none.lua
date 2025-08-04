-- =============================================================================
-- nginx/lua/is_none.lua - SIMPLIFIED - LET is_guest HANDLE THE COLLISION DETECTION
-- =============================================================================

local cjson = require "cjson"

local M = {}

-- Helper function to send JSON response and exit
local function send_json(status, tbl)
    ngx.status = status
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode(tbl))
    ngx.exit(status)
end

-- =============================================
-- SIMPLIFIED GUEST SESSION CREATION
-- =============================================

function M.handle_create_session()
    ngx.log(ngx.INFO, "🎮 is_none: Delegating directly to is_guest with collision detection")
    
    -- Delegate directly to is_guest.lua which now handles collision detection
    local success, result = pcall(function()
        local is_guest = require "is_guest"
        return is_guest.handle_create_session()
    end)
    
    if not success then
        ngx.log(ngx.ERR, "❌ is_guest handler failed: " .. tostring(result))
        send_json(500, {
            success = false,
            error = "Guest session creation failed",
            message = "Error in guest session handler: " .. tostring(result)
        })
    end
    
    -- If we get here, is_guest should have sent its own response
    ngx.log(ngx.INFO, "✅ is_guest handler completed")
end

-- =============================================
-- SIMPLE API HANDLER
-- =============================================

function M.handle_api(uri, method)
    ngx.log(ngx.INFO, "🎮 is_none.handle_api: " .. method .. " " .. uri)
    
    if uri == "/api/guest/create-session" and method == "POST" then
        return M.handle_create_session()
    else
        send_json(404, {
            success = false,
            error = "is_none API endpoint not found",
            requested = method .. " " .. uri,
            available_endpoints = {
                "POST /api/guest/create-session"
            }
        })
    end
end

return M