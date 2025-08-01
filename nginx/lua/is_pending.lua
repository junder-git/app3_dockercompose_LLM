-- =============================================================================
-- nginx/lua/is_pending.lua - PENDING USER API HANDLERS ONLY (VIEWS HANDLED BY manage_views.lua)
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"

local M = {}