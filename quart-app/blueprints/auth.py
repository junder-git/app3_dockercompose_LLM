# quart-app/blueprints/auth.py - FIXED version with proper route handling
from quart import Blueprint, render_template, request, redirect, url_for, session, flash, jsonify
from quart_auth import login_user, logout_user, login_required, current_user, AuthUser
from werkzeug.security import generate_password_hash, check_password_hash
from functools import wraps
import os
from .models import User
from .utils import sanitize_html, generate_csrf_token
from .database import save_user, get_user_by_username, get_pending_users_count, get_all_users, get_current_user_data

# FIXED: Create blueprint with explicit url_prefix
auth_bp = Blueprint('auth', __name__, url_prefix='')

# Get all settings from environment
MAX_PENDING_USERS = int(os.environ['MAX_PENDING_USERS'])
MIN_USERNAME_LENGTH = int(os.environ['MIN_USERNAME_LENGTH'])
MAX_USERNAME_LENGTH = int(os.environ['MAX_USERNAME_LENGTH'])
MIN_PASSWORD_LENGTH = int(os.environ['MIN_PASSWORD_LENGTH'])
MAX_PASSWORD_LENGTH = int(os.environ['MAX_PASSWORD_LENGTH'])

print(f"🔧 Auth Blueprint Config:")
print(f"  MAX_PENDING_USERS: {MAX_PENDING_USERS}")
print(f"  Username length: {MIN_USERNAME_LENGTH}-{MAX_USERNAME_LENGTH}")
print(f"  Password length: {MIN_PASSWORD_LENGTH}-{MAX_PASSWORD_LENGTH}")

# Authentication decorators
def require_auth(f):
    """Simple decorator to require authentication"""
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        print(f"🔐 require_auth: Checking authentication for {request.endpoint}")
        
        if not await current_user.is_authenticated:
            print(f"🔐 require_auth: User not authenticated")
            if request.is_json:
                return jsonify({'error': 'Authentication required', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        # Check if user is approved
        try:
            user_data = await get_current_user_data(current_user.auth_id)
            if not user_data or (not user_data.is_approved and not user_data.is_admin):
                print(f"🔐 require_auth: User not approved")
                if request.is_json:
                    return jsonify({'error': 'Account not approved', 'redirect': '/login'}), 403
                return redirect(url_for('auth.login'))
        except Exception as e:
            print(f"🔐 require_auth: Error checking user data: {e}")
            if request.is_json:
                return jsonify({'error': 'Authentication error', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        print(f"🔐 require_auth: Authentication successful")
        return await f(*args, **kwargs)
    return decorated_function

def require_admin(f):
    """Simple decorator to require admin privileges"""
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        print(f"🔐 require_admin: Checking admin privileges for {request.endpoint}")
        
        if not await current_user.is_authenticated:
            print(f"🔐 require_admin: User not authenticated")
            if request.is_json:
                return jsonify({'error': 'Authentication required', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        # Check if user is admin
        try:
            user_data = await get_current_user_data(current_user.auth_id)
            if not user_data or not user_data.is_admin:
                print(f"🔐 require_admin: User not admin")
                if request.is_json:
                    return jsonify({'error': 'Admin privileges required'}), 403
                return redirect(url_for('auth.login'))
        except Exception as e:
            print(f"🔐 require_admin: Error checking admin status: {e}")
            if request.is_json:
                return jsonify({'error': 'Authentication error', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        print(f"🔐 require_admin: Admin authentication successful")
        return await f(*args, **kwargs)
    return decorated_function

# FIXED: Auth routes with proper error handling
@auth_bp.route('/login', methods=['GET', 'POST'])
async def login():
    """Login route with improved error handling"""
    print(f"🔐 Login route accessed: {request.method}")
    
    try:
        if request.method == 'POST':
            print(f"🔐 Processing login form")
            data = await request.form
            username = sanitize_html(data.get('username', '').strip())
            password = data.get('password', '')  # Don't sanitize passwords
            
            print(f"🔐 Login attempt for username: {username}")
            
            if not username or not password:
                print(f"🔐 Login failed: Missing credentials")
                return await render_template('auth/login.html', 
                                           error='Username and password are required')
            
            try:
                user = await get_user_by_username(username)
                print(f"🔐 User lookup result: {'Found' if user else 'Not found'}")
                
                if user and check_password_hash(user.password_hash, password):
                    print(f"🔐 Password check: Success")
                    # Check if user is approved (or is admin)
                    if user.is_admin or user.is_approved:
                        print(f"🔐 User approved, logging in")
                        login_user(AuthUser(user.id))
                        print(f"🔐 Login successful, redirecting to chat")
                        return redirect(url_for('chat.chat'))
                    else:
                        print(f"🔐 User not approved")
                        return await render_template('auth/login.html', 
                                                   error='Your account is pending admin approval. Please wait for activation.')
                else:
                    print(f"🔐 Invalid credentials")
                    return await render_template('auth/login.html', 
                                               error='Invalid username or password')
            except Exception as e:
                print(f"🔐 Login error: {e}")
                return await render_template('auth/login.html', 
                                           error='Login error occurred. Please try again.')
        
        # GET request - show login form
        print(f"🔐 Showing login form")
        return await render_template('auth/login.html')
        
    except Exception as e:
        print(f"❌ Login route error: {e}")
        return await render_template('auth/login.html', 
                                   error='An error occurred. Please try again.')

@auth_bp.route('/register', methods=['GET', 'POST'])
async def register():
    """Register route with improved error handling"""
    print(f"🔐 Register route accessed: {request.method}")
    
    try:
        # Check pending users limit first
        pending_count = await get_pending_users_count()
        print(f"🔐 Pending users: {pending_count}/{MAX_PENDING_USERS}")
        
        if pending_count >= MAX_PENDING_USERS:
            print(f"🔐 Registration closed - too many pending users")
            return await render_template('auth/register.html', 
                                       error=f'Registration temporarily closed. Too many pending approvals ({pending_count}/{MAX_PENDING_USERS}). Please try again later.',
                                       registration_closed=True)
        
        if request.method == 'POST':
            print(f"🔐 Processing registration form")
            data = await request.form
            username = sanitize_html(data.get('username', '').strip())
            password = data.get('password', '')
            confirm_password = data.get('confirm_password', '')
            
            print(f"🔐 Registration attempt for username: {username}")
            
            # Validate inputs using environment variables
            if len(username) < MIN_USERNAME_LENGTH:
                return await render_template('auth/register.html', 
                                           error=f'Username must be at least {MIN_USERNAME_LENGTH} characters',
                                           pending_count=pending_count,
                                           max_pending=MAX_PENDING_USERS)
            
            if len(username) > MAX_USERNAME_LENGTH:
                return await render_template('auth/register.html', 
                                           error=f'Username must be no more than {MAX_USERNAME_LENGTH} characters',
                                           pending_count=pending_count,
                                           max_pending=MAX_PENDING_USERS)
            
            if len(password) < MIN_PASSWORD_LENGTH:
                return await render_template('auth/register.html', 
                                           error=f'Password must be at least {MIN_PASSWORD_LENGTH} characters',
                                           pending_count=pending_count,
                                           max_pending=MAX_PENDING_USERS)
            
            if len(password) > MAX_PASSWORD_LENGTH:
                return await render_template('auth/register.html', 
                                           error=f'Password must be no more than {MAX_PASSWORD_LENGTH} characters',
                                           pending_count=pending_count,
                                           max_pending=MAX_PENDING_USERS)
            
            if password != confirm_password:
                return await render_template('auth/register.html', 
                                           error='Passwords do not match',
                                           pending_count=pending_count,
                                           max_pending=MAX_PENDING_USERS)
            
            # Check if user exists
            try:
                existing_user = await get_user_by_username(username)
                if existing_user:
                    print(f"🔐 Username already exists")
                    return await render_template('auth/register.html', 
                                               error='Username already exists',
                                               pending_count=pending_count,
                                               max_pending=MAX_PENDING_USERS)
                
                # Double-check pending users limit (in case it changed while form was being filled)
                current_pending_count = await get_pending_users_count()
                if current_pending_count >= MAX_PENDING_USERS:
                    print(f"🔐 Registration closed during processing")
                    return await render_template('auth/register.html', 
                                               error=f'Registration temporarily closed. Too many pending approvals ({current_pending_count}/{MAX_PENDING_USERS}). Please try again later.',
                                               registration_closed=True)
                
                # Create new user (pending approval)
                print(f"🔐 Creating new user")
                new_user = User(
                    username=username,
                    password_hash=generate_password_hash(password),
                    is_admin=False,
                    is_approved=False  # Requires admin approval
                )
                await save_user(new_user)
                
                print(f"🔐 Registration successful for: {username}")
                return await render_template('auth/register.html', 
                                           success='Registration successful! Your account is pending admin approval. You will be notified when activated.',
                                           pending_count=current_pending_count + 1,
                                           max_pending=MAX_PENDING_USERS)
                                           
            except Exception as e:
                print(f"🔐 Registration error: {e}")
                return await render_template('auth/register.html', 
                                           error='Registration failed. Please try again.',
                                           pending_count=pending_count,
                                           max_pending=MAX_PENDING_USERS)
        
        # GET request - show registration form
        print(f"🔐 Showing registration form")
        return await render_template('auth/register.html',
                                   pending_count=pending_count,
                                   max_pending=MAX_PENDING_USERS,
                                   min_username_length=MIN_USERNAME_LENGTH,
                                   max_username_length=MAX_USERNAME_LENGTH,
                                   min_password_length=MIN_PASSWORD_LENGTH,
                                   max_password_length=MAX_PASSWORD_LENGTH)
        
    except Exception as e:
        print(f"❌ Register route error: {e}")
        return await render_template('auth/register.html', 
                                   error='An error occurred. Please try again.',
                                   pending_count=0,
                                   max_pending=MAX_PENDING_USERS)

@auth_bp.route('/logout')
@login_required
async def logout():
    """Logout route"""
    print(f"🔐 Logout route accessed")
    try:
        logout_user()
        session.clear()
        print(f"🔐 Logout successful")
        return redirect(url_for('auth.login'))
    except Exception as e:
        print(f"❌ Logout error: {e}")
        return redirect(url_for('auth.login'))

print("✅ Auth Blueprint FIXED and configured")