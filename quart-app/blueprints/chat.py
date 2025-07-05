# quart-app/blueprints/chat.py - Complete streaming implementation with all features
import os
import hashlib
import aiohttp
import asyncio
import json
import time
import uuid
from typing import List, Dict, AsyncGenerator
from quart import Blueprint, render_template, request, redirect, url_for, flash, Response
from quart_auth import login_required, current_user

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response, get_user_chat_sessions,
    get_chat_session, delete_chat_session, create_chat_session,
    clear_session_messages
)
from .utils import escape_html

chat_bp = Blueprint('chat', __name__)

# AI Model configuration - ONLY from environment variables, NO DEFAULTS
OLLAMA_URL = os.environ['OLLAMA_URL']
OLLAMA_MODEL = os.environ['OLLAMA_MODEL']

# All parameters from environment - NO DEFAULTS
MODEL_TEMPERATURE = float(os.environ['MODEL_TEMPERATURE'])
MODEL_TOP_P = float(os.environ['MODEL_TOP_P'])
MODEL_TOP_K = int(os.environ['MODEL_TOP_K'])
MODEL_REPEAT_PENALTY = float(os.environ['MODEL_REPEAT_PENALTY'])
MODEL_MAX_TOKENS = int(os.environ['MODEL_MAX_TOKENS'])
MODEL_TIMEOUT = int(os.environ['MODEL_TIMEOUT'])

# Hardware settings from environment
OLLAMA_GPU_LAYERS = int(os.environ['OLLAMA_GPU_LAYERS'])
OLLAMA_NUM_THREAD = int(os.environ['OLLAMA_NUM_THREAD'])
OLLAMA_CONTEXT_SIZE = int(os.environ['OLLAMA_CONTEXT_SIZE'])
OLLAMA_BATCH_SIZE = int(os.environ['OLLAMA_BATCH_SIZE'])

# CRITICAL: Memory management - proper boolean conversion
MODEL_USE_MMAP = os.environ['MODEL_USE_MMAP'].lower() == 'true'
MODEL_USE_MLOCK = os.environ['MODEL_USE_MLOCK'].lower() == 'true'

# Auto-adjust MMAP when MLOCK is enabled (they conflict)
if MODEL_USE_MLOCK and MODEL_USE_MMAP:
    MODEL_USE_MMAP = False
    print("🔧 Auto-disabled MMAP because MLOCK is enabled (they conflict)")
    print("   For fully RAM/VRAM loaded models, MLOCK without MMAP is optimal")

# Other settings from environment
OLLAMA_KEEP_ALIVE = os.environ['OLLAMA_KEEP_ALIVE']
# Convert keep_alive to proper format for Ollama (handles both string and int)
if str(OLLAMA_KEEP_ALIVE) == '-1':
    OLLAMA_KEEP_ALIVE = -1  # Convert to integer for permanent loading

# Chat and rate limiting from environment
CHAT_HISTORY_LIMIT = int(os.environ['CHAT_HISTORY_LIMIT'])
RATE_LIMIT_MAX = int(os.environ['RATE_LIMIT_MESSAGES_PER_MINUTE'])

# Stop sequences - fixed list for AI models
MODEL_STOP_SEQUENCES = ["<|endoftext|>", "<|im_end|>", "[DONE]", "<|end|>"]

def get_active_model():
    """Get the active optimized model name"""
    try:
        with open('/tmp/active_model', 'r') as f:
            return f.read().strip()
    except:
        return OLLAMA_MODEL

ACTIVE_MODEL = get_active_model()

print(f"🔧 Chat Blueprint Config:")
print(f"  Active Model: {ACTIVE_MODEL}")
print(f"  OLLAMA_URL: {OLLAMA_URL}")
print(f"  MMAP: {MODEL_USE_MMAP}")
print(f"  MLOCK: {MODEL_USE_MLOCK}")
print(f"  Context Size: {OLLAMA_CONTEXT_SIZE}")
print(f"  GPU Layers: {OLLAMA_GPU_LAYERS}")
print(f"  Temperature: {MODEL_TEMPERATURE}")
print(f"  Max Tokens: {MODEL_MAX_TOKENS}")
print(f"  Timeout: {MODEL_TIMEOUT}")

# Global dictionary to track active streams
active_streams = {}

async def stream_ai_response(prompt: str, chat_history: List[Dict] = None, stream_id: str = None) -> AsyncGenerator[str, None]:
    """Stream AI response with interruption capability"""
    
    try:
        # Build messages array
        messages = []
        
        # Add context history (limited for speed)
        if chat_history:
            for msg in chat_history[-6:]:  # Only last 6 messages
                role = msg.get('role')
                content = msg.get('content', '').strip()
                if role in ['user', 'assistant'] and content:
                    # Truncate long messages
                    if len(content) > 1500:
                        content = content[:1500] + "..."
                    messages.append({
                        'role': role,
                        'content': content
                    })
        
        # Add current user message
        user_prompt = prompt.strip()
        if len(user_prompt) > 5000:
            user_prompt = user_prompt[:5000] + "..."
        
        messages.append({
            'role': 'user',
            'content': user_prompt
        })
        
        # Build payload with ALL environment settings
        payload = {
            'model': ACTIVE_MODEL,
            'messages': messages,
            'stream': True,  # Enable streaming
            'keep_alive': OLLAMA_KEEP_ALIVE,
            'options': {
                'temperature': MODEL_TEMPERATURE,
                'top_p': MODEL_TOP_P,
                'top_k': MODEL_TOP_K,
                'repeat_penalty': MODEL_REPEAT_PENALTY,
                'num_predict': MODEL_MAX_TOKENS,
                'num_ctx': OLLAMA_CONTEXT_SIZE,
                'num_batch': OLLAMA_BATCH_SIZE,
                'num_gpu': OLLAMA_GPU_LAYERS,
                'num_thread': OLLAMA_NUM_THREAD,
                'use_mmap': MODEL_USE_MMAP,
                'use_mlock': MODEL_USE_MLOCK,
                'stop': MODEL_STOP_SEQUENCES
            }
        }
        
        print(f"🔧 AI Request:")
        print(f"  Model: {ACTIVE_MODEL}")
        print(f"  MMAP: {MODEL_USE_MMAP}")
        print(f"  MLOCK: {MODEL_USE_MLOCK}")
        print(f"  Context: {OLLAMA_CONTEXT_SIZE}")
        print(f"  Temperature: {MODEL_TEMPERATURE}")
        
        timeout = aiohttp.ClientTimeout(total=MODEL_TIMEOUT)
        
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_URL}/api/chat",
                json=payload,
                headers={'Content-Type': 'application/json'}
            ) as response:
                
                if response.status != 200:
                    error_text = await response.text()
                    yield f"data: {json.dumps({'error': f'API Error {response.status}: {error_text}'})}\n\n"
                    return
                
                # Stream the response
                async for line in response.content:
                    # Check if stream should be interrupted
                    if stream_id and stream_id in active_streams and active_streams[stream_id].get('interrupt'):
                        yield f"data: {json.dumps({'interrupted': True})}\n\n"
                        break
                    
                    line = line.decode('utf-8').strip()
                    if line:
                        try:
                            data = json.loads(line)
                            if 'message' in data and 'content' in data['message']:
                                content = data['message']['content']
                                if content:
                                    yield f"data: {json.dumps({'content': content})}\n\n"
                            
                            # Check if done
                            if data.get('done', False):
                                yield f"data: {json.dumps({'done': True})}\n\n"
                                break
                        except json.JSONDecodeError:
                            continue
    
    except asyncio.TimeoutError:
        yield f"data: {json.dumps({'error': f'Timeout: Response took longer than {MODEL_TIMEOUT}s.'})}\n\n"
    except Exception as e:
        yield f"data: {json.dumps({'error': f'Error: {str(e)}'})}\n\n"
    finally:
        # Clean up stream tracking
        if stream_id and stream_id in active_streams:
            del active_streams[stream_id]

@chat_bp.route('/chat', methods=['GET'])
@chat_bp.route('/chat/new', methods=['GET'])
@login_required
async def chat():
    """Main chat interface with session management"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))
    
    # Get session ID from query parameter or create new
    requested_session_id = request.args.get('session')
    
    if request.path == '/chat/new' or not requested_session_id:
        # Create new session
        current_session_id = await get_or_create_current_session(user_data.id)
    else:
        # Use requested session or fallback to default
        current_session_id = requested_session_id
        # Verify session exists and belongs to user
        session_obj = await get_chat_session(current_session_id)
        if not session_obj or session_obj.user_id != user_data.id:
            current_session_id = await get_or_create_current_session(user_data.id)
    
    # Get all user sessions for sidebar (limited to 3)
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

@chat_bp.route('/chat/new', methods=['POST'])
@login_required
async def create_new_chat():
    """Create a new chat session"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return {'success': False, 'message': 'Unauthorized'}, 401
    
    # Create new session
    new_session = await create_chat_session(user_data.id)
    
    return {'success': True, 'session_id': new_session.id}

@chat_bp.route('/chat/clear', methods=['POST'])
@login_required
async def clear_current_chat():
    """Clear all messages from current chat session"""
    data = await request.json
    session_id = data.get('session_id')
    
    if not session_id:
        return {'success': False, 'message': 'Session ID required'}, 400
    
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return {'success': False, 'message': 'Unauthorized'}, 401
    
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        return {'success': False, 'message': 'Session not found'}, 404
    
    # Clear all messages from this session
    await clear_session_messages(session_id)
    
    return {'success': True, 'message': 'Chat cleared successfully'}

@chat_bp.route('/chat/stream')
@login_required
async def chat_stream():
    """Server-Sent Events endpoint for streaming responses with real-time DB updates"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))
    
    # Get parameters from query string
    message = request.args.get('message', '')
    session_id = request.args.get('session_id', '')
    stream_id = request.args.get('stream_id', '')
    
    if not message or not session_id:
        async def error_stream():
            yield f"data: {json.dumps({'error': 'Missing message or session_id'})}\n\n"
        return Response(error_stream(), mimetype='text/event-stream')
    
    # Check rate limit
    if not await check_rate_limit(user_data.id, RATE_LIMIT_MAX):
        async def rate_limit_stream():
            yield f"data: {json.dumps({'error': 'Rate limit exceeded'})}\n\n"
        return Response(rate_limit_stream(), mimetype='text/event-stream')
    
    # Save user message immediately to database
    await save_message(user_data.id, 'user', message, session_id)
    
    # Get chat history for context
    chat_history = await get_session_messages(session_id, CHAT_HISTORY_LIMIT // 3)  # Use 1/3 of limit for context
    
    # Check cache first
    prompt_hash = hashlib.md5(message.encode()).hexdigest()
    cached_response = await get_cached_response(prompt_hash)
    
    if cached_response:
        # Save cached response immediately to database
        await save_message(user_data.id, 'assistant', cached_response, session_id)
        
        # Return cached response as if it was streamed
        async def cached_stream():
            yield f"data: {json.dumps({'content': cached_response, 'cached': True})}\n\n"
            yield f"data: {json.dumps({'done': True})}\n\n"
        return Response(cached_stream(), mimetype='text/event-stream')
    
    # Track this stream
    active_streams[stream_id] = {'interrupt': False}
    
    # Stream the AI response with real-time DB updates
    async def streaming_with_db_updates():
        full_response = ''
        
        async for chunk in stream_ai_response(message, chat_history, stream_id):
            yield chunk
            
            # Parse the chunk to get content
            if chunk.startswith('data: '):
                try:
                    data = json.loads(chunk[6:].strip())
                    if 'content' in data:
                        full_response += data['content']
                    elif data.get('done'):
                        # Save complete response to database immediately
                        if full_response.strip():
                            await save_message(user_data.id, 'assistant', full_response, session_id)
                            # Cache the response
                            await cache_response(prompt_hash, full_response)
                        # Signal refresh needed
                        yield f"data: {json.dumps({'refresh_needed': True})}\n\n"
                    elif data.get('interrupted'):
                        # Save partial response if interrupted
                        if full_response.strip():
                            interrupted_response = full_response + '\n\n[Generation interrupted]'
                            await save_message(user_data.id, 'assistant', interrupted_response, session_id)
                        # Signal refresh needed
                        yield f"data: {json.dumps({'refresh_needed': True})}\n\n"
                except (json.JSONDecodeError, KeyError):
                    pass
    
    return Response(
        streaming_with_db_updates(),
        mimetype='text/event-stream',
        headers={
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*'
        }
    )

@chat_bp.route('/chat/interrupt', methods=['POST'])
@login_required
async def interrupt_stream():
    """Interrupt an active stream"""
    data = await request.json
    stream_id = data.get('stream_id')
    
    if stream_id and stream_id in active_streams:
        active_streams[stream_id]['interrupt'] = True
        return {'success': True}
    
    return {'success': False}, 404

@chat_bp.route('/chat/delete_session', methods=['POST'])
@login_required
async def delete_session():
    """Delete a chat session"""
    data = await request.json
    session_id = data.get('session_id')
    
    if not session_id:
        return {'success': False, 'message': 'Session ID required'}, 400
    
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return {'success': False, 'message': 'Unauthorized'}, 401
    
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        return {'success': False, 'message': 'Session not found'}, 404
    
    # Don't allow deleting if it's the only session
    user_sessions = await get_user_chat_sessions(user_data.id)
    if len(user_sessions) <= 1:
        return {'success': False, 'message': 'Cannot delete the last session'}, 400
    
    # Delete the session
    await delete_chat_session(user_data.id, session_id)
    
    return {'success': True, 'message': 'Session deleted successfully'}

async def handle_chat_message(user_id: str, session_id: str, username: str):
    """Legacy handler - no longer used with streaming"""
    # This is kept for backward compatibility but streaming handles everything now
    return redirect(url_for('chat.chat', session=session_id))

@chat_bp.route('/chat/health')
@login_required
async def chat_health():
    """Check AI service health"""
    try:
        timeout = aiohttp.ClientTimeout(total=10)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(f"{OLLAMA_URL}/api/tags") as response:
                if response.status == 200:
                    data = await response.json()
                    available_models = [model['name'] for model in data.get('models', [])]
                    model_loaded = any(ACTIVE_MODEL in model for model in available_models)
                    
                    return {
                        'status': 'healthy' if model_loaded else 'model_not_found',
                        'active_model': ACTIVE_MODEL,
                        'available_models': available_models,
                        'ollama_url': OLLAMA_URL,
                        'environment_config': {
                            'temperature': MODEL_TEMPERATURE,
                            'top_p': MODEL_TOP_P,
                            'context_size': OLLAMA_CONTEXT_SIZE,
                            'gpu_layers': OLLAMA_GPU_LAYERS,
                            'use_mmap': MODEL_USE_MMAP,
                            'use_mlock': MODEL_USE_MLOCK,
                            'keep_alive': OLLAMA_KEEP_ALIVE,
                            'max_tokens': MODEL_MAX_TOKENS,
                            'timeout': MODEL_TIMEOUT
                        }
                    }
        return {'status': 'unhealthy', 'error': 'Service unavailable'}
    except Exception as e:
        return {'status': 'error', 'error': str(e)}