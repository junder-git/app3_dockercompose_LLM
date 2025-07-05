# quart-app/blueprints/chat.py - FIXED server-side only with ENV vars
import os
import hashlib
import aiohttp
import asyncio
import json
import time
from typing import List, Dict
from quart import Blueprint, render_template, request, redirect, url_for, flash
from quart_auth import login_required, current_user

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response
)
from .utils import escape_html

chat_bp = Blueprint('chat', __name__)

# AI Model configuration - ONLY from environment variables
OLLAMA_URL = os.environ.get('OLLAMA_URL')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL')

# All parameters from environment - no fallbacks
MODEL_TEMPERATURE = float(os.environ.get('MODEL_TEMPERATURE', '0.7'))
MODEL_TOP_P = float(os.environ.get('MODEL_TOP_P', '0.9'))
MODEL_TOP_K = int(os.environ.get('MODEL_TOP_K', '40'))
MODEL_REPEAT_PENALTY = float(os.environ.get('MODEL_REPEAT_PENALTY', '1.1'))
MODEL_MAX_TOKENS = int(os.environ.get('MODEL_MAX_TOKENS', '1024'))
MODEL_TIMEOUT = int(os.environ.get('MODEL_TIMEOUT', '180'))

# Hardware settings from environment
OLLAMA_GPU_LAYERS = int(os.environ.get('OLLAMA_GPU_LAYERS', '29'))
OLLAMA_NUM_THREAD = int(os.environ.get('OLLAMA_NUM_THREAD', '4'))
OLLAMA_CONTEXT_SIZE = int(os.environ.get('OLLAMA_CONTEXT_SIZE', '8192'))
OLLAMA_BATCH_SIZE = int(os.environ.get('OLLAMA_BATCH_SIZE', '128'))

# CRITICAL: Memory management - proper boolean conversion
MODEL_USE_MMAP = os.environ.get('MODEL_USE_MMAP', 'false').lower() == 'true'
MODEL_USE_MLOCK = os.environ.get('MODEL_USE_MLOCK', 'true').lower() == 'true'

# Other settings from environment
OLLAMA_KEEP_ALIVE = os.environ.get('OLLAMA_KEEP_ALIVE', '-1')
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

async def get_ai_response(prompt: str, chat_history: List[Dict] = None) -> str:
    """Get AI response - server-side only, no streaming"""
    
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
            'stream': False,  # Server-side only
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
                    return f"API Error {response.status}: {error_text}"
                
                # Get response
                data = await response.json()
                
                if 'message' in data and 'content' in data['message']:
                    return data['message']['content']
                else:
                    return "Error: Invalid response format"
    
    except asyncio.TimeoutError:
        return f"Timeout: Response took longer than {MODEL_TIMEOUT}s."
    except aiohttp.ClientError as e:
        return f"Connection Error: {str(e)}"
    except Exception as e:
        print(f"AI error: {e}")
        return f"Error: AI service unavailable. ({str(e)})"

@chat_bp.route('/chat', methods=['GET', 'POST'])
@login_required
async def chat():
    """Main chat interface - pure server-side processing"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))
    
    current_session_id = await get_or_create_current_session(user_data.id)
    
    if request.method == 'POST':
        # Handle message submission
        return await handle_chat_message(user_data.id, current_session_id, user_data.username)
    
    # GET request - show chat page with messages
    messages = await get_session_messages(current_session_id, 25)
    
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
                               messages=formatted_messages)

async def handle_chat_message(user_id: str, session_id: str, username: str):
    """Handle chat message submission - server-side processing only"""
    
    # Check rate limit
    if not await check_rate_limit(user_id):
        flash('Rate limit exceeded. Please wait before sending another message.', 'error')
        return redirect(url_for('chat.chat'))
    
    # Get user message
    form_data = await request.form
    user_message = form_data.get('message', '').strip()
    
    if not user_message:
        flash('Message cannot be empty.', 'error')
        return redirect(url_for('chat.chat'))
    
    # Message length validation
    if len(user_message) > 10000:
        flash('Message too long. Maximum 10,000 characters.', 'error')
        return redirect(url_for('chat.chat'))
    
    # Check for recent duplicates
    recent_messages = await get_session_messages(session_id, 3)
    for msg in recent_messages:
        if (msg.get('role') == 'user' and 
            msg.get('content') == user_message and 
            msg.get('timestamp')):
            try:
                from datetime import datetime
                msg_time = datetime.fromisoformat(msg.get('timestamp').replace('Z', '+00:00'))
                if (time.time() - msg_time.timestamp()) < 10:
                    flash('Duplicate message detected. Please wait before sending the same message again.', 'error')
                    return redirect(url_for('chat.chat'))
            except:
                pass
    
    # Save user message
    await save_message(user_id, 'user', user_message, session_id)
    
    # Check cache
    prompt_hash = hashlib.md5(user_message.encode()).hexdigest()
    cached_response = await get_cached_response(prompt_hash)
    
    if cached_response:
        await save_message(user_id, 'assistant', cached_response, session_id)
        flash('Response retrieved from cache.', 'success')
        return redirect(url_for('chat.chat'))
    
    # Get chat history for context
    chat_history = await get_session_messages(session_id, 8)
    
    # Generate AI response
    try:
        ai_response = await get_ai_response(user_message, chat_history)
        
        if ai_response and ai_response.strip():
            # Save AI response
            await save_message(user_id, 'assistant', ai_response.strip(), session_id)
            await cache_response(prompt_hash, ai_response.strip())
            flash('AI response generated successfully.', 'success')
        else:
            flash('No response from AI. Please try again.', 'error')
    
    except Exception as e:
        print(f"Error generating AI response: {e}")
        flash('Error generating AI response. Please try again.', 'error')
    
    return redirect(url_for('chat.chat'))

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