# quart-app/blueprints/chat.py - FIXED with minimal essential routes
import os
import hashlib
import aiohttp
import asyncio
import json
import time
import uuid
from typing import List, Dict, AsyncGenerator
from quart import Blueprint, render_template, request, redirect, url_for, flash, Response
from quart_auth import current_user, login_required

from .database import (
    get_current_user_data, get_or_create_current_session,
    save_message, get_session_messages, check_rate_limit,
    get_cached_response, cache_response, get_user_chat_sessions,
    get_chat_session, delete_chat_session, create_chat_session,
    clear_session_messages
)
from .utils import escape_html

# FIXED: Create blueprint with explicit url_prefix
chat_bp = Blueprint('chat', __name__, url_prefix='')

# AI Model configuration - Essential only
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://localhost:11434')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL', 'llama2')
CHAT_HISTORY_LIMIT = int(os.environ.get('CHAT_HISTORY_LIMIT', '50'))
RATE_LIMIT_MAX = int(os.environ.get('RATE_LIMIT_MESSAGES_PER_MINUTE', '10'))

print(f"🔧 Chat Blueprint FIXED Config:")
print(f"  OLLAMA_URL: {OLLAMA_URL}")
print(f"  OLLAMA_MODEL: {OLLAMA_MODEL}")
print(f"  CHAT_HISTORY_LIMIT: {CHAT_HISTORY_LIMIT}")
print(f"  RATE_LIMIT_MAX: {RATE_LIMIT_MAX}")

# FIXED: Simple require_auth decorator for chat
def require_auth(f):
    """Simple auth decorator for chat routes"""
    from functools import wraps
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        print(f"🔐 Chat auth check for {request.endpoint}")
        
        if not await current_user.is_authenticated:
            print(f"🔐 Chat: User not authenticated")
            if request.is_json:
                return {'error': 'Authentication required'}, 401
            return redirect(url_for('auth.login'))
        
        try:
            user_data = await get_current_user_data(current_user.auth_id)
            if not user_data or (not user_data.is_approved and not user_data.is_admin):
                print(f"🔐 Chat: User not approved")
                if request.is_json:
                    return {'error': 'Account not approved'}, 403
                return redirect(url_for('auth.login'))
        except Exception as e:
            print(f"🔐 Chat auth error: {e}")
            if request.is_json:
                return {'error': 'Authentication error'}, 401
            return redirect(url_for('auth.login'))
        
        print(f"🔐 Chat auth successful")
        return await f(*args, **kwargs)
    return decorated_function

# FIXED: Essential chat routes only
@chat_bp.route('/chat', methods=['GET'])
@chat_bp.route('/chat/new', methods=['GET'])
@require_auth
async def chat():
    """Main chat interface - FIXED"""
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

@chat_bp.route('/chat/test', methods=['GET'])
@require_auth
async def chat_test():
    """Simple test route for chat"""
    print(f"🔗 Chat test route accessed")
    
    try:
        user_data = await get_current_user_data(current_user.auth_id)
        return {
            'status': 'success',
            'message': 'Chat blueprint is working',
            'user': user_data.username if user_data else 'Unknown',
            'timestamp': time.time()
        }
    except Exception as e:
        print(f"❌ Chat test error: {e}")
        return {'error': str(e)}, 500

@chat_bp.route('/chat/health', methods=['GET'])
@require_auth
async def chat_health():
    """Check AI service health - simplified"""
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
                    
                    return {
                        'status': 'healthy' if model_loaded else 'model_not_found',
                        'active_model': OLLAMA_MODEL,
                        'available_models': available_models,
                        'ollama_url': OLLAMA_URL
                    }
        return {'status': 'unhealthy', 'error': 'Service unavailable'}
    except Exception as e:
        print(f"❌ Health check error: {e}")
        return {'status': 'error', 'error': str(e)}

@chat_bp.route('/chat/clear', methods=['POST'])
@require_auth
async def clear_current_chat():
    """Clear all messages from current chat session"""
    print(f"🔗 Clear chat request")
    
    try:
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
        
    except Exception as e:
        print(f"❌ Clear chat error: {e}")
        return {'success': False, 'message': str(e)}, 500

print("✅ Chat Blueprint FIXED - Essential routes only")