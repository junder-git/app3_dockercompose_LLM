# quart-app/blueprints/chat.py - Clean Chunked Response Implementation
from quart import Blueprint, render_template, request, redirect, url_for, Response
from quart_auth import login_required, current_user
import hashlib
from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response
)
from .ollama_client import get_ai_response_chunked
from .utils import sanitize_html, escape_html

chat_bp = Blueprint('chat', __name__)

@chat_bp.route('/chat', methods=['GET', 'POST'])
@login_required
async def chat():
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
    
    # Check rate limit
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
    
    # Save user message (no sanitization for storage)
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
    """Generate chunked HTML response with AI streaming - uses templates"""
    
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
        async for chunk in get_ai_response_chunked(user_message, chat_history):
            if chunk:
                # Escape HTML in chunk for safe display
                safe_chunk = escape_html(chunk)
                full_response += chunk  # Store unescaped for database
                yield safe_chunk
                
                # Add padding for consistent streaming
                if len(safe_chunk) < 10:
                    yield " " * (10 - len(safe_chunk))
    
    except Exception as e:
        error_msg = f"\n\n[Error: {str(e)}]"
        yield escape_html(error_msg)
        full_response += error_msg
    
    # Render the streaming template end
    template_end = await render_template('chat/streaming_end.html')
    yield template_end
    
    # Save the complete AI response to database and cache
    if full_response.strip():
        await save_message(user_id, 'assistant', full_response.strip(), session_id)
        await cache_response(prompt_hash, full_response.strip())