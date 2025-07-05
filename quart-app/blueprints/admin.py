# quart-app/blueprints/admin.py - Fixed with proper authentication
from quart import Blueprint, render_template, request, redirect, url_for, flash, g, jsonify
from quart_auth import current_user, login_required
from .database import (
    get_current_user_data, get_all_users, get_user_messages,
    get_database_stats, cleanup_database, delete_user,
    get_pending_users, approve_user, reject_user
)

admin_bp = Blueprint('admin', __name__)

async def check_admin_access():
    """Check if user has admin access"""
    if not await current_user.is_authenticated:
        return redirect(url_for('auth.login'))
    
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data or not user_data.is_admin:
        return redirect(url_for('auth.login'))
    
    return None  # Access granted

@admin_bp.route('/admin')
async def admin():
    """Admin dashboard - With auth check"""
    # Check admin access
    auth_response = await check_admin_access()
    if auth_response:
        return auth_response
    
    # Get database stats, users, and pending users
    stats = await get_database_stats()
    users = await get_all_users()
    pending_users = await get_pending_users()
    
    return await render_template('admin/index.html', 
                               stats=stats, 
                               users=users, 
                               pending_users=pending_users)

@admin_bp.route('/admin/cleanup', methods=['POST'])
async def admin_database_cleanup():
    """Perform database cleanup operations via form - With auth check"""
    # Check admin access
    auth_response = await check_admin_access()
    if auth_response:
        return auth_response
    
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
async def admin_approve_user():
    """Approve a pending user - With auth check"""
    # Check admin access
    auth_response = await check_admin_access()
    if auth_response:
        return auth_response
    
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
async def admin_reject_user():
    """Reject and delete a pending user - With auth check"""
    # Check admin access
    auth_response = await check_admin_access()
    if auth_response:
        return auth_response
    
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
async def admin_user_detail(user_id):
    """View detailed user information and chat history - With auth check"""
    # Check admin access
    auth_response = await check_admin_access()
    if auth_response:
        return auth_response
    
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
async def admin_delete_user(user_id):
    """Delete a user via form submission - With auth check"""
    # Check admin access
    auth_response = await check_admin_access()
    if auth_response:
        return auth_response
    
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
async def admin_system_info():
    """Get system information - With auth check"""
    # Check admin access (for JSON endpoints, return JSON error)
    if not await current_user.is_authenticated:
        return jsonify({'error': 'Authentication required'}), 401
    
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data or not user_data.is_admin:
        return jsonify({'error': 'Admin privileges required'}), 403
    
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

# Add auth checks to all other API endpoints too...
@admin_bp.route('/admin/api/stats')
async def admin_api_stats():
    """Get database stats via API - With auth check"""
    if not await current_user.is_authenticated:
        return jsonify({'error': 'Authentication required'}), 401
    
    user_data = await get_current_user_data(current_user.auth_id)
    if not user_data or not user_data.is_admin:
        return jsonify({'error': 'Admin privileges required'}), 403
    
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

# ... (add similar auth checks to all other admin API endpoints)