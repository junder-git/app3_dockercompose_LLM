-- =============================================================================
-- nginx/lua/manage.lua - Main server module (updated for Ollama)
-- =============================================================================

-- Load sub-modules
local user_manager = require "manage_users"
local sse_manager = require "manage_sse"
local ollama_adapter = require "manage_adapter_ollama_streaming"

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
M.clear_chat_history = user_manager.clear_chat_history
M.check_rate_limit = user_manager.check_rate_limit

-- SSE Manager Functions
M.can_start_sse_session = sse_manager.can_start_sse_session
M.start_sse_session = sse_manager.start_sse_session
M.update_sse_activity = sse_manager.update_sse_activity
M.end_sse_session = sse_manager.end_sse_session
M.get_sse_stats = sse_manager.get_sse_stats
M.sse_send = sse_manager.sse_send
M.setup_sse_response = sse_manager.setup_sse_response

-- Ollama Adapter Functions (simplified - only streaming function)
M.call_ollama_streaming = ollama_adapter.call_ollama_streaming
M.format_messages = ollama_adapter.format_messages

return M