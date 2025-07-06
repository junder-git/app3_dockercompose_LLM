# quart-app/blueprints/chat.py - COMPLETE with all required routes
import os
import hashlib
import aiohttp
import json
import time
from quart import Blueprint, render_template, request, redirect, url_for, Response, jsonify
from quart_auth import current_user, login_required

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response, get_user_chat_sessions,
    get_chat_session, delete_chat_session,
    clear_session_messages
)
from .utils import validate_message

# Create blueprint with explicit url_prefix
chat_bp = Blueprint('chat', __name__, url_prefix='')

# AI Model configuration - ALL from environment
OLLAMA_URL = os.environ['OLLAMA_URL']
OLLAMA_MODEL = os.environ['OLLAMA_MODEL']
CHAT_HISTORY_LIMIT = int(os.environ['CHAT_HISTORY_LIMIT'])
RATE_LIMIT_MAX = int(os.environ['RATE_LIMIT_MESSAGES_PER_MINUTE'])

# Model parameters - ALL from environment
MODEL_TEMPERATURE = float(os.environ['MODEL_TEMPERATURE'])
MODEL_TOP_P = float(os.environ['MODEL_TOP_P'])
MODEL_TOP_K = int(os.environ['MODEL_TOP_K'])
MODEL_MAX_TOKENS = int(os.environ['MODEL_MAX_TOKENS'])
MODEL_TIMEOUT = int(os.environ['MODEL_TIMEOUT'])

# Global storage for active streams
active_streams = {}

# Chat routes
@chat_bp.route('/chat', methods=['GET'])
@login_required
async def chat():
    """Main chat interface"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))    
    # Get session ID from query parameter or create new
    requested_session_id = request.args.get('session')
    # Use requested session or fallback to default
    current_session_id = requested_session_id
    # Verify session exists and belongs to user
    session_obj = await get_chat_session(current_session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        current_session_id = await get_or_create_current_session(user_data.id)
    # Get all user sessions for sidebar
    chat_sessions = await get_user_chat_sessions(user_data.id)
    # Get messages for current session
    messages = await get_session_messages(current_session_id, CHAT_HISTORY_LIMIT)
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp'),
            'cached': msg.get('cached', False)
        })
    return await render_template('chat/index.html', 
                                username=user_data.username,
                                messages=formatted_messages,
                                current_session_id=current_session_id,
                                chat_sessions=chat_sessions)
                                
@chat_bp.route('/chat/stream', methods=['GET'])
@login_required
async def chat_stream():
    """Server-Sent Events streaming endpoint for real-time AI responses"""
    # Get parameters
    message = request.args.get('message', '').strip()
    session_id = request.args.get('session_id')
    stream_id = request.args.get('stream_id')   
    if not message or not session_id or not stream_id:
        return jsonify({'error': 'Missing required parameters'}), 400
    # Validate message
    is_valid, error_msg = validate_message(message)
    if not is_valid:
        return jsonify({'error': error_msg}), 400
    # Get user data
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return jsonify({'error': 'User not found'}), 401
    # Check rate limit
    if not await check_rate_limit(user_data.id, RATE_LIMIT_MAX):
        return jsonify({'error': 'Rate limit exceeded'}), 429
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        return jsonify({'error': 'Invalid session'}), 403
    # Save user message
    await save_message(user_data.id, 'user', message, session_id)
    # Store stream info for interrupt capability
    active_streams[stream_id] = {
        'user_id': user_data.id,
        'active': True,
        'start_time': time.time()
    }
    # Create response generator
    async def generate_response():
        # Check for cached response
        message_hash = hashlib.md5(message.encode()).hexdigest()
        cached = await get_cached_response(message_hash)
        if cached:
            yield f"data: {json.dumps({'content': cached, 'cached': True})}\n\n"
            yield f"data: {json.dumps({'done': True})}\n\n"
            # Save cached response
            await save_message(user_data.id, 'assistant', cached, session_id)
            return
        # Generate new response from Ollama       
        # Build request payload
        payload = {
            'model': OLLAMA_MODEL,
            'messages': [{'role': 'user', 'content': message}],
            'stream': True,
            'options': {
                'temperature': MODEL_TEMPERATURE,
                'top_p': MODEL_TOP_P,
                'top_k': MODEL_TOP_K,
                'num_predict': MODEL_MAX_TOKENS
            }
        }
        # Set timeout configuration
        if MODEL_TIMEOUT > 0:
            timeout = aiohttp.ClientTimeout(total=MODEL_TIMEOUT)
        else:
            timeout = aiohttp.ClientTimeout(total=None)  # Unlimited
        # Stream from Ollama
        full_response = ""
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(f"{OLLAMA_URL}/api/chat", json=payload) as resp:
                if resp.status != 200:
                    error_text = await resp.text()
                    yield f"data: {json.dumps({'error': f'AI service error: {resp.status}'})}\n\n"
                    return
                async for line in resp.content:
                    # Check if stream was interrupted
                    if stream_id not in active_streams or not active_streams[stream_id]['active']:
                        yield f"data: {json.dumps({'interrupted': True})}\n\n"
                        return
                    line_text = line.decode('utf-8').strip()
                    if not line_text:
                        continue
                    data = json.loads(line_text)
                    if data.get('done'):
                        yield f"data: {json.dumps({'done': True})}\n\n"
                        break
                    if 'message' in data and 'content' in data['message']:
                        content = data['message']['content']
                        full_response += content
                        yield f"data: {json.dumps({'content': content})}\n\n"
            # Save full response and cache it
            if full_response.strip():
                await save_message(user_data.id, 'assistant', full_response, session_id)
                await cache_response(message_hash, full_response)
            # Clean up stream tracking
            if stream_id in active_streams:
                del active_streams[stream_id]
    # Return Server-Sent Events response
    return Response(
        generate_response(),
        content_type='text/event-stream',
        headers={
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'X-Accel-Buffering': 'no'  # Disable nginx buffering
        }
    )

@chat_bp.route('/chat/interrupt', methods=['POST'])
@login_required
async def chat_interrupt():
    """Interrupt an active streaming response"""
    data = await request.json
    stream_id = data.get('stream_id')
    if not stream_id:
        return jsonify({'error': 'Stream ID required'}), 400
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return jsonify({'error': 'User not found'}), 401
    # Check if stream exists and belongs to user
    if stream_id in active_streams:
        stream_info = active_streams[stream_id]
        if stream_info['user_id'] == user_data.id:
            stream_info['active'] = False
            return jsonify({'success': True, 'message': 'Stream interrupted'})
        else:
            return jsonify({'error': 'Unauthorized'}), 403
    else:
        return jsonify({'error': 'Stream not found'}), 404

@chat_bp.route('/chat/clear', methods=['POST'])
@login_required
async def clear_current_chat():
    """Clear all messages from current chat session"""
    data = await request.json
    session_id = data.get('session_id')
    if not session_id:
        return jsonify({'success': False, 'message': 'Session ID required'}), 400
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        return jsonify({'success': False, 'message': 'Session not found'}), 404
    # Clear all messages from this session
    await clear_session_messages(session_id)
    return jsonify({'success': True, 'message': 'Chat cleared successfully'})

@chat_bp.route('/chat/delete_session', methods=['POST'])
@login_required
async def delete_session():
    """Delete a chat session"""
    data = await request.json
    session_id = data.get('session_id')
    if not session_id:
        return jsonify({'success': False, 'message': 'Session ID required'}), 400
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        return jsonify({'success': False, 'message': 'Session not found'}), 404
    # Delete the session
    await delete_chat_session(user_data.id, session_id)
    return jsonify({'success': True, 'message': 'Session deleted successfully'})