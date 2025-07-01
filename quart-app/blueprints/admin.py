# quart-app/blueprints/admin.py - Fixed Admin Blueprint
from quart import Blueprint, render_template, request, redirect, url_for, flash, g
from quart_auth import login_required, current_user
from functools import wraps
from .database import (
    get_current_user_data, get_all_users, get_user_messages,
    get_database_stats, cleanup_database, delete_user
)

admin_bp = Blueprint('admin', __name__)

def admin_required(f):
    @wraps(f)
    @login_required
    async def decorated_function(*args, **kwargs):
        user_data = await get_current_user_data(current_user.auth_id)
        if not user_data or not user_data.is_admin:
            flash('Admin access required', 'error')
            return redirect(url_for('chat.chat'))
        return await f(*args, **kwargs)
    return decorated_function

@admin_bp.route('/admin')
@admin_required
async def admin():
    # Get database stats and users
    stats = await get_database_stats()
    users = await get_all_users()
    
    return await render_template('admin/admin.html', 
                               stats=stats, 
                               users=users)

@admin_bp.route('/admin/cleanup', methods=['POST'])
@admin_required
async def admin_database_cleanup():
    """Perform database cleanup operations via form"""
    form_data = await request.form
    cleanup_type = form_data.get('type')
    
    if not cleanup_type:
        flash('Cleanup type is required', 'error')
        return redirect(url_for('admin.admin'))
    
    valid_types = ['complete_reset', 'fix_users', 'recreate_admin', 'clear_cache', 'fix_sessions']
    if cleanup_type not in valid_types:
        flash('Invalid cleanup type', 'error')
        return redirect(url_for('admin.admin'))
    
    # Perform cleanup
    result = await cleanup_database(cleanup_type, current_user.auth_id)
    
    if result['success']:
        flash(result['message'], 'success')
    else:
        flash(result['message'], 'error')
    
    return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/user/<user_id>')
@admin_required
async def admin_user_detail(user_id):
    """View detailed user information and chat history"""
    # Get user messages
    messages = await get_user_messages(user_id)
    
    # Get user info
    users = await get_all_users()
    user_info = next((u for u in users if u.id == user_id), None)
    
    if not user_info:
        flash('User not found', 'error')
        return redirect(url_for('admin.admin'))
    
    # Format messages for display
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp')
        })
    
    return await render_template('admin/admin_user.html', 
                               user=user_info,
                               messages=formatted_messages)

@admin_bp.route('/admin/user/<user_id>/delete', methods=['POST'])
@admin_required
async def admin_delete_user(user_id):
    """Delete a user via form submission"""
    # Check if trying to delete self
    if user_id == current_user.auth_id:
        flash('Cannot delete your own account', 'error')
        return redirect(url_for('admin.admin'))
    
    result = await delete_user(user_id)
    
    if result['success']:
        flash(result['message'], 'success')
    else:
        flash(result['message'], 'error')
    
    return redirect(url_for('admin.admin'))