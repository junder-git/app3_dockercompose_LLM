# quart-app/blueprints/auth.py - Updated with pending user approval
from quart import Blueprint, render_template, request, redirect, url_for, session, flash
from quart_auth import login_user, logout_user, login_required, current_user, AuthUser
from werkzeug.security import generate_password_hash, check_password_hash
from .models import User
from .utils import sanitize_html, generate_csrf_token
from .database import save_user, get_user_by_username, get_pending_users_count, get_all_users

auth_bp = Blueprint('auth', __name__)

MAX_PENDING_USERS = 10

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
    if request.method == 'POST':
        data = await request.form
        username = sanitize_html(data.get('username'))
        password = data.get('password')
        confirm_password = data.get('confirm_password')
        
        # Validate inputs
        if len(username) < 3:
            return await render_template('auth/register.html', error='Username must be at least 3 characters')
        if len(password) < 6:
            return await render_template('auth/register.html', error='Password must be at least 6 characters')
        if password != confirm_password:
            return await render_template('auth/register.html', error='Passwords do not match')
        
        # Check if user exists
        existing_user = await get_user_by_username(username)
        if existing_user:
            return await render_template('auth/register.html', error='Username already exists')
        
        # Check pending users limit
        pending_count = await get_pending_users_count()
        if pending_count >= MAX_PENDING_USERS:
            return await render_template('auth/register.html', 
                                       error=f'Registration temporarily closed. Too many pending approvals ({pending_count}/{MAX_PENDING_USERS})')
        
        # Create new user (pending approval)
        new_user = User(
            username=username,
            password_hash=generate_password_hash(password),
            is_admin=False,
            is_approved=False  # Requires admin approval
        )
        await save_user(new_user)
        
        return await render_template('auth/register.html', 
                                   success='Registration successful! Your account is pending admin approval. You will be notified when activated.')
    
    return await render_template('auth/register.html')

@auth_bp.route('/logout')
@login_required
async def logout():
    logout_user()
    session.clear()
    return redirect(url_for('auth.login'))