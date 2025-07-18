-- =============================================================================
-- nginx/lua/manage.lua - Main server module (refactored)
-- =============================================================================

-- Load sub-modules
local user_manager = require "manage_users"
local sse_manager = require "manage_sse"
local vllm_streaming = require "manage_all_llm"
local vllm_adapter = require "manage_adapter_vllm_streaming"

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

-- vLLM Streaming Functions
M.handle_chat_stream_common = vllm_streaming.handle_chat_stream_common
M.call_ollama_streaming = vllm_streaming.call_vllm_streaming  -- For backward compatibility
M.call_vllm_streaming = vllm_streaming.call_vllm_streaming

-- vLLM Adapter Functions
M.call_vllm_api = vllm_adapter.call_vllm_api
M.stream_to_sse = vllm_adapter.stream_to_sse
M.format_messages = vllm_adapter.format_messages

return M