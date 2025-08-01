-- =============================================================================
-- nginx/lua/is_guest.lua - COMPLETE GUEST USER HANDLER WITH CHALLENGE SYSTEM
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- GUEST HELPER FUNCTIONS
-- =============================================

local function get_guest_display_name()
    local user_type, username, user_data = auth.check()
    if user_type == "is_guest" and user_data then
        return user_data.display_username or "Guest User"
    end
    return "Guest User"
end

local function get_chat_features()        
    return string.format([[
        <div class="user-features guest-features">
            <div class="alert alert-warning">
                <h6><i class="bi bi-clock-history text-warning"></i> Guest Chat</h6>
                <p class="mb-1">localStorage only</p>
                <div class="guest-actions">
                    <a href="/register" class="btn btn-warning btn-sm me-2">Register for unlimited</a>
                    <button class="btn btn-outline-light btn-sm" onclick="downloadGuestHistory()">Download History</button>
                </div>
            </div>
        </div>
    ]])
end

-- =============================================
-- MODULE EXPORTS
-- =============================================

return {  
    -- Helper functions
    get_guest_display_name = get_guest_display_name,
    get_chat_features = get_chat_features
}