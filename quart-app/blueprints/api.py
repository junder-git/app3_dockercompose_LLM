# blueprints/api.py - Updated with chat management endpoints
import datetime
from quart import Blueprint, jsonify, request, session
from quart_auth import login_required, current_user
from .models import ChatSession
from .database import (
    get_session_messages, get_or_create_user_session,
    get_chat_session, clear_user_chat, compress_user_chat,
    get_chat_statistics
)
from .utils import sanitize_html

api_bp = Blueprint('api', __name__, url_prefix='/api')

@api_bp.route('/chat/history')
@login_required
async def chat_history():
    # Get user's single session
    session_obj = await get_or_create_user_session(current_user.auth_id)
    
    messages = await get_session_messages(session_obj.id)
    
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
        }
    })

@api_bp.route('/chat/clear', methods=['POST'])
@login_required
async def clear_chat():
    """Clear all messages in the user's chat"""
    result = await clear_user_chat(current_user.auth_id)
    
    if result['success']:
        return jsonify(result)
    else:
        return jsonify(result), 400

@api_bp.route('/chat/compress', methods=['POST'])
@login_required
async def compress_chat():
    """Compress chat to keep only recent messages"""
    data = await request.get_json()
    keep_count = data.get('keep_count', 50)
    
    # Validate keep_count
    if not isinstance(keep_count, int) or keep_count < 10 or keep_count > 200:
        return jsonify({'error': 'keep_count must be between 10 and 200'}), 400
    
    result = await compress_user_chat(current_user.auth_id, keep_count)
    
    if result['success']:
        return jsonify(result)
    else:
        return jsonify(result), 400

@api_bp.route('/chat/statistics')
@login_required
async def chat_statistics():
    """Get statistics about the user's chat"""
    stats = await get_chat_statistics(current_user.auth_id)
    return jsonify(stats)

@api_bp.route('/chat/export')
@login_required
async def export_chat():
    """Export chat history as JSON"""
    # Get user's session
    session_obj = await get_or_create_user_session(current_user.auth_id)
    
    # Get all messages
    messages = await get_session_messages(session_obj.id, limit=None)
    
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp')
        })
    
    export_data = {
        'user': current_user.auth_id,
        'session_id': session_obj.id,
        'session_title': session_obj.title,
        'exported_at': "JUNKNOWN", # USE datetime.whatever in here 
        'message_count': len(formatted_messages),
        'messages': formatted_messages
    }
    
    return jsonify(export_data)