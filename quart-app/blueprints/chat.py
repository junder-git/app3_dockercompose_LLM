# quart-app/blueprints/chat.py - Merged with Direct Ollama Integration
import os
import hashlib
import aiohttp
import asyncio
import json
from typing import List, Dict, AsyncGenerator
from quart import Blueprint, render_template, request, redirect, url_for, Response
from quart_auth import login_required, current_user

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response
)
from .utils import escape_html

chat_bp = Blueprint('chat', __name__)

# AI Model configuration - Optimized for your RTX 3060 Ti setup
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL', 'devstral:24b')
MODEL_TEMPERATURE = float(os.environ.get('MODEL_TEMPERATURE', '0.7'))
MODEL_TOP_P = float(os.environ.get('MODEL_TOP_P', '0.9'))
MODEL_MAX_TOKENS = int(os.environ.get('MODEL_MAX_TOKENS', '4096'))
MODEL_TIMEOUT = int(os.environ.get('MODEL_TIMEOUT', '300'))

# Your hardware-specific optimizations
OLLAMA_GPU_LAYERS = int(os.environ.get('OLLAMA_GPU_LAYERS', '15'))  # Fits in 8GB VRAM
OLLAMA_NUM_THREAD = int(os.environ.get('OLLAMA_NUM_THREAD', '8'))   # Use 8 CPU cores

def get_active_model():
    """Get the active model name from the init script"""
    try:
        with open('/tmp/active_model', 'r') as f:
            return f.read().strip()
    except:
        return OLLAMA_MODEL

# Use the actual loaded model
ACTIVE_MODEL = get_active_model()

async def stream_ai_response(prompt: str, chat_history: List[Dict] = None) -> AsyncGenerator[str, None]:
    """Stream AI response directly from Ollama - optimized for your hardware"""
    
    try:
        # Build messages array for chat context
        messages = []
        
        # Add recent chat history (keep last 8 messages for context, save memory)
        if chat_history:
            for msg in chat_history[-8:]:
                role = msg.get('role')
                content = msg.get('content', '').strip()
                if role in ['user', 'assistant'] and content:
                    messages.append({
                        'role': role,
                        'content': content
                    })
        
        # Add current user message
        messages.append({
            'role': 'user',
            'content': prompt.strip()
        })
        
        # Configure request payload - optimized for Devstral:24b hybrid setup
        payload = {
            'model': ACTIVE_MODEL,
            'messages': messages,
            'stream': True,
            'keep_alive': -1,  # Keep model permanently loaded
            'options': {
                'temperature': MODEL_TEMPERATURE,
                'top_p': MODEL_TOP_P,
                'num_predict': MODEL_MAX_TOKENS,
                'num_ctx': 32768,  # Use full context capability but reduced for memory
                'repeat_penalty': 1.1,
                'top_k': 40,
                # Your hardware-specific settings
                'num_gpu': OLLAMA_GPU_LAYERS,    # 15 layers on GPU (fits in 8GB)
                'num_thread': OLLAMA_NUM_THREAD, # 8 CPU cores for remaining layers
                'num_batch': 256,                # Smaller batch for hybrid setup
                'rope_scaling_type': 1,          # Better long context handling
                'flash_attention': True,         # Enable flash attention optimization
                'low_vram': True                 # Enable low VRAM optimizations
            }
        }
        
        # Create aiohttp session with extended timeout for AI responses
        timeout = aiohttp.ClientTimeout(total=MODEL_TIMEOUT)
        
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_URL}/api/chat",
                json=payload,
                headers={'Content-Type': 'application/json'}
            ) as response:
                
                if response.status != 200:
                    error_text = await response.text()
                    yield f"\n\n[API Error {response.status}]: {error_text}"
                    return
                
                # Process streaming response line by line
                async for line in response.content:
                    if line:
                        try:
                            line_str = line.decode('utf-8').strip()
                            if line_str:
                                # Parse JSON response
                                data = json.loads(line_str)
                                
                                # Extract content from message
                                if 'message' in data and 'content' in data['message']:
                                    chunk_text = data['message']['content']
                                    if chunk_text:
                                        yield chunk_text
                                
                                # Check if response is complete
                                if data.get('done', False):
                                    break
                                    
                        except json.JSONDecodeError:
                            # Skip malformed JSON lines
                            continue
                        except Exception as e:
                            print(f"Error processing chunk: {e}")
                            continue
    
    except asyncio.TimeoutError:
        yield f"\n\n[Timeout]: AI response took longer than {MODEL_TIMEOUT}s. The model may be processing a complex request."
    except aiohttp.ClientError as e:
        yield f"\n\n[Connection Error]: Failed to connect to Devstral AI service: {str(e)}"
    except Exception as e:
        print(f"Devstral AI error: {e}")
        yield f"\n\n[Error]: AI service unavailable. Please check if Devstral is running."

@chat_bp.route('/chat', methods=['GET', 'POST'])
@login_required
async def chat():
    """Main chat interface with streaming AI responses"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))
    
    # Get or create current session
    current_session_id = await get_or_create_current_session(user_data.id)
    
    if request.method == 'POST':
        # Handle form submission - start chunked response
        return await handle_chat_message(user_data.id, current_session_id, user_data.username)
    
    # GET request - show chat page with existing messages
    messages = await get_session_messages(current_session_id, 20)
    
    # Format messages for display with proper escaping
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'role': msg.get('role'),
            'content': msg.get('content', ''),  # Will be escaped in template
            'timestamp': msg.get('timestamp'),
            'cached': msg.get('cached', False)
        })
    
    return await render_template('chat/index.html', 
                               username=user_data.username,
                               messages=formatted_messages)

async def handle_chat_message(user_id: str, session_id: str, username: str):
    """Handle chat message with chunked streaming response"""
    
    # Check rate limit first
    if not await check_rate_limit(user_id):
        messages = await get_session_messages(session_id, 20)
        formatted_messages = [{'role': msg.get('role'), 'content': msg.get('content', ''), 
                             'timestamp': msg.get('timestamp')} for msg in messages]
        return await render_template('chat/index.html', 
                                   username=username,
                                   messages=formatted_messages,
                                   error="Rate limit exceeded. Please wait before sending another message.")
    
    # Get user message from form
    form_data = await request.form
    user_message = form_data.get('message', '').strip()
    
    if not user_message:
        return redirect(url_for('chat.chat'))
    
    # Validate message length
    if len(user_message) > 10000:
        messages = await get_session_messages(session_id, 20)
        formatted_messages = [{'role': msg.get('role'), 'content': msg.get('content', ''), 
                             'timestamp': msg.get('timestamp')} for msg in messages]
        return await render_template('chat/index.html', 
                                   username=username,
                                   messages=formatted_messages,
                                   error="Message too long. Maximum 10,000 characters allowed.")
    
    # Save user message (store raw, escape for display)
    await save_message(user_id, 'user', user_message, session_id)
    
    # Check cache first
    prompt_hash = hashlib.md5(user_message.encode()).hexdigest()
    cached_response = await get_cached_response(prompt_hash)
    
    if cached_response:
        # Save cached response and redirect
        await save_message(user_id, 'assistant', cached_response, session_id)
        return redirect(url_for('chat.chat'))
    
    # Generate chunked streaming response
    return Response(
        generate_chat_stream(user_id, session_id, user_message, username, prompt_hash),
        content_type='text/html; charset=utf-8'
    )

async def generate_chat_stream(user_id: str, session_id: str, user_message: str, username: str, prompt_hash: str):
    """Generate chunked HTML response with AI streaming"""
    
    # Get chat history for context
    chat_history = await get_session_messages(session_id, 10)
    
    # Render the streaming template start
    template_start = await render_template('chat/streaming_start.html', 
                                         username=username,
                                         messages=chat_history,
                                         user_message=escape_html(user_message))
    yield template_start
    
    # Force browser to render immediately
    yield " " * 1024  # Padding to trigger browser rendering
    
    # Stream AI response
    full_response = ""
    try:
        async for chunk in stream_ai_response(user_message, chat_history):
            if chunk:
                # Escape HTML in chunk for safe display
                safe_chunk = escape_html(chunk)
                full_response += chunk  # Store unescaped for database
                yield safe_chunk
                
                # Add small padding for consistent streaming
                if len(safe_chunk) < 5:
                    yield " " * (5 - len(safe_chunk))
    
    except Exception as e:
        error_msg = f"\n\n[Stream Error: {str(e)}]"
        yield escape_html(error_msg)
        full_response += error_msg
    
    # Render the streaming template end
    template_end = await render_template('chat/streaming_end.html')
    yield template_end
    
    # Save the complete AI response to database and cache
    if full_response.strip():
        await save_message(user_id, 'assistant', full_response.strip(), session_id)
        await cache_response(prompt_hash, full_response.strip())

# Health check for AI service
@chat_bp.route('/chat/health')
@login_required
async def chat_health():
    """Check if Devstral AI service is healthy"""
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
                        'ollama_url': OLLAMA_URL
                    }
        return {'status': 'unhealthy', 'error': 'Service unavailable'}
    except Exception as e:
        return {'status': 'error', 'error': str(e)}