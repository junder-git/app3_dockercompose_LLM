-- =============================================================================
-- nginx/lua/is_approved.lua - APPROVED USER API HANDLERS WITH REDIS CHAT PERSISTENCE
-- =============================================================================

local cjson = require "cjson"
local auth = require "manage_auth"
local chat_history = require "manage_chat_history"

local M = {}