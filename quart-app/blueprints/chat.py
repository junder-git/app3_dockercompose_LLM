# quart-app/blueprints/chat.py - FIXED single submit flow and mmap issue
import os
import hashlib
import aiohttp
import asyncio
import json
import time
from typing import List, Dict, AsyncGenerator
from quart import Blueprint, render_template, request, redirect, url_for, Response, current_app, session
from quart_auth import login_required, current_user

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response
)
from .utils import escape_html

chat_bp = Blueprint('chat', __name__)

# AI Model configuration - ONLY from environment, NO defaults
OLLAMA_URL = os.environ.get('OLLAMA_URL')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL')

# Model parameters - ONLY from environment, NO defaults
MODEL_TEMPERATURE = float(os.environ.get('MODEL_TEMPERATURE')) if os.environ.get('MODEL_TEMPERATURE') else None
MODEL_TOP_P = float(os.environ.get('MODEL_TOP_P')) if os.environ.get('MODEL_TOP_P') else None
MODEL_TOP_K = int(os.environ.get('MODEL_TOP_K')) if os.environ.get('MODEL_TOP_K') else None
MODEL_REPEAT_PENALTY = float(os.environ.get('MODEL_REPEAT_PENALTY')) if os.environ.get('MODEL_REPEAT_PENALTY') else None
MODEL_MAX_TOKENS = int(os.environ.get('MODEL_MAX_TOKENS')) if os.environ.get('MODEL_MAX_TOKENS') else None
MODEL_TIMEOUT = int(os.environ.get('MODEL_TIMEOUT')) if os.environ.get('MODEL_TIMEOUT') else None

# Mirostat settings - ONLY from environment
MODEL_MIROSTAT = int(os.environ.get('MODEL_MIROSTAT')) if os.environ.get('MODEL_MIROSTAT') else None
MODEL_MIROSTAT_ETA = float(os.environ.get('MODEL_MIROSTAT_ETA')) if os.environ.get('MODEL_MIROSTAT_ETA') else None
MODEL_MIROSTAT_TAU = float(os.environ.get('MODEL_MIROSTAT_TAU')) if os.environ.get('MODEL_MIROSTAT_TAU') else None

# Hardware and performance settings - ONLY from environment
OLLAMA_GPU_LAYERS = int(os.environ.get('OLLAMA_GPU_LAYERS')) if os.environ.get('OLLAMA_GPU_LAYERS') else None
OLLAMA_NUM_THREAD = int(os.environ.get('OLLAMA_NUM_THREAD')) if os.environ.get('OLLAMA_NUM_THREAD') else None
OLLAMA_CONTEXT_SIZE = int(os.environ.get('OLLAMA_CONTEXT_SIZE')) if os.environ.get('OLLAMA_CONTEXT_SIZE') else None
OLLAMA_BATCH_SIZE = int(os.environ.get('OLLAMA_BATCH_SIZE')) if os.environ.get('OLLAMA_BATCH_SIZE') else None

# Memory management settings - ONLY from environment (FIXED)
MODEL_USE_MMAP = os.environ.get('MODEL_USE_MMAP')
MODEL_USE_MLOCK = os.environ.get('MODEL_USE_MLOCK')

# Keep alive setting - ONLY from environment
OLLAMA_KEEP_ALIVE = os.environ.get('OLLAMA_KEEP_ALIVE')

# Stop sequences - ONLY from environment
MODEL_STOP_SEQUENCES = os.environ.get('MODEL_STOP_SEQUENCES')

def get_active_model():
    """Get the active model name from the init script"""
    try:
        with open('/tmp/active_model', 'r') as f:
            return f.read().strip()
    except:
        return OLLAMA_MODEL

ACTIVE_MODEL = get_active_model()

async def stream_ai_response(prompt: str, chat_history: List[Dict] = None) -> AsyncGenerator[str, None]:
    """Stream AI response with COMPLETE environment-driven configuration - NO defaults"""
    
    try:
        # Build messages array
        messages = []
        
        # Use context history
        if chat_history:
            for msg in chat_history[-8:]:
                role = msg.get('role')
                content = msg.get('content', '').strip()
                if role in ['user', 'assistant'] and content:
                    if len(content) > 2000:
                        content = content[:2000] + "..."
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
        
        # Base payload
        payload = {
            'model': ACTIVE_MODEL,
            'messages': messages,
            'stream': True,
            'options': {}
        }
        
        # Add keep_alive ONLY if set in environment
        if OLLAMA_KEEP_ALIVE is not None:
            payload['keep_alive'] = OLLAMA_KEEP_ALIVE
        
        # Add ONLY environment-configured options
        if MODEL_TEMPERATURE is not None:
            payload['options']['temperature'] = MODEL_TEMPERATURE
        if MODEL_TOP_P is not None:
            payload['options']['top_p'] = MODEL_TOP_P
        if MODEL_TOP_K is not None:
            payload['options']['top_k'] = MODEL_TOP_K
        if MODEL_REPEAT_PENALTY is not None:
            payload['options']['repeat_penalty'] = MODEL_REPEAT_PENALTY
        if MODEL_MAX_TOKENS is not None:
            payload['options']['num_predict'] = MODEL_MAX_TOKENS
        if OLLAMA_CONTEXT_SIZE is not None:
            payload['options']['num_ctx'] = OLLAMA_CONTEXT_SIZE
        if OLLAMA_BATCH_SIZE is not None:
            payload['options']['num_batch'] = OLLAMA_BATCH_SIZE
        if OLLAMA_GPU_LAYERS is not None:
            payload['options']['num_gpu'] = OLLAMA_GPU_LAYERS
        if OLLAMA_NUM_THREAD is not None:
            payload['options']['num_thread'] = OLLAMA_NUM_THREAD
        
        # FIXED: Proper boolean conversion for mmap/mlock
        if MODEL_USE_MMAP is not None:
            # Convert string to boolean properly
            use_mmap = MODEL_USE_MMAP.lower() in ['true', '1', 'yes', 'on']
            payload['options']['use_mmap'] = use_mmap
            print(f"🔧 MMAP setting: {MODEL_USE_MMAP} -> {use_mmap}")
        
        if MODEL_USE_MLOCK is not None:
            # Convert string to boolean properly
            use_mlock = MODEL_USE_MLOCK.lower() in ['true', '1', 'yes', 'on']
            payload['options']['use_mlock'] = use_mlock
            print(f"🔧 MLOCK setting: {MODEL_USE_MLOCK} -> {use_mlock}")
        
        if MODEL_MIROSTAT is not None:
            payload['options']['mirostat'] = MODEL_MIROSTAT
        if MODEL_MIROSTAT_ETA is not None:
            payload['options']['mirostat_eta'] = MODEL_MIROSTAT_ETA
        if MODEL_MIROSTAT_TAU is not None:
            payload['options']['mirostat_tau'] = MODEL_MIROSTAT_TAU
        if MODEL_STOP_SEQUENCES is not None:
            payload['options']['stop'] = MODEL_STOP_SEQUENCES
        
        print(f"🔧 AI Request Config (ONLY from env):")
        print(f"  Model: {ACTIVE_MODEL}")
        print(f"  Options: {payload['options']}")
        print(f"  Keep Alive: {payload.get('keep_alive', 'Not set')}")
        
        timeout = aiohttp.ClientTimeout(total=MODEL_TIMEOUT if MODEL_TIMEOUT else 120)
        
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
                
                # Process streaming response
                async for line in response.content:
                    if line:
                        try:
                            line_str = line.decode('utf-8').strip()
                            if line_str:
                                data = json.loads(line_str)
                                
                                if 'message' in data and 'content' in data['message']:
                                    chunk_text = data['message']['content']
                                    if chunk_text:
                                        yield chunk_text
                                
                                if data.get('done', False):
                                    break
                                    
                        except json.JSONDecodeError:
                            continue
                        except Exception as e:
                            print(f"Error processing chunk: {e}")
                            continue
    
    except asyncio.TimeoutError:
        yield f"\n\n[Timeout]: Response took longer than {MODEL_TIMEOUT if MODEL_TIMEOUT else 120}s."
    except aiohttp.ClientError as e:
        yield f"\n\n[Connection Error]: {str(e)}"
    except Exception as e:
        print(f"Devstral AI error: {e}")
        yield f"\n\n[Error]: AI service unavailable."

# FIXED: Single submit flow - NO duplicate templates/forms
@chat_bp.route('/chat', methods=['GET', 'POST'])
@login_required
async def chat():
    """FIXED: Single chat interface - no double submit"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))
    
    current_session_id = await get_or_create_current_session(user_data.id)
    
    if request.method == 'POST':
        # Handle message submission and return streaming response
        return await handle_chat_message_streaming(user_data.id, current_session_id, user_data.username)
    
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

async def handle_chat_message_streaming(user_id: str, session_id: str, username: str):
    """Handle chat message with streaming response - SINGLE SUBMIT"""
    
    # Check rate limit
    if not await check_rate_limit(user_id):
        return redirect(url_for('chat.chat'))
    
    # Get user message
    form_data = await request.form
    user_message = form_data.get('message', '').strip()
    
    if not user_message:
        return redirect(url_for('chat.chat'))
    
    # Message length validation
    if len(user_message) > 10000:
        return redirect(url_for('chat.chat'))
    
    # ENHANCED duplicate prevention
    duplicate_key = f"last_message_{user_id}_{session_id}"
    
    # Check session-based duplicate
    if duplicate_key in session:
        last_message_data = session[duplicate_key]
        if (last_message_data.get('content') == user_message and 
            time.time() - last_message_data.get('timestamp', 0) < 5):
            print(f"🚫 Duplicate message blocked for user {user_id}")
            return redirect(url_for('chat.chat'))
    
    # Check database duplicate
    recent_messages = await get_session_messages(session_id, 3)
    for msg in recent_messages:
        if (msg.get('role') == 'user' and 
            msg.get('content') == user_message and 
            msg.get('timestamp')):
            try:
                from datetime import datetime
                msg_time = datetime.fromisoformat(msg.get('timestamp').replace('Z', '+00:00'))
                if (time.time() - msg_time.timestamp()) < 10:
                    print(f"🚫 Database duplicate detected, redirecting")
                    return redirect(url_for('chat.chat'))
            except:
                pass
    
    # Record message to prevent duplicates
    session[duplicate_key] = {
        'content': user_message,
        'timestamp': time.time()
    }
    
    # Save user message ONCE
    await save_message(user_id, 'user', user_message, session_id)
    
    # Check cache
    prompt_hash = hashlib.md5(user_message.encode()).hexdigest()
    cached_response = await get_cached_response(prompt_hash)
    
    if cached_response:
        await save_message(user_id, 'assistant', cached_response, session_id)
        return redirect(url_for('chat.chat'))
    
    # Generate streaming response that redirects back to main chat
    return Response(
        generate_streaming_response(user_id, session_id, user_message, username, prompt_hash),
        content_type='text/html; charset=utf-8'
    )

async def generate_streaming_response(user_id: str, session_id: str, user_message: str, username: str, prompt_hash: str):
    """Generate streaming response that redirects back to main chat page"""
    
    # Get chat history
    chat_history = await get_session_messages(session_id, 8)
    
    # Simple streaming page that redirects when done
    html_start = f'''<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Response - Devstral AI</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
    <style>
        .streaming-container {{
            max-width: 800px;
            margin: 2rem auto;
            padding: 2rem;
        }}
        .ai-response {{
            background-color: #198754;
            color: white;
            padding: 1.5rem;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
        }}
        .user-message {{
            background-color: #0d6efd;
            color: white;
            padding: 1rem;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
        }}
        .processing {{
            text-align: center;
            color: #28a745;
            margin: 1rem 0;
        }}
        pre {{
            margin: 0;
            white-space: pre-wrap;
            word-break: break-word;
            font-family: inherit;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="streaming-container">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h4><i class="bi bi-chat-dots"></i> AI Response</h4>
                <span class="badge bg-success">Streaming</span>
            </div>
            
            <div class="user-message">
                <strong><i class="bi bi-person-fill"></i> You:</strong><br>
                <pre>{escape_html(user_message)}</pre>
            </div>
            
            <div class="processing">
                <div class="spinner-border spinner-border-sm text-success" role="status">
                    <span class="visually-hidden">Loading...</span>
                </div>
                AI is thinking...
            </div>
            
            <div class="ai-response">
                <strong><i class="bi bi-robot"></i> AI:</strong><br>
                <pre>'''
    
    yield html_start
    yield " " * 1024  # Browser padding
    
    # Stream AI response
    full_response = ""
    try:
        async for chunk in stream_ai_response(user_message, chat_history):
            if chunk:
                safe_chunk = escape_html(chunk)
                full_response += chunk
                yield safe_chunk
                
                # Small padding for consistent streaming
                if len(safe_chunk) < 5:
                    yield " " * (5 - len(safe_chunk))
    
    except Exception as e:
        error_msg = f"\n\n[Stream Error: {str(e)}]"
        yield escape_html(error_msg)
        full_response += error_msg
    
    # End streaming page with auto-redirect
    html_end = f'''</pre>
            </div>
            
            <div class="text-center mt-4">
                <div class="alert alert-success">
                    <i class="bi bi-check-circle"></i> Response complete! 
                    <a href="/chat" class="btn btn-success btn-sm ms-2">
                        <i class="bi bi-arrow-left"></i> Back to Chat
                    </a>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Auto-redirect after 3 seconds -->
    <script>
        setTimeout(function() {{
            window.location.href = '/chat';
        }}, 3000);
    </script>
</body>
</html>'''
    
    yield html_end
    
    # Save response to database
    if full_response.strip():
        await save_message(user_id, 'assistant', full_response.strip(), session_id)
        await cache_response(prompt_hash, full_response.strip())

# Health check
@chat_bp.route('/chat/health')
@login_required
async def chat_health():
    """Check AI service health with environment config"""
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
                        'config_source': 'environment_variables_only',
                        'environment_config': {
                            'temperature': MODEL_TEMPERATURE,
                            'top_p': MODEL_TOP_P,
                            'top_k': MODEL_TOP_K,
                            'context_size': OLLAMA_CONTEXT_SIZE,
                            'gpu_layers': OLLAMA_GPU_LAYERS,
                            'use_mmap': MODEL_USE_MMAP,
                            'use_mlock': MODEL_USE_MLOCK,
                            'keep_alive': OLLAMA_KEEP_ALIVE
                        }
                    }
        return {'status': 'unhealthy', 'error': 'Service unavailable'}
    except Exception as e:
        return {'status': 'error', 'error': str(e)}