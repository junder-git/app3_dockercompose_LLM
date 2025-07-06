# quart-app/blueprints/chat.py - FIXED with comprehensive error handling and logging
import os
import hashlib
import aiohttp
import json
import time
import asyncio
import logging
import sys
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

# Configure logging to show in docker logs with more detail
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - CHAT - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.StreamHandler(sys.stderr)
    ],
    force=True
)
logger = logging.getLogger(__name__)

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

logger.info(f"🚀 Chat blueprint initialized - Model: {OLLAMA_MODEL}, URL: {OLLAMA_URL}")
logger.info(f"⚙️ Model settings - Tokens: {MODEL_MAX_TOKENS}, Timeout: {MODEL_TIMEOUT}s")

async def test_ollama_connection():
    """Test if Ollama is responding with detailed logging"""
    try:
        logger.info(f"🔍 Testing connection to {OLLAMA_URL}/api/tags")
        timeout = aiohttp.ClientTimeout(total=10)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(f"{OLLAMA_URL}/api/tags") as resp:
                logger.info(f"📡 Ollama response status: {resp.status}")
                if resp.status == 200:
                    data = await resp.json()
                    models = data.get('models', [])
                    logger.info(f"✅ Ollama connection successful: {len(models)} models available")
                    for model in models[:3]:  # Log first 3 models
                        logger.info(f"   📦 Available model: {model.get('name', 'Unknown')}")
                    return True
                else:
                    error_text = await resp.text()
                    logger.error(f"❌ Ollama HTTP error {resp.status}: {error_text}")
                    return False
    except asyncio.TimeoutError:
        logger.error("❌ Ollama connection timeout after 10 seconds")
        return False
    except aiohttp.ClientError as e:
        logger.error(f"❌ Ollama client error: {e}")
        return False
    except Exception as e:
        logger.error(f"❌ Ollama connection unexpected error: {e}")
        return False

# Chat routes
@chat_bp.route('/chat', methods=['GET'])
@login_required
async def chat():
    """Main chat interface"""
    logger.info(f"🌐 Chat page requested by user: {current_user.auth_id}")
    
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        logger.warning(f"❌ User data not found for: {current_user.auth_id}")
        return redirect(url_for('auth.login'))    
    
    # Get session ID from query parameter or create new
    requested_session_id = request.args.get('session')
    logger.info(f"📋 Requested session: {requested_session_id}")
    
    # Use requested session or fallback to default
    current_session_id = requested_session_id
    # Verify session exists and belongs to user
    session_obj = await get_chat_session(current_session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        logger.info("🔄 Creating new session for user")
        current_session_id = await get_or_create_current_session(user_data.id)
    
    logger.info(f"✅ Using session: {current_session_id}")
    
    # Get all user sessions for sidebar
    chat_sessions = await get_user_chat_sessions(user_data.id)
    # Get messages for current session
    messages = await get_session_messages(current_session_id, CHAT_HISTORY_LIMIT)
    
    logger.info(f"📨 Loaded {len(messages)} messages for session")
    
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
    logger.info("🌊 === STREAM REQUEST STARTED ===")
    
    # Get parameters
    message = request.args.get('message', '').strip()
    session_id = request.args.get('session_id')
    stream_id = request.args.get('stream_id')   
    
    logger.info(f"📋 Stream params received:")
    logger.info(f"   💬 Message: '{message[:100]}{'...' if len(message) > 100 else ''}'")
    logger.info(f"   🆔 Session: {session_id}")
    logger.info(f"   🎯 Stream: {stream_id}")
    
    if not message or not session_id or not stream_id:
        logger.error("❌ Missing required parameters")
        return jsonify({'error': 'Missing required parameters'}), 400
    
    # Validate message
    is_valid, error_msg = validate_message(message)
    if not is_valid:
        logger.error(f"❌ Invalid message: {error_msg}")
        return jsonify({'error': error_msg}), 400
    
    # Get user data
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        logger.error("❌ User not found")
        return jsonify({'error': 'User not found'}), 401
    
    logger.info(f"👤 User: {user_data.username} (ID: {user_data.id})")
    
    # Check rate limit
    if not await check_rate_limit(user_data.id, RATE_LIMIT_MAX):
        logger.warning(f"🚫 Rate limit exceeded for user: {user_data.username}")
        return jsonify({'error': 'Rate limit exceeded'}), 429
    
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != user_data.id:
        logger.error(f"❌ Invalid session {session_id} for user {user_data.id}")
        return jsonify({'error': 'Invalid session'}), 403
    
    # Test Ollama connection before proceeding
    logger.info("🔍 Testing Ollama connection before streaming...")
    if not await test_ollama_connection():
        logger.error("❌ Ollama connection failed - aborting stream")
        return jsonify({'error': 'AI service is not available. Please try again in a moment.'}), 503
    
    # Save user message
    await save_message(user_data.id, 'user', message, session_id)
    logger.info("💾 User message saved to database")
    
    # Store stream info for interrupt capability
    active_streams[stream_id] = {
        'user_id': user_data.id,
        'active': True,
        'start_time': time.time()
    }
    
    logger.info(f"🎯 Stream {stream_id} registered - starting generation...")
    
    # Create response generator
    async def generate_response():
        try:
            # Check for cached response
            message_hash = hashlib.md5(message.encode()).hexdigest()
            cached = await get_cached_response(message_hash)
            if cached:
                logger.info("💾 Using cached response")
                yield f"data: {json.dumps({'content': cached, 'cached': True})}\n\n"
                yield f"data: {json.dumps({'done': True})}\n\n"
                # Save cached response
                await save_message(user_data.id, 'assistant', cached, session_id)
                return
            
            logger.info("🔥 Generating new response from Ollama")
            
            # Use the optimized model if it exists
            model_to_use = f"{OLLAMA_MODEL}-optimized"
            
            # Build request payload with CONSERVATIVE settings
            payload = {
                'model': model_to_use,
                'messages': [{'role': 'user', 'content': message}],
                'stream': True,
                'options': {
                    'temperature': MODEL_TEMPERATURE,
                    'top_p': MODEL_TOP_P,
                    'top_k': MODEL_TOP_K,
                    'num_predict': MODEL_MAX_TOKENS
                }
            }
            
            logger.info(f"📤 Sending request to Ollama:")
            logger.info(f"   🎛️ Model: {model_to_use}")
            logger.info(f"   🌡️ Temperature: {MODEL_TEMPERATURE}")
            logger.info(f"   🎯 Max tokens: {MODEL_MAX_TOKENS}")
            logger.info(f"   ⏱️ Timeout: {MODEL_TIMEOUT}s")
            
            # Conservative timeout settings
            timeout = aiohttp.ClientTimeout(
                total=MODEL_TIMEOUT,
                sock_read=30,  # 30 seconds per chunk
                sock_connect=10  # 10 seconds to connect
            )
            
            # Stream from Ollama
            full_response = ""
            chunk_count = 0
            
            try:
                connector = aiohttp.TCPConnector(
                    limit=0,  # No connection pool limit
                    limit_per_host=0,  # No per-host limit
                    keepalive_timeout=30,
                    enable_cleanup_closed=True
                )
                
                async with aiohttp.ClientSession(
                    timeout=timeout, 
                    connector=connector
                ) as session:
                    
                    logger.info(f"🔗 Opening connection to {OLLAMA_URL}/api/chat")
                    
                    async with session.post(f"{OLLAMA_URL}/api/chat", json=payload) as resp:
                        logger.info(f"📡 Ollama response status: {resp.status}")
                        
                        if resp.status != 200:
                            error_text = await resp.text()
                            logger.error(f"❌ Ollama error {resp.status}: {error_text}")
                            yield f"data: {json.dumps({'error': f'AI service error: {resp.status} - {error_text}'})}\n\n"
                            return
                        
                        logger.info("✅ Ollama streaming started successfully")
                        
                        async for line in resp.content:
                            # Check if stream was interrupted
                            if stream_id not in active_streams or not active_streams[stream_id]['active']:
                                logger.info("🛑 Stream interrupted by user")
                                yield f"data: {json.dumps({'interrupted': True})}\n\n"
                                return
                            
                            line_text = line.decode('utf-8').strip()
                            if not line_text:
                                continue
                            
                            try:
                                data = json.loads(line_text)
                                chunk_count += 1
                                
                                if chunk_count % 10 == 0:  # Log every 10th chunk
                                    logger.info(f"📝 Processed {chunk_count} chunks, response length: {len(full_response)}")
                                
                                if data.get('done'):
                                    logger.info("✅ Stream completed by Ollama")
                                    yield f"data: {json.dumps({'done': True})}\n\n"
                                    break
                                
                                if 'message' in data and 'content' in data['message']:
                                    content = data['message']['content']
                                    full_response += content
                                    yield f"data: {json.dumps({'content': content})}\n\n"
                                    
                                    # Small delay every 20 chunks to prevent overwhelming
                                    if chunk_count % 20 == 0:
                                        await asyncio.sleep(0.01)
                                        
                            except json.JSONDecodeError as e:
                                logger.error(f"❌ JSON decode error: {e}, line: {line_text[:100]}")
                                continue
                
                logger.info(f"📊 Stream completed - Total chunks: {chunk_count}, Response length: {len(full_response)}")
                
                # Save full response and cache it
                if full_response.strip():
                    await save_message(user_data.id, 'assistant', full_response, session_id)
                    await cache_response(message_hash, full_response)
                    logger.info("💾 Response saved and cached successfully")
                else:
                    logger.warning("⚠️ Empty response generated")
                    yield f"data: {json.dumps({'error': 'Empty response from AI service'})}\n\n"
                
            except asyncio.TimeoutError:
                logger.error("❌ Request timeout to Ollama")
                yield f"data: {json.dumps({'error': 'Request timeout - please try again with a shorter message'})}\n\n"
            except aiohttp.ClientError as e:
                logger.error(f"❌ HTTP client error: {e}")
                yield f"data: {json.dumps({'error': f'Connection error: {str(e)}'})}\n\n"
            except Exception as e:
                logger.error(f"❌ Unexpected streaming error: {e}")
                yield f"data: {json.dumps({'error': f'Unexpected error: {str(e)}'})}\n\n"
                
        finally:
            # Clean up stream tracking
            if stream_id in active_streams:
                del active_streams[stream_id]
                logger.info(f"🧹 Cleaned up stream: {stream_id}")
            logger.info("🏁 === STREAM REQUEST FINISHED ===")
    
    # Return Server-Sent Events response
    logger.info("🚀 Starting SSE response generation")
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
    
    logger.info(f"🛑 Interrupt request for stream: {stream_id}")
    
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
            logger.info(f"✅ Stream {stream_id} marked for interruption")
            return jsonify({'success': True, 'message': 'Stream interrupted'})
        else:
            logger.warning(f"❌ Unauthorized interrupt attempt")
            return jsonify({'error': 'Unauthorized'}), 403
    else:
        logger.warning(f"❌ Stream {stream_id} not found")
        return jsonify({'error': 'Stream not found'}), 404

@chat_bp.route('/chat/clear', methods=['POST'])
@login_required
async def clear_current_chat():
    """Clear all messages from current chat session"""
    data = await request.json
    session_id = data.get('session_id')
    
    logger.info(f"🧹 Clear request for session: {session_id}")
    
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
    logger.info(f"✅ Cleared session {session_id}")
    return jsonify({'success': True, 'message': 'Chat cleared successfully'})

@chat_bp.route('/chat/delete_session', methods=['POST'])
@login_required
async def delete_session():
    """Delete a chat session"""
    data = await request.json
    session_id = data.get('session_id')
    
    logger.info(f"🗑️ Delete request for session: {session_id}")
    
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
    logger.info(f"✅ Deleted session {session_id}")
    return jsonify({'success': True, 'message': 'Session deleted successfully'})

# Add health check endpoint
@chat_bp.route('/chat/health', methods=['GET'])
@login_required
async def chat_health():
    """Health check for chat functionality"""
    try:
        logger.info("🏥 Health check requested")
        
        # Test Ollama connection
        ollama_ok = await test_ollama_connection()
        
        # Test user access
        user_data = await get_current_user_data(current_user.auth_id)
        user_ok = user_data is not None
        
        logger.info(f"🏥 Health check results - Ollama: {ollama_ok}, User: {user_ok}")
        
        return jsonify({
            'status': 'ok' if (ollama_ok and user_ok) else 'error',
            'ollama': 'ok' if ollama_ok else 'error',
            'user': 'ok' if user_ok else 'error',
            'timestamp': time.time(),
            'model': OLLAMA_MODEL,
            'url': OLLAMA_URL
        })
        
    except Exception as e:
        logger.error(f"❌ Health check error: {e}")
        return jsonify({
            'status': 'error',
            'error': str(e),
            'timestamp': time.time()
        }), 500