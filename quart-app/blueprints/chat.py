# blueprints/chat.py
from quart import Blueprint, render_template, websocket, jsonify, redirect, url_for, current_app
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
                
                # Get user input - NO sanitization for AI processing
                user_message = data.get('message', '').strip()
                if not user_message:
                    continue
                
                # Save raw user message to current session
                await save_message(current_user.auth_id, 'user', user_message, current_session_id)
                
                # Send user message back for display (only sanitize for display)
                await websocket.send_json({
                    'type': 'message',
                    'role': 'user',
                    'content': user_message  # Show raw message to user
                })
                
                # Check cache first
                prompt_hash = hashlib.md5(user_message.encode()).hexdigest()
                cached_response = await get_cached_response(prompt_hash)
                
                if cached_response:
                    # Send cached response (no sanitization)
                    await websocket.send_json({
                        'type': 'message',
                        'role': 'assistant',
                        'content': cached_response,
                        'cached': True
                    })
                    # Raw response already stored in cache/database
                else:
                    # Get AI response from Ollama with chat history
                    chat_history = await get_session_messages(current_session_id, 10)
                    full_response = await get_ai_response(user_message, websocket, chat_history)
                    
                    if full_response:
                        # Store and cache raw AI response (NO sanitization)
                        await cache_response(prompt_hash, full_response)
                        await save_message(current_user.auth_id, 'assistant', full_response, current_session_id)
                        
                        # Send completion signal (no sanitization)
                        await websocket.send_json({
                            'type': 'complete',
                            'role': 'assistant',
                            'content': full_response
                        })
                
    except asyncio.CancelledError:
        pass
    except Exception as e:
        current_app.logger.error(f"WebSocket error: {e}")