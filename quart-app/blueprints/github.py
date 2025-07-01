# blueprints/github.py
from quart import Blueprint, jsonify, request
from quart_auth import login_required, current_user
from .database import get_redis
from .utils import sanitize_html

github_bp = Blueprint('github', __name__, url_prefix='/api/github')

@github_bp.route('/settings', methods=['GET'])
@login_required
async def get_github_settings():
    """Get GitHub settings for current user"""
    r = await get_redis()
    
    # Get user's GitHub settings
    settings = await r.hgetall(f"github_settings:{current_user.auth_id}")
    
    return jsonify({
        'username': settings.get('username', ''),
        'has_token': bool(settings.get('token'))
    })

@github_bp.route('/settings', methods=['POST'])
@login_required
async def save_github_settings():
    """Save GitHub settings for current user"""
    r = await get_redis()
    data = await request.get_json()
    
    token = data.get('token', '').strip()
    username = sanitize_html(data.get('username', '').strip())
    
    if not token or not username:
        return jsonify({'error': 'Token and username are required'}), 400
    
    # Save to Redis
    await r.hset(f"github_settings:{current_user.auth_id}", mapping={
        'token': token,
        'username': username
    })
    
    # Set expiry for security (30 days)
    await r.expire(f"github_settings:{current_user.auth_id}", 30 * 24 * 60 * 60)
    
    return jsonify({'success': True})

@github_bp.route('/settings', methods=['DELETE'])
@login_required
async def delete_github_settings():
    """Delete GitHub settings for current user"""
    r = await get_redis()
    await r.delete(f"github_settings:{current_user.auth_id}")
    return jsonify({'success': True})