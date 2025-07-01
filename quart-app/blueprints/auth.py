# blueprints/auth.py
from quart import Blueprint, render_template, request, redirect, url_for, session
from quart_auth import login_user, logout_user, login_required, current_user, AuthUser
from werkzeug.security import generate_password_hash, check_password_hash
from .models import User
from .utils import sanitize_html, generate_csrf_token
from .database import save_user, get_user_by_username

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/login', methods=['GET', 'POST'])
async def login():
    if request.method == 'POST':
        data = await request.form
        username = sanitize_html(data.get('username'))
        password = data.get('password')  # Don't sanitize passwords
        
        user = await get_user_by_username(username)
        
        if user and check_password_hash(user.password_hash, password):
            login_user(AuthUser(user.id))
            return redirect(url_for('chat.chat'))
        else:
            return await render_template('login.html', error='Invalid username or password')
    
    return await render_template('login.html')

@auth_bp.route('/register', methods=['GET', 'POST'])
async def register():
    if request.method == 'POST':
        data = await request.form
        username = sanitize_html(data.get('username'))
        password = data.get('password')
        
        # Validate inputs
        if len(username) < 3:
            return await render_template('register.html', error='Username must be at least 3 characters')
        if len(password) < 6:
            return await render_template('register.html', error='Password must be at least 6 characters')
        
        # Check if user exists
        existing_user = await get_user_by_username(username)
        if existing_user:
            return await render_template('register.html', error='Username already exists')
        
        # Create new user
        new_user = User(
            username=username,
            password_hash=generate_password_hash(password),
            is_admin=False
        )
        await save_user(new_user)
        
        return redirect(url_for('auth.login'))
    
    return await render_template('register.html')

@auth_bp.route('/logout')
@login_required
async def logout():
    logout_user()
    session.clear()
    return redirect(url_for('auth.login'))