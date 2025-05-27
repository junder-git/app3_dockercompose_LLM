# blueprints/chat.py
from quart import Blueprint, render_template, websocket, jsonify
from quart_auth import login_required, current_user
import json
import asyncio
import hashlib
from .models import ChatSession
from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response
)
from .utils import sanitize_html
from .ollama_client import get_ai_response

chat_bp = Blueprint('chat', __name__)

@chat_bp.route('/chat')
@login_required
async def chat():
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data:
        return redirect(url_for('auth.login'))
    
    # Get or create current session
    current_session_id = await get_or_create_current_session(user_data.id)
    
    return await render_template('chat.html', username=user_data.username)

@chat_bp.websocket('/ws')
@login_required
async def ws():
    """WebSocket endpoint for real-time chat"""
    try:
        # Get current session for this user
        current_session_id = await get_or_create_current_session(current_user.auth_id)
        
        while True:
            data = await websocket.receive_json()
            
            if data['type'] == 'chat':
                # Check rate limit
                if not await check_rate_limit(current_user.auth_id):
                    await websocket.send_json({
                        'type': 'error',
                        'message': 'Rate limit exceeded. Please wait a moment before sending another message.'
                    })
                    continue
                
                # Sanitize user input
                user_message = sanitize_html(data.get('message', ''))
                if not user_message:
                    continue
                
                # Save user message to current session
                asyncio.create_task(save_message(current_user.auth_id, 'user', user_message, current_session_id))
                
                # Send user message back for display
                await websocket.send_json({
                    'type': 'message',
                    'role': 'user',
                    'content': user_message
                })
                
                # Check cache first
                prompt_hash = hashlib.md5(user_message.encode()).hexdigest()
                cached_response = await get_cached_response(prompt_hash)
                
                if cached_response:
                    # Send cached response
                    await websocket.send_json({
                        'type': 'message',
                        'role': 'assistant',
                        'content': cached_response,
                        'cached': True
                    })
                    # Save to current session
                    asyncio.create_task(save_message(current_user.auth_id, 'assistant', cached_response, current_session_id))
                else:
                    # Get AI response from Ollama with chat history
                    chat_history = await get_session_messages(current_session_id, 10)  # Last 10 messages for context
                    full_response = await get_ai_response(user_message, websocket, chat_history)
                    
                    if full_response:
                        # Sanitize AI response before caching/saving
                        sanitized_response = sanitize_html(full_response)
                        
                        # Cache the response asynchronously
                        asyncio.create_task(cache_response(prompt_hash, sanitized_response))
                        # Save to current session
                        asyncio.create_task(save_message(current_user.auth_id, 'assistant', sanitized_response, current_session_id))
                        
                        # Send completion signal
                        await websocket.send_json({
                            'type': 'complete',
                            'role': 'assistant',
                            'content': sanitized_response
                        })
                
    except asyncio.CancelledError:
        pass
    except Exception as e:
        current_app.logger.error(f"WebSocket error: {e}")