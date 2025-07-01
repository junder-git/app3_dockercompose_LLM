# blueprints/api.py
from quart import Blueprint, jsonify, request, session
from quart_auth import login_required, current_user
from .models import ChatSession
from .database import (
    get_session_messages, get_user_chat_sessions,
    create_chat_session, get_chat_session, delete_chat_session,
    get_or_create_current_session
)
from .utils import sanitize_html

api_bp = Blueprint('api', __name__, url_prefix='/api')

@api_bp.route('/chat/history')
@login_required
async def chat_history():
    # Get current session for this user
    current_session_id = await get_or_create_current_session(current_user.auth_id)
    
    # Get session object
    session_obj = await get_chat_session(current_session_id)
    
    messages = await get_session_messages(current_session_id)
    
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'id': msg.get('id'),
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp')
        })
    
    return jsonify({
        'messages': formatted_messages,
        'session': {
            'id': session_obj.id,
            'title': session_obj.title
        } if session_obj else None
    })

@api_bp.route('/chat/sessions')
@login_required
async def get_user_sessions():
    """Get all chat sessions for the current user"""
    sessions = await get_user_chat_sessions(current_user.auth_id)
    
    session_data = []
    for session_obj in sessions:
        # Get message count for each session
        messages = await get_session_messages(session_obj.id)
        message_count = len(messages)
        
        session_data.append({
            'id': session_obj.id,
            'title': session_obj.title,
            'created_at': session_obj.created_at,
            'updated_at': session_obj.updated_at,
            'message_count': message_count
        })
    
    return jsonify({'sessions': session_data})

@api_bp.route('/chat/sessions', methods=['POST'])
@login_required
async def create_new_session():
    """Create a new chat session"""
    data = await request.get_json()
    title = sanitize_html(data.get('title', '')) if data else None
    
    session_obj = await create_chat_session(current_user.auth_id, title)
    
    # Update current session in user's session storage
    session[f"current_session_{current_user.auth_id}"] = session_obj.id
    
    return jsonify({
        'session': {
            'id': session_obj.id,
            'title': session_obj.title,
            'created_at': session_obj.created_at,
            'updated_at': session_obj.updated_at
        }
    })

@api_bp.route('/chat/sessions/<session_id>/switch', methods=['POST'])
@login_required
async def switch_session(session_id):
    """Switch to a different chat session"""
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != current_user.auth_id:
        return jsonify({'error': 'Session not found'}), 404
    
    # Update current session
    session[f"current_session_{current_user.auth_id}"] = session_id
    
    # Get messages for this session
    messages = await get_session_messages(session_id)
    
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'id': msg.get('id'),
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp')
        })
    
    return jsonify({
        'session': {
            'id': session_obj.id,
            'title': session_obj.title,
            'created_at': session_obj.created_at,
            'updated_at': session_obj.updated_at
        },
        'messages': formatted_messages
    })

@api_bp.route('/chat/sessions/<session_id>', methods=['DELETE'])
@login_required
async def delete_session(session_id):
    """Delete a chat session"""
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != current_user.auth_id:
        return jsonify({'error': 'Session not found'}), 404
    
    # Don't allow deleting the last session
    user_sessions = await get_user_chat_sessions(current_user.auth_id)
    if len(user_sessions) <= 1:
        return jsonify({'error': 'Cannot delete the last session'}), 400
    
    await delete_chat_session(current_user.auth_id, session_id)
    
    # If this was the current session, switch to another one
    current_session_key = f"current_session_{current_user.auth_id}"
    if session.get(current_session_key) == session_id:
        remaining_sessions = await get_user_chat_sessions(current_user.auth_id)
        if remaining_sessions:
            session[current_session_key] = remaining_sessions[0].id
    
    return jsonify({'success': True})