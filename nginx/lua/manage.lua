-- =============================================================================
-- nginx/lua/server.lua - Main server module (refactored)
-- =============================================================================

-- Load sub-modules
local user_manager = require "user_manager"
local sse_manager = require "sse_manager"
local vllm_streaming = require "vllm_streaming"

-- Create the main module
local M = {}

-- =============================================
-- Export all functions from sub-modules
-- =============================================

-- User Manager Functions
M.get_user = user_manager.get_user
M.create_user = user_manager.create_user
M.update_user_activity = user_manager.update_user_activity
M.get_all_users = user_manager.get_all_users
M.verify_password = user_manager.verify_password
M.get_user_counts = user_manager.get_user_counts
M.get_pending_users = user_manager.get_pending_users
M.approve_user = user_manager.approve_user
M.reject_user = user_manager.reject_user
M.get_registration_stats = user_manager.get_registration_stats
M.save_message = user_manager.save_message
M.get_chat_history = user_manager.get_chat_history
M.clear_chat_history = user_manager.clear_chat