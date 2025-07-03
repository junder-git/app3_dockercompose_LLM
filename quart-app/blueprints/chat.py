# quart-app/blueprints/chat.py - Fixed form handling and options
import os
import hashlib
import aiohttp
import asyncio
import json
from typing import List, Dict, AsyncGenerator
from quart import Blueprint, render_template, request, redirect, url_for, Response, current_app
from quart_auth import login_required, current_user

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response
)
from .utils import escape_html

chat_bp = Blueprint('chat', __name__)

# AI Model configuration - HIGH PERFORMANCE 7.5GB
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL', 'devstral:24b')
MODEL_TEMPERATURE = float(os.environ.get('MODEL_TEMPERATURE', '0.7'))
MODEL_TOP_P = float(os.environ.get('MODEL_TOP_P', '0.9'))
MODEL_MAX_TOKENS = int(os.environ.get('MODEL_MAX_TOKENS', '2048'))
MODEL_TIMEOUT = int(os.environ.get('MODEL_TIMEOUT', '120'))

# Hardware settings
OLLAMA_GPU_LAYERS = int(os.environ.get('OLLAMA_GPU_LAYERS', '12'))
OLLAMA_NUM_THREAD = int(os.environ.get('OLLAMA_NUM_THREAD', '4'))

def get_active_model():
    """Get the active model name from the init script"""
    try:
        with open('/tmp/active_model', 'r') as f:
            return f.read().strip()
    except:
        return OLLAMA_MODEL

ACTIVE_MODEL = get_active_model()

async def stream_ai_response(prompt: str, chat_history: List[Dict] = None) -> AsyncGenerator[str, None]:
    """Stream AI response - HIGH PERFORMANCE with valid options only"""
    
    try:
        # Build messages array
        messages = []
        
        # Use good context history with higher VRAM
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
        
        # HIGH PERFORMANCE payload with ONLY VALID options
        payload = {
            'model': ACTIVE_MODEL,
            'messages': messages,
            'stream': True,
            'keep_alive': -1,
            'options': {
                'temperature': MODEL_TEMPERATURE,
                'top_p': MODEL_TOP_P,
                'num_predict': MODEL_MAX_TOKENS,
                'num_ctx': 16384,
                'repeat_penalty': 1.1,
                'top_k': 40,
                # ONLY VALID options - removed invalid ones
                'num_gpu': OLLAMA_GPU_LAYERS,
                'num_thread': OLLAMA_NUM_THREAD,
                'num_batch': 256
            }
        }
        
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
        yield f"\n\n[Timeout]: Response took longer than {MODEL_TIMEOUT}s."
    except aiohttp.ClientError as e:
        yield f"\n\n[Connection Error]: {str(e)}"
    except Exception as e:
        print(f"Devstral AI error: {e}")
        yield f"\n\n[Error]: AI service unavailable."

@chat_bp.route('/chat', methods=['GET', 'POST'])
@login_required
async def chat():
    """Main chat interface"""
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))
    
    current_session_id = await get_or_create_current_session(user_data.id)
    
    if request.method == 'POST':
        return await handle_chat_message(user_data.id, current_session_id, user_data.username)
    
    # GET request - show chat page
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
    """Handle chat message with proper duplicate prevention"""
    
    # Check rate limit
    if not await check_rate_limit(user_id):
        messages = await get_session_messages(session_id, 15)
        formatted_messages = [{'role': msg.get('role'), 'content': msg.get('content', ''), 
                             'timestamp': msg.get('timestamp')} for msg in messages]
        return await render_template('chat/index.html', 
                                   username=username,
                                   messages=formatted_messages,
                                   error="Rate limit exceeded. Please wait before sending another message.")
    
    # Get user message
    form_data = await request.form
    user_message = form_data.get('message', '').strip()
    
    if not user_message:
        return redirect(url_for('chat.chat'))
    
    # Higher message length limit
    if len(user_message) > 5000:
        messages = await get_session_messages(session_id, 15)
        formatted_messages = [{'role': msg.get('role'), 'content': msg.get('content', ''), 
                             'timestamp': msg.get('timestamp')} for msg in messages]
        return await render_template('chat/index.html', 
                                   username=username,
                                   messages=formatted_messages,
                                   error="Message too long. Maximum 5,000 characters allowed.")
    
    # ROBUST duplicate prevention with timestamp check
    import time
    current_time = time.time()
    
    # Check for duplicate submission in last 10 seconds
    recent_messages = await get_session_messages(session_id, 5)
    for msg in recent_messages:
        if (msg.get('role') == 'user' and 
            msg.get('content') == user_message and 
            msg.get('timestamp')):
            try:
                from datetime import datetime
                msg_time = datetime.fromisoformat(msg.get('timestamp').replace('Z', '+00:00'))
                if (current_time - msg_time.timestamp()) < 10:  # Within 10 seconds
                    print(f"Duplicate message detected within 10 seconds, redirecting")
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
        return redirect(url_for('chat.chat'))
    
    # Generate streaming response
    return Response(
        generate_chat_stream(user_id, session_id, user_message, username, prompt_hash),
        content_type='text/html; charset=utf-8'
    )

async def generate_chat_stream(user_id: str, session_id: str, user_message: str, username: str, prompt_hash: str):
    """Generate chunked HTML response with FIXED form handling"""
    
    # Get chat history
    chat_history = await get_session_messages(session_id, 8)
    
    # Enhanced HTML with PROPER form handling
    html_start = f'''<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Chat - Devstral AI</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
    <link href="/static/css/styles.css" rel="stylesheet">
    <style>
        .chat-container {{
            max-width: 900px;
            margin: 0 auto;
        }}
        .message {{
            margin-bottom: 1rem;
            padding: 1rem;
            border-radius: 0.5rem;
        }}
        .user-message {{
            background-color: #0d6efd;
            color: white;
            margin-left: 2rem;
        }}
        .assistant-message {{
            background-color: #343a40;
            color: #f8f9fa;
            margin-right: 2rem;
        }}
        .streaming-message {{
            background-color: #198754;
            color: white;
            margin-right: 2rem;
        }}
        .processing-indicator {{
            text-align: center;
            color: #28a745;
            font-style: italic;
            margin: 1rem 0;
        }}
        .message-content pre {{
            margin: 0;
            white-space: pre-wrap;
            word-break: break-word;
            font-family: inherit;
        }}
        .performance-badge {{
            background-color: #198754;
            color: white;
            padding: 0.25rem 0.5rem;
            border-radius: 0.25rem;
            font-size: 0.75rem;
        }}
    </style>
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="/">
                <i class="bi bi-robot"></i> Devstral AI
                <span class="performance-badge">7.5GB Mode</span>
            </a>
            <div class="navbar-nav ms-auto">
                <span class="nav-link">
                    <i class="bi bi-person-circle"></i> {escape_html(username)}
                </span>
                <a class="nav-link" href="/logout">
                    <i class="bi bi-box-arrow-right"></i> Logout
                </a>
            </div>
        </div>
    </nav>
    <main class="container-fluid py-4">
        <div class="row">
            <div class="col-12">
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <h2><i class="bi bi-chat-dots"></i> Chat with AI</h2>
                    <div class="text-muted">
                        <i class="bi bi-person"></i> {escape_html(username)}
                        <br><small class="performance-badge">High Performance • 7.5GB VRAM</small>
                    </div>
                </div>
                <div class="chat-container">
                    <div class="chat-messages">'''
    
    # Add recent messages
    for msg in chat_history:
        role = msg.get('role')
        content = escape_html(msg.get('content', ''))
        message_class = 'user-message' if role == 'user' else 'assistant-message'
        html_start += f'''
                        <div class="message {message_class}">
                            <div class="message-content">
                                <pre>{content}</pre>
                            </div>
                        </div>'''
    
    # Add user's new message
    html_start += f'''
                        <div class="message user-message">
                            <div class="message-content">
                                <pre>{escape_html(user_message)}</pre>
                            </div>
                        </div>
                        
                        <div class="processing-indicator">
                            <div class="spinner-border spinner-border-sm text-success" role="status">
                                <span class="visually-hidden">Loading...</span>
                            </div>
                            AI is processing (High Performance Mode)...
                        </div>
                        
                        <div class="message streaming-message">
                            <div class="message-content">
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
    
    # HTML end with NO JAVASCRIPT (pure form handling)
    html_end = f'''</pre>
                            </div>
                        </div>
                    </div>
                    
                    <form method="POST" action="/chat" class="mt-4">
                        <div class="input-group">
                            <textarea name="message" class="form-control" 
                                    placeholder="Type your message (max 5,000 chars)..." 
                                    rows="4" maxlength="5000" required autofocus></textarea>
                            <button class="btn btn-success" type="submit">
                                <i class="bi bi-send"></i> Send
                            </button>
                        </div>
                        <small class="text-muted mt-2 d-block">
                            <i class="bi bi-info-circle"></i> 
                            Submit with <strong>Send button</strong> • <strong>Shift+Enter</strong> for new line in textarea
                        </small>
                        <small class="text-success">
                            <i class="bi bi-lightning-fill"></i> High Performance Mode: 
                            7.5GB VRAM • No JavaScript • Pure HTML forms
                        </small>
                    </form>
                </div>
            </div>
        </div>
    </main>
    
    <!-- Bootstrap CSS only - NO JAVASCRIPT -->
    <!-- All interactions handled by pure HTML forms -->
</body>
</html>'''
    
    yield html_end
    
    # Save response
    if full_response.strip():
        await save_message(user_id, 'assistant', full_response.strip(), session_id)
        await cache_response(prompt_hash, full_response.strip())

# Health check
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
                        'performance_mode': '7.5GB High Performance',
                        'gpu_layers': OLLAMA_GPU_LAYERS,
                        'context_size': 16384
                    }
        return {'status': 'unhealthy', 'error': 'Service unavailable'}
    except Exception as e:
        return {'status': 'error', 'error': str(e)}