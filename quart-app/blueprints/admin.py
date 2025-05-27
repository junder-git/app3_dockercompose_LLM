# blueprints/admin.py
from quart import Blueprint, render_template, jsonify, request, redirect, url_for
from quart_auth import login_required, current_user
from functools import wraps
from .database import (
    get_current_user_data, get_all_users, get_user_messages,
    get_database_stats, cleanup_database
)
from datetime import datetime

admin_bp = Blueprint('admin', __name__)

def admin_required(f):
    @wraps(f)
    @login_required
    async def decorated_function(*args, **kwargs):
        user_data = await get_current_user_data()
        if not user_data or not user_data.is_admin:
            return redirect(url_for('chat.chat'))
        return await f(*args, **kwargs)
    return decorated_function

@admin_bp.route('/admin')
@admin_required
async def admin():
    return await render_template('admin.html')

@admin_bp.route('/api/admin/users')
@admin_required
async def admin_users():
    users = await get_all_users()
    
    users_data = []
    for user in users:
        users_data.append({
            'id': user.id,
            'username': user.username,
            'is_admin': user.is_admin,
            'created_at': user.created_at
        })
    
    return jsonify({'users': users_data})

@admin_bp.route('/api/admin/chat/<user_id>')
@admin_required
async def admin_user_chat(user_id):
    # Get all messages for the user across all sessions
    messages = await get_user_messages(user_id)
    
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'id': msg.get('id'),
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp')
        })
    
    return jsonify({'messages': formatted_messages})

@admin_bp.route('/api/admin/database/stats')
@admin_required
async def get_admin_database_stats():
    """Get database statistics for admin panel"""
    stats = await get_database_stats()
    return jsonify(stats)

@admin_bp.route('/api/admin/database/cleanup', methods=['POST'])
@admin_required
async def admin_database_cleanup():
    """Perform database cleanup operations"""
    data = await request.get_json()
    cleanup_type = data.get('type')
    
    if not cleanup_type:
        return jsonify({'error': 'Cleanup type is required'}), 400
    
    valid_types = ['complete_reset', 'fix_users', 'recreate_admin', 'clear_cache', 'fix_sessions']
    if cleanup_type not in valid_types:
        return jsonify({'error': 'Invalid cleanup type'}), 400
    
    # Perform cleanup
    result = await cleanup_database(cleanup_type, current_user.auth_id)
    
    if result['success']:
        return jsonify(result)
    else:
        return jsonify(result), 500

@admin_bp.route('/api/admin/database/backup')
@admin_required
async def create_database_backup():
    """Create a database backup"""
    try:
        from ..database import get_redis
        r = await get_redis()
        
        # Get all keys and their data
        all_keys = await r.keys("*")
        backup_data = {}
        
        for key in all_keys:
            key_type = await r.type(key)
            
            if key_type == 'string':
                backup_data[key] = {
                    'type': 'string',
                    'value': await r.get(key)
                }
            elif key_type == 'hash':
                backup_data[key] = {
                    'type': 'hash',
                    'value': await r.hgetall(key)
                }
            elif key_type == 'set':
                backup_data[key] = {
                    'type': 'set',
                    'value': list(await r.smembers(key))
                }
            elif key_type == 'zset':
                backup_data[key] = {
                    'type': 'zset',
                    'value': await r.zrange(key, 0, -1, withscores=True)
                }
        
        backup = {
            'timestamp': datetime.utcnow().isoformat(),
            'total_keys': len(all_keys),
            'data': backup_data
        }
        
        return jsonify(backup)
        
    except Exception as e:
        current_app.logger.error(f"Backup creation failed: {e}")
        return jsonify({'error': str(e)}), 500