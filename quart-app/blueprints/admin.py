# quart-app/blueprints/admin.py - COMPLETELY FIXED VERSION
from quart import Blueprint, render_template, request, redirect, url_for, flash, g, jsonify
from quart_auth import current_user, login_required
from .database import (
    get_current_user_data, get_all_users, get_user_messages,
    get_database_stats, cleanup_database, delete_user,
    get_pending_users, approve_user, reject_user
)

# Create blueprint WITHOUT url_prefix (let app handle it)
admin_bp = Blueprint('admin', __name__)

# FIXED: Helper functions instead of decorators
async def get_current_user_info():
    """Get current user info safely"""
    if not await current_user.is_authenticated:
        return None
    
    try:
        return await get_current_user_data(current_user.auth_id)
    except Exception as e:
        print(f"⚠️ Error getting user data: {e}")
        return None

async def check_user_admin():
    """Check if current user is admin"""
    user_info = await get_current_user_info()
    if not user_info:
        return False
    return user_info.is_admin

# FIXED: Admin routes using @login_required
@admin_bp.route('/admin')
@login_required
async def admin():
    """Admin dashboard - COMPLETELY FIXED"""
    print(f"🔗 Admin dashboard accessed")
    
    # Check if user is admin (not in decorator to avoid loops)
    if not await check_user_admin():
        print(f"🔗 Admin: User not admin, redirecting to login")
        return redirect(url_for('auth.login'))
    
    try:
        # Get database stats, users, and pending users
        print(f"🔗 Admin: Getting stats")
        stats = await get_database_stats()
        
        print(f"🔗 Admin: Getting users")
        users = await get_all_users()
        
        print(f"🔗 Admin: Getting pending users")
        pending_users = await get_pending_users()
        
        print(f"🔗 Admin: Rendering template")
        return await render_template('admin/index.html', 
                                   stats=stats, 
                                   users=users, 
                                   pending_users=pending_users)
                                   
    except Exception as e:
        print(f"❌ Admin dashboard error: {e}")
        return await render_template('admin/index.html', 
                                   stats={'error': str(e)}, 
                                   users=[], 
                                   pending_users=[])

@admin_bp.route('/admin/test')
@login_required
async def admin_test():
    """Simple test route for admin"""
    print(f"🔗 Admin test route accessed")
    
    # Check admin
    if not await check_user_admin():
        return {'error': 'Admin privileges required'}, 403
    
    try:
        user_data = await get_current_user_info()
        return {
            'status': 'success',
            'message': 'Admin blueprint is working',
            'admin': user_data.username if user_data else 'Unknown',
            'is_admin': user_data.is_admin if user_data else False
        }
    except Exception as e:
        print(f"❌ Admin test error: {e}")
        return {'error': str(e)}, 500

@admin_bp.route('/admin/cleanup', methods=['POST'])
@login_required
async def admin_database_cleanup():
    """Perform database cleanup operations via form"""
    print(f"🔗 Admin cleanup request")
    
    # Check admin
    if not await check_user_admin():
        await flash('Admin privileges required', 'error')
        return redirect(url_for('auth.login'))
    
    try:
        form_data = await request.form
        cleanup_type = form_data.get('type')
        
        if not cleanup_type:
            await flash('Cleanup type is required', 'error')
            return redirect(url_for('admin.admin'))
        
        valid_types = ['complete_reset', 'fix_users', 'recreate_admin', 'clear_cache', 'fix_sessions']
        if cleanup_type not in valid_types:
            await flash('Invalid cleanup type', 'error')
            return redirect(url_for('admin.admin'))
        
        print(f"🔗 Admin: Performing cleanup: {cleanup_type}")
        
        # Perform cleanup
        result = await cleanup_database(cleanup_type, current_user.auth_id)
        
        if result['success']:
            await flash(result['message'], 'success')
        else:
            await flash(result['message'], 'error')
        
        return redirect(url_for('admin.admin'))
        
    except Exception as e:
        print(f"❌ Admin cleanup error: {e}")
        await flash(f'Cleanup error: {str(e)}', 'error')
        return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/approve_user', methods=['POST'])
@login_required
async def admin_approve_user():
    """Approve a pending user"""
    print(f"🔗 Admin approve user request")
    
    # Check admin
    if not await check_user_admin():
        await flash('Admin privileges required', 'error')
        return redirect(url_for('auth.login'))
    
    try:
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
        
    except Exception as e:
        print(f"❌ Admin approve user error: {e}")
        await flash(f'Approval error: {str(e)}', 'error')
        return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/reject_user', methods=['POST'])
@login_required
async def admin_reject_user():
    """Reject and delete a pending user"""
    print(f"🔗 Admin reject user request")
    
    # Check admin
    if not await check_user_admin():
        await flash('Admin privileges required', 'error')
        return redirect(url_for('auth.login'))
    
    try:
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
        
    except Exception as e:
        print(f"❌ Admin reject user error: {e}")
        await flash(f'Rejection error: {str(e)}', 'error')
        return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/user/<user_id>')
@login_required
async def admin_user_detail(user_id):
    """View detailed user information and chat history"""
    print(f"🔗 Admin user detail for: {user_id}")
    
    # Check admin
    if not await check_user_admin():
        await flash('Admin privileges required', 'error')
        return redirect(url_for('auth.login'))
    
    try:
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
        
    except Exception as e:
        print(f"❌ Admin user detail error: {e}")
        await flash(f'Error loading user details: {str(e)}', 'error')
        return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/user/<user_id>/delete', methods=['POST'])
@login_required
async def admin_delete_user(user_id):
    """Delete a user via form submission"""
    print(f"🔗 Admin delete user: {user_id}")
    
    # Check admin
    if not await check_user_admin():
        await flash('Admin privileges required', 'error')
        return redirect(url_for('auth.login'))
    
    try:
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
        
    except Exception as e:
        print(f"❌ Admin delete user error: {e}")
        await flash(f'Delete error: {str(e)}', 'error')
        return redirect(url_for('admin.admin'))

@admin_bp.route('/admin/system_info')
@login_required
async def admin_system_info():
    """Get system information"""
    # Check admin
    if not await check_user_admin():
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

@admin_bp.route('/admin/api/stats')
@login_required
async def admin_api_stats():
    """Get database stats via API"""
    # Check admin
    if not await check_user_admin():
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

print("✅ Admin Blueprint COMPLETELY FIXED - Using @login_required properly")