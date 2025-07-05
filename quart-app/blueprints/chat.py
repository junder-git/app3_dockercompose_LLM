# quart-app/blueprints/chat.py - COMPLETE with all required routes
import os
import hashlib
import aiohttp
import asyncio
import json
import time
import uuid
from typing import List, Dict, AsyncGenerator
from quart import Blueprint, render_template, request, redirect, url_for, flash, Response, jsonify
from quart_auth import current_user, login_required

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response, get_user_chat_sessions,
    get_chat_session, delete_chat_session, create_chat_session,
    clear_session_messages
)
from .utils import escape_html, sanitize_html, validate_message

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

print(f"🔧 Chat Blueprint COMPLETE Config:")
print(f"  OLLAMA_URL: {OLLAMA_URL}")
print(f"  OLLAMA_MODEL: {OLLAMA_MODEL}")
print(f"  CHAT_HISTORY_LIMIT: {CHAT_HISTORY_LIMIT}")
print(f"  RATE_LIMIT_MAX: {RATE_LIMIT_MAX}")
print(f"  MODEL_TIMEOUT: {MODEL_TIMEOUT}")

# Global storage for active streams
active_streams = {}

# Chat routes
@chat_bp.route('/chat', methods=['GET'])
@chat_bp.route('/chat/new', methods=['GET'])
@login_required
async def chat():
    """Main chat interface"""
    print(f"🔗 Chat route accessed: {request.path}")
    
    try:
        user_data = await get_current_user_data(current_user.auth_id)
        if not user_data:
            print(f"🔗 Chat: No user data found")
            return redirect(url_for('auth.login'))
        
        print(f"🔗 Chat: User {user_data.username} accessing chat")
        
        # Get session ID from query parameter or create new
        requested_session_id = request.args.get('session')
        
        if request.path == '/chat/new' or not requested_session_id:
            # Create new session
            print(f"🔗 Chat: Creating new session")
            current_session_id = await get_or_create_current_session(user_data.id)
        else:
            # Use requested session or fallback to default
            print(f"🔗 Chat: Using session {requested_session_id}")
            current_session_id = requested_session_id
            # Verify session exists and belongs to user
            session_obj = await get_chat_session(current_session_id)
            if not session_obj or session_obj.user_id != user_data.id:
                print(f"🔗 Chat: Session not found, creating new")
                current_session_id = await get_or_create_current_session(user_data.id)
        
        # Get all user sessions for sidebar
        try:
            chat_sessions = await get_user_chat_sessions(user_data.id)
            print(f"🔗 Chat: Found {len(chat_sessions)} sessions")
        except Exception as e:
            print(f"🔗 Chat: Error getting sessions: {e}")
            chat_sessions = []
        
        # Get messages for current session
        try:
            messages = await get_session_messages(current_session_id, CHAT_HISTORY_LIMIT)
            print(f"🔗 Chat: Found {len(messages)} messages")
        except Exception as e:
            print(f"🔗 Chat: Error getting messages: {e}")
            messages = []
        
        formatted_messages = []
        for msg in messages:
            formatted_messages.append({
                'role': msg.get('role'),
                'content': msg.get('content', ''),
                'timestamp': msg.get('timestamp'),
                'cached': msg.get('cached', False)
            })
        
        print(f"🔗 Chat: Rendering template")
        return await render_template('chat/index.html', 
                                   username=user_data.username,
                                   messages=formatted_messages,
                                   current_session_id=current_session_id,
                                   chat_sessions=chat_sessions)
                                   
    except Exception as e:
        print(f"❌ Chat route error: {e}")
        return redirect(url_for('auth.login'))

@chat_bp.route('/chat/stream', methods=['GET'])
@login_required
async def chat_stream():
    """Server-Sent Events streaming endpoint for real-time AI responses"""
    print(f"🌊 Chat stream request started")
    
    try:
        # Get parameters
        message = request.args.get('message', '').strip()
        session_id = request.args.get('session_id')
        stream_id = request.args.get('stream_id')
        
        print(f"🌊 Stream params: message_len={len(message)}, session={session_id}, stream={stream_id}")
        
        if not message or not session_id or not stream_id:
            print(f"🌊 Missing required parameters")
            return jsonify({'error': 'Missing required parameters'}), 400
        
        # Validate message
        is_valid, error_msg = validate_message(message)
        if not is_valid:
            print(f"🌊 Invalid message: {error_msg}")
            return jsonify({'error': error_msg}), 400
        
        # Get user data
        user_data = await get_current_user_data(current_user.auth_id)
        if not user_data:
            print(f"🌊 No user data")
            return jsonify({'error': 'User not found'}), 401
        
        # Check rate limit
        if not await check_rate_limit(user_data.id, RATE_LIMIT_MAX):
            print(f"🌊 Rate limit exceeded for user {user_data.username}")
            return jsonify({'error': 'Rate limit exceeded'}), 429
        
        # Verify session belongs to user
        session_obj = await get_chat_session(session_id)
        if not session_obj or session_obj.user_id != user_data.id:
            print(f"🌊 Invalid session")
            return jsonify({'error': 'Invalid session'}), 403
        
        print(f"🌊 Starting stream for user {user_data.username}")
        
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
            try:
                # Check for cached response
                message_hash = hashlib.md5(message.encode()).hexdigest()
                cached = await get_cached_response(message_hash)
                
                if cached:
                    print(f"🌊 Using cached response")
                    yield f"data: {json.dumps({'content': cached, 'cached': True})}\n\n"
                    yield f"data: {json.dumps({'done': True})}\n\n"
                    # Save cached response
                    await save_message(user_data.id, 'assistant', cached, session_id)
                    return
                
                # Generate new response from Ollama
                print(f"🌊 Generating new response from Ollama")
                
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
                            print(f"🌊 Ollama error: {resp.status} - {error_text}")
                            yield f"data: {json.dumps({'error': f'AI service error: {resp.status}'})}\n\n"
                            return
                        
                        async for line in resp.content:
                            # Check if stream was interrupted
                            if stream_id not in active_streams or not active_streams[stream_id]['active']:
                                print(f"🌊 Stream {stream_id} interrupted")
                                yield f"data: {json.dumps({'interrupted': True})}\n\n"
                                return
                            
                            try:
                                line_text = line.decode('utf-8').strip()
                                if not line_text:
                                    continue
                                
                                data = json.loads(line_text)
                                
                                if data.get('done'):
                                    print(f"🌊 Stream complete")
                                    yield f"data: {json.dumps({'done': True})}\n\n"
                                    break
                                
                                if 'message' in data and 'content' in data['message']:
                                    content = data['message']['content']
                                    full_response += content
                                    yield f"data: {json.dumps({'content': content})}\n\n"
                                    
                            except json.JSONDecodeError as e:
                                print(f"🌊 JSON decode error: {e}")
                                continue
                            except Exception as e:
                                print(f"🌊 Stream processing error: {e}")
                                continue
                
                # Save full response and cache it
                if full_response.strip():
                    await save_message(user_data.id, 'assistant', full_response, session_id)
                    await cache_response(message_hash, full_response)
                    print(f"🌊 Response saved and cached")
                
            except asyncio.TimeoutError:
                print(f"🌊 Timeout error")
                yield f"data: {json.dumps({'error': 'Request timeout'})}\n\n"
            except Exception as e:
                print(f"🌊 Stream error: {e}")
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
            finally:
                # Clean up stream tracking
                if stream_id in active_streams:
                    del active_streams[stream_id]
                print(f"🌊 Stream {stream_id} cleanup complete")
        
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
        
    except Exception as e:
        print(f"❌ Stream error: {e}")
        return jsonify({'error': str(e)}), 500

@chat_bp.route('/chat/interrupt', methods=['POST'])
@login_required
async def chat_interrupt():
    """Interrupt an active streaming response"""
    print(f"🛑 Interrupt request")
    
    try:
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
                print(f"🛑 Stream {stream_id} marked for interruption")
                return jsonify({'success': True, 'message': 'Stream interrupted'})
            else:
                return jsonify({'error': 'Unauthorized'}), 403
        else:
            return jsonify({'error': 'Stream not found'}), 404
            
    except Exception as e:
        print(f"❌ Interrupt error: {e}")
        return jsonify({'error': str(e)}), 500

@chat_bp.route('/chat/clear', methods=['POST'])
@login_required
async def clear_current_chat():
    """Clear all messages from current chat session"""
    print(f"🔗 Clear chat request")
    
    try:
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
        
    except Exception as e:
        print(f"❌ Clear chat error: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@chat_bp.route('/chat/delete_session', methods=['POST'])
@login_required
async def delete_session():
    """Delete a chat session"""
    print(f"🔗 Delete session request")
    
    try:
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
        
    except Exception as e:
        print(f"❌ Delete session error: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@chat_bp.route('/chat/test', methods=['GET'])
@login_required
async def chat_test():
    """Simple test route for chat"""
    print(f"🔗 Chat test route accessed")
    
    try:
        user_data = await get_current_user_data(current_user.auth_id)
        return jsonify({
            'status': 'success',
            'message': 'Chat blueprint is working',
            'user': user_data.username if user_data else 'Unknown',
            'timestamp': time.time(),
            'ollama_url': OLLAMA_URL,
            'model': OLLAMA_MODEL
        })
    except Exception as e:
        print(f"❌ Chat test error: {e}")
        return jsonify({'error': str(e)}), 500

@chat_bp.route('/chat/health', methods=['GET'])
@login_required
async def chat_health():
    """Check AI service health"""
    print(f"🔗 Chat health check")
    
    try:
        # Simple connection test
        timeout = aiohttp.ClientTimeout(total=5)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(f"{OLLAMA_URL}/api/tags") as response:
                if response.status == 200:
                    data = await response.json()
                    available_models = [model['name'] for model in data.get('models', [])]
                    model_loaded = any(OLLAMA_MODEL in model for model in available_models)
                    
                    return jsonify({
                        'status': 'healthy' if model_loaded else 'model_not_found',
                        'active_model': OLLAMA_MODEL,
                        'available_models': available_models,
                        'ollama_url': OLLAMA_URL
                    })
        return jsonify({'status': 'unhealthy', 'error': 'Service unavailable'})
    except Exception as e:
        print(f"❌ Health check error: {e}")
        return jsonify({'status': 'error', 'error': str(e)})

print("✅ Chat Blueprint COMPLETE - All routes implemented")