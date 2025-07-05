# quart-app/blueprints/admin.py - Updated with clean authentication
from quart import Blueprint, render_template, request, redirect, url_for, flash, g, jsonify
from quart_auth import current_user, login_required
from .database import (
    get_current_user_data, get_all_users, get_user_messages,
    get_database_stats, cleanup_database, delete_user,
    get_pending_users, approve_user, reject_user
)
from .auth import require_admin  # Import from auth module

admin_bp = Blueprint('admin', __name__)

@admin_bp.route('/admin')
@require_admin
async def admin():
    """Admin dashboard"""
    # Get database stats, users, and pending users
    stats = await get_database_stats()
    users = await get_all_users()
    pending_users = await get_pending_users()
    
    return await render_template('admin/index.html', 
                               stats=stats, 
                               users=users, 
                               pending_users=pending_users)

@admin_bp.route('/admin/cleanup', methods=['POST'])
@require_admin
async def admin_database_cleanup():
    """Perform database cleanup operations via form"""
    form_data = await request.form
    cleanup_type = form_data.get('type')
    
    if not cleanup_type:
        await flash('Cleanup type is required', 'error')
        return redirect(url_for('admin.admin'))
    
    valid_types = ['complete_reset', 'fix_users', 'recreate_admin', 'clear_cache', 'fix_sessions']
    if cleanup_type not in valid_types:
        await flash('Invalid cleanup type', 'error')
        return redirect(url_for('admin.admin'))
    
    # Perform cleanup
    result = await cleanup_database(cleanup_type, current_user.auth_id)
    
    if result['success']:
        await flash(result['message'], 'success')
    else:
        await flash(result['message'], 'error')
    
    return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/approve_user', methods=['POST'])
@require_admin
async def admin_approve_user():
    """Approve a pending user"""
    form_data = await request.form
    user_id = form_data.get('user_id')
    
    if not user_id:
        await flash('User ID is required', 'error')
        return redirect(url_for('admin.admin'))
    
    result = await approve_user(user_id)
    
    if result['success']:
        await flash(result['message'], 'success')
    else:
        await flash(result['message'], 'error')
    
    return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/reject_user', methods=['POST'])
@require_admin
async def admin_reject_user():
    """Reject and delete a pending user"""
    form_data = await request.form
    user_id = form_data.get('user_id')
    
    if not user_id:
        await flash('User ID is required', 'error')
        return redirect(url_for('admin.admin'))
    
    result = await reject_user(user_id)
    
    if result['success']:
        await flash(result['message'], 'success')
    else:
        await flash(result['message'], 'error')
    
    return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/user/<user_id>')
@require_admin
async def admin_user_detail(user_id):
    """View detailed user information and chat history"""
    # Get user messages
    messages = await get_user_messages(user_id)
    
    # Get user info
    users = await get_all_users()
    user_info = next((u for u in users if u.id == user_id), None)
    
    if not user_info:
        await flash('User not found', 'error')
        return redirect(url_for('admin.admin'))
    
    # Format messages for display
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp')
        })
    
    return await render_template('admin/user_detail.html', user=user_info, messages=formatted_messages)

@admin_bp.route('/admin/user/<user_id>/delete', methods=['POST'])
@require_admin
async def admin_delete_user(user_id):
    """Delete a user via form submission"""
    # Check if trying to delete self
    if user_id == current_user.auth_id:
        await flash('Cannot delete your own account', 'error')
        return redirect(url_for('admin.admin'))
    
    result = await delete_user(user_id)
    
    if result['success']:
        await flash(result['message'], 'success')
    else:
        await flash(result['message'], 'error')
    
    return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/system_info')
@require_admin
async def admin_system_info():
    """Get system information"""
    try:
        # Try to import psutil, but handle gracefully if not available
        try:
            import psutil
            import os
            
            # Get system stats
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            system_info = {
                'cpu_percent': cpu_percent,
                'memory_percent': memory.percent,
                'memory_used': f"{memory.used / (1024**3):.1f} GB",
                'memory_total': f"{memory.total / (1024**3):.1f} GB",
                'disk_percent': disk.percent,
                'disk_used': f"{disk.used / (1024**3):.1f} GB",
                'disk_total': f"{disk.total / (1024**3):.1f} GB",
                'load_average': os.getloadavg() if hasattr(os, 'getloadavg') else None
            }
            
            return jsonify({
                'success': True,
                'system_info': system_info
            })
            
        except ImportError:
            # psutil not available
            return jsonify({
                'success': False,
                'error': 'psutil not available - system monitoring disabled'
            })
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        })

@admin_bp.route('/admin/api/stats')
@require_admin
async def admin_api_stats():
    """Get database stats via API"""
    try:
        stats = await get_database_stats()
        return jsonify({
            'success': True,
            'stats': stats
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        })