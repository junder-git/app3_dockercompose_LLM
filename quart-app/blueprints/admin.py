# quart-app/blueprints/admin.py - FIXED with proper route handling
from quart import Blueprint, render_template, request, redirect, url_for, flash, g, jsonify
from quart_auth import current_user, login_required
from .database import (
    get_current_user_data, get_all_users, get_user_messages,
    get_database_stats, cleanup_database, delete_user,
    get_pending_users, approve_user, reject_user
)

# FIXED: Create blueprint with explicit url_prefix
admin_bp = Blueprint('admin', __name__, url_prefix='')

# FIXED: Simple require_admin decorator
def require_admin(f):
    """Simple admin decorator"""
    from functools import wraps
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        print(f"🔐 Admin auth check for {request.endpoint}")
        
        if not await current_user.is_authenticated:
            print(f"🔐 Admin: User not authenticated")
            if request.is_json:
                return jsonify({'error': 'Authentication required'}), 401
            return redirect(url_for('auth.login'))
        
        try:
            user_data = await get_current_user_data(current_user.auth_id)
            if not user_data or not user_data.is_admin:
                print(f"🔐 Admin: User not admin")
                if request.is_json:
                    return jsonify({'error': 'Admin privileges required'}), 403
                return redirect(url_for('auth.login'))
        except Exception as e:
            print(f"🔐 Admin auth error: {e}")
            if request.is_json:
                return jsonify({'error': 'Authentication error'}), 401
            return redirect(url_for('auth.login'))
        
        print(f"🔐 Admin auth successful")
        return await f(*args, **kwargs)
    return decorated_function

@admin_bp.route('/admin')
@require_admin
async def admin():
    """Admin dashboard - FIXED"""
    print(f"🔗 Admin dashboard accessed")
    
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
@require_admin
async def admin_test():
    """Simple test route for admin"""
    print(f"🔗 Admin test route accessed")
    
    try:
        user_data = await get_current_user_data(current_user.auth_id)
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
@require_admin
async def admin_database_cleanup():
    """Perform database cleanup operations via form"""
    print(f"🔗 Admin cleanup request")
    
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
@require_admin
async def admin_approve_user():
    """Approve a pending user"""
    print(f"🔗 Admin approve user request")
    
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
@require_admin
async def admin_reject_user():
    """Reject and delete a pending user"""
    print(f"🔗 Admin reject user request")
    
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
@require_admin
async def admin_user_detail(user_id):
    """View detailed user information and chat history"""
    print(f"🔗 Admin user detail for: {user_id}")
    
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
@require_admin
async def admin_delete_user(user_id):
    """Delete a user via form submission"""
    print(f"🔗 Admin delete user: {user_id}")
    
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

print("✅ Admin Blueprint FIXED and configured")