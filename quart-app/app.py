# quart-app/app.py - Clean and Secure Application
import os
import secrets
from datetime import timedelta
from dotenv import load_dotenv

from quart import Quart, render_template, redirect, url_for, session, request, jsonify
from quart_auth import AuthUser, QuartAuth, current_user
from werkzeug.security import generate_password_hash

# Import only essential blueprints
from blueprints import auth_bp, chat_bp, admin_bp
from blueprints.database import get_user_by_username, save_user
from blueprints.models import User
from blueprints.utils import generate_csrf_token, validate_csrf_token

# Load environment variables
load_dotenv()

# Initialize Quart app
app = Quart(__name__)

# Configure Quart
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=int(os.environ.get('SESSION_LIFETIME_DAYS', '7')))

# Configure auth
app.config['QUART_AUTH_COOKIE_SECURE'] = os.environ.get('SECURE_COOKIES', 'false').lower() == 'true'
app.config['QUART_AUTH_COOKIE_HTTPONLY'] = True
app.config['QUART_AUTH_COOKIE_SAMESITE'] = 'Lax'

# Initialize extensions
auth = QuartAuth(app)

# Register essential blueprints only
app.register_blueprint(auth_bp)
app.register_blueprint(chat_bp)
app.register_blueprint(admin_bp)

# Make sessions permanent by default
@app.before_request
async def make_session_permanent():
    """Make sessions permanent (persist across browser sessions)"""
    session.permanent = True

# CSRF Protection for POST requests
@app.before_request
async def csrf_protect():
    """Validate CSRF token for state-changing requests"""
    if request.method in ['POST', 'PUT', 'DELETE', 'PATCH']:
        # Skip health check
        if request.path == '/health':
            return
            
        token = (await request.form).get('csrf_token') or request.headers.get('X-CSRF-Token')
        if not await validate_csrf_token(token):
            return jsonify({'error': 'Invalid CSRF token'}), 403

# Security Headers Middleware
@app.after_request
async def add_security_headers(response):
    """Add security headers to all responses"""
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'
    
    # Strict CSP - NO JavaScript allowed except Bootstrap
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
        "font-src 'self' https://cdn.jsdelivr.net; "
        "img-src 'self' data:; "
        "script-src https://cdn.jsdelivr.net; "  # Only Bootstrap JS
        "connect-src 'none'"  # No AJAX/WebSocket allowed
    )
    
    # Add CSRF token to all HTML responses
    if response.content_type and 'text/html' in response.content_type:
        response.headers['X-CSRF-Token'] = await generate_csrf_token()
    
    return response

# Template globals
@app.context_processor
async def inject_csrf_token():
    """Inject CSRF token into all templates"""
    return {'csrf_token': await generate_csrf_token()}

# Initialize admin user
async def init_admin():
    """Create default admin user if not exists"""
    ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
    ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin123')
    
    admin = await get_user_by_username(ADMIN_USERNAME)
    if not admin:
        admin_user = User(
            user_id='admin',  # Fixed ID for admin
            username=ADMIN_USERNAME,
            password_hash=generate_password_hash(ADMIN_PASSWORD),
            is_admin=True
        )
        await save_user(admin_user)
        app.logger.info(f"Created default admin user: {ADMIN_USERNAME}")
    else:
        # Ensure existing admin has correct admin status
        if not admin.is_admin:
            admin.is_admin = True
            await save_user(admin)
            app.logger.info(f"Fixed admin status for user: {ADMIN_USERNAME}")

@app.before_serving
async def startup():
    await init_admin()

# Health check endpoint
@app.route('/health')
async def health():
    return jsonify({'status': 'healthy', 'service': 'devstral-chat'})

# Routes
@app.route('/')
async def index():
    if await current_user.is_authenticated:
        return redirect(url_for('chat.chat'))
    return redirect(url_for('auth.login'))

if __name__ == '__main__':
    app.run(debug=True)