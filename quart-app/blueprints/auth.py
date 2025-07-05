# quart-app/blueprints/auth.py - With auth decorators included
from quart import Blueprint, render_template, request, redirect, url_for, session, flash, jsonify
from quart_auth import login_user, logout_user, login_required, current_user, AuthUser
from werkzeug.security import generate_password_hash, check_password_hash
from functools import wraps
import os
from .models import User
from .utils import sanitize_html, generate_csrf_token
from .database import save_user, get_user_by_username, get_pending_users_count, get_all_users, get_current_user_data

auth_bp = Blueprint('auth', __name__)

# Get all settings from environment
MAX_PENDING_USERS = int(os.environ['MAX_PENDING_USERS'])
MIN_USERNAME_LENGTH = int(os.environ['MIN_USERNAME_LENGTH'])
MAX_USERNAME_LENGTH = int(os.environ['MAX_USERNAME_LENGTH'])
MIN_PASSWORD_LENGTH = int(os.environ['MIN_PASSWORD_LENGTH'])
MAX_PASSWORD_LENGTH = int(os.environ['MAX_PASSWORD_LENGTH'])

# Authentication decorators
def require_auth(f):
    """Simple decorator to require authentication"""
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        if not await current_user.is_authenticated:
            if request.is_json:
                return jsonify({'error': 'Authentication required', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        # Check if user is approved
        user_data = await get_current_user_data(current_user.auth_id)
        if not user_data or (not user_data.is_approved and not user_data.is_admin):
            if request.is_json:
                return jsonify({'error': 'Account not approved', 'redirect': '/login'}), 403
            return redirect(url_for('auth.login'))
        
        return await f(*args, **kwargs)
    return decorated_function

def require_admin(f):
    """Simple decorator to require admin privileges"""
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        if not await current_user.is_authenticated:
            if request.is_json:
                return jsonify({'error': 'Authentication required', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        # Check if user is admin
        user_data = await get_current_user_data(current_user.auth_id)
        if not user_data or not user_data.is_admin:
            if request.is_json:
                return jsonify({'error': 'Admin privileges required'}), 403
            return redirect(url_for('auth.login'))
        
        return await f(*args, **kwargs)
    return decorated_function

# Auth routes
@auth_bp.route('/login', methods=['GET', 'POST'])
async def login():
    if request.method == 'POST':
        data = await request.form
        username = sanitize_html(data.get('username'))
        password = data.get('password')  # Don't sanitize passwords
        
        user = await get_user_by_username(username)
        
        if user and check_password_hash(user.password_hash, password):
            # Check if user is approved (or is admin)
            if user.is_admin or user.is_approved:
                login_user(AuthUser(user.id))
                return redirect(url_for('chat.chat'))
            else:
                return await render_template('auth/login.html', 
                                           error='Your account is pending admin approval. Please wait for activation.')
        else:
            return await render_template('auth/login.html', error='Invalid username or password')
    
    return await render_template('auth/login.html')

@auth_bp.route('/register', methods=['GET', 'POST'])
async def register():
    # Check pending users limit first
    pending_count = await get_pending_users_count()
    if pending_count >= MAX_PENDING_USERS:
        return await render_template('auth/register.html', 
                                   error=f'Registration temporarily closed. Too many pending approvals ({pending_count}/{MAX_PENDING_USERS}). Please try again later.',
                                   registration_closed=True)
    
    if request.method == 'POST':
        data = await request.form
        username = sanitize_html(data.get('username'))
        password = data.get('password')
        confirm_password = data.get('confirm_password')
        
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
        existing_user = await get_user_by_username(username)
        if existing_user:
            return await render_template('auth/register.html', 
                                       error='Username already exists',
                                       pending_count=pending_count,
                                       max_pending=MAX_PENDING_USERS)
        
        # Double-check pending users limit (in case it changed while form was being filled)
        current_pending_count = await get_pending_users_count()
        if current_pending_count >= MAX_PENDING_USERS:
            return await render_template('auth/register.html', 
                                       error=f'Registration temporarily closed. Too many pending approvals ({current_pending_count}/{MAX_PENDING_USERS}). Please try again later.',
                                       registration_closed=True)
        
        # Create new user (pending approval)
        new_user = User(
            username=username,
            password_hash=generate_password_hash(password),
            is_admin=False,
            is_approved=False  # Requires admin approval
        )
        await save_user(new_user)
        
        return await render_template('auth/register.html', 
                                   success='Registration successful! Your account is pending admin approval. You will be notified when activated.',
                                   pending_count=current_pending_count + 1,
                                   max_pending=MAX_PENDING_USERS)
    
    return await render_template('auth/register.html',
                               pending_count=pending_count,
                               max_pending=MAX_PENDING_USERS,
                               min_username_length=MIN_USERNAME_LENGTH,
                               max_username_length=MAX_USERNAME_LENGTH,
                               min_password_length=MIN_PASSWORD_LENGTH,
                               max_password_length=MAX_PASSWORD_LENGTH)

@auth_bp.route('/logout')
@login_required
async def logout():
    logout_user()
    session.clear()
    return redirect(url_for('auth.login'))