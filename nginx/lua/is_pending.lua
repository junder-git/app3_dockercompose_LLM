-- =============================================================================
-- nginx/lua/is_pending.lua - PENDING USER API HANDLERS ONLY (VIEWS HANDLED BY manage_views.lua)
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}

-- =============================================
-- PENDING USER STATUS API
-- =============================================

local function handle_status_check()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_pending" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Access denied",
            message = "Pending user access required"
        }))
        return
    end
    
    -- Get pending user count for queue position
    local red = auth.connect_redis()
    local pending_count = 0
    local user_position = 0
    
    if red then
        local user_keys = red:keys("username:*") or {}
        local pending_users = {}
        
        for _, key in ipairs(user_keys) do
            local user_data_redis = red:hgetall(key)
            if user_data_redis and #user_data_redis > 0 then
                local user = {}
                for i = 1, #user_data_redis, 2 do
                    local field_key = user_data_redis[i]
                    if string.sub(field_key, -1) == ":" then
                        field_key = string.sub(field_key, 1, -2)
                    end
                    user[field_key] = user_data_redis[i + 1]
                end
                
                if user.user_type == "is_pending" then
                    pending_count = pending_count + 1
                    table.insert(pending_users, {
                        username = user.username,
                        created_at = user.created_at
                    })
                end
            end
        end
        
        -- Sort by creation time to determine position
        table.sort(pending_users, function(a, b)
            return (a.created_at or "") < (b.created_at or "")
        end)
        
        for i, user in ipairs(pending_users) do
            if user.username == username then
                user_position = i
                break
            end
        end
        
        red:close()
    end
    
    ngx.status = 200
    ngx.header.content_type = 'application/json'
    ngx.say(cjson.encode({
        success = true,
        status = "pending_approval",
        username = username,
        is_approved = false,
        message = "Your account is pending administrator approval",
        created_at = user_data.created_at,
        queue_info = {
            total_pending = pending_count,
            max_pending = 2,
            position_in_queue = user_position
        },
        estimated_wait_time = "24-48 hours"
    }))
end

-- =============================================
-- PENDING USER API HANDLER
-- =============================================

function M.handle_pending_api()
    local user_type, username, user_data = auth.check()
    
    if user_type ~= "is_pending" then
        ngx.status = 403
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Access denied",
            message = "Pending user access required"
        }))
        return
    end
    
    local uri = ngx.var.uri
    local method = ngx.var.request_method
    
    if uri == "/api/pending/status" and method == "GET" then
        handle_status_check()
    else
        ngx.status = 404
        ngx.header.content_type = 'application/json'
        ngx.say(cjson.encode({
            success = false,
            error = "Pending user API endpoint not found",
            available_endpoints = {
                "GET /api/pending/status - Check approval status"
            }
        }))
    end
end

-- =============================================
-- ROUTE HANDLER (FOR NON-VIEW ROUTES)
-- =============================================

function M.handle_route(route_type)
    -- This function handles non-view routes for pending users
    -- Views are handled by manage_views.lua
    if route_type == "pending_api" then
        return M.handle_pending_api()
    else
        ngx.status = 404
        return ngx.say("Pending user route not found: " .. tostring(route_type))
    end
end

return {
    handle_pending_api = M.handle_pending_api,
    handle_route = M.handle_route
}