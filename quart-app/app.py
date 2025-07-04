# quart-app/app.py - Debug version with better error handling
import os
import sys
import secrets
import asyncio
from datetime import timedelta
from dotenv import load_dotenv

print("🔍 Starting Quart app initialization...")

try:
    from quart import Quart, render_template, redirect, url_for, session, request, jsonify, g
    from quart_auth import AuthUser, QuartAuth, current_user
    from werkzeug.security import generate_password_hash
    print("✅ Core imports successful")
except Exception as e:
    print(f"❌ Core import failed: {e}")
    sys.exit(1)

try:
    # Import only essential blueprints
    from blueprints import auth_bp, chat_bp, admin_bp
    from blueprints.database import get_user_by_username, save_user, get_current_user_data
    from blueprints.models import User
    from blueprints.utils import generate_csrf_token, validate_csrf_token
    print("✅ Blueprint imports successful")
except Exception as e:
    print(f"❌ Blueprint import failed: {e}")
    sys.exit(1)

# Load environment variables
load_dotenv()
print("✅ Environment loaded")

# Initialize Quart app
app = Quart(__name__)
print("✅ Quart app created")

# Configure Quart
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=int(os.environ.get('SESSION_LIFETIME_DAYS', '7')))

# Configure auth
app.config['QUART_AUTH_COOKIE_SECURE'] = os.environ.get('SECURE_COOKIES', 'false').lower() == 'true'
app.config['QUART_AUTH_COOKIE_HTTPONLY'] = True
app.config['QUART_AUTH_COOKIE_SAMESITE'] = 'Lax'

# Initialize extensions
try:
    auth = QuartAuth(app)
    print("✅ QuartAuth initialized")
except Exception as e:
    print(f"❌ QuartAuth initialization failed: {e}")
    sys.exit(1)

# Register essential blueprints only
try:
    app.register_blueprint(auth_bp)
    app.register_blueprint(chat_bp)
    app.register_blueprint(admin_bp)
    print("✅ Blueprints registered")
except Exception as e:
    print(f"❌ Blueprint registration failed: {e}")
    sys.exit(1)

# Make sessions permanent by default
@app.before_request
async def make_session_permanent():
    """Make sessions permanent (persist across browser sessions)"""
    session.permanent = True

# Load user data for templates
@app.before_request
async def load_user_data():
    """Load current user data for template context"""
    g.current_user_data = None
    try:
        if await current_user.is_authenticated:
            g.current_user_data = await get_current_user_data(current_user.auth_id)
    except Exception as e:
        print(f"⚠️ Error loading user data: {e}")
        g.current_user_data = None

# CSRF Protection for POST requests
@app.before_request
async def csrf_protect():
    """Validate CSRF token for state-changing requests"""
    if request.method in ['POST', 'PUT', 'DELETE', 'PATCH']:
        # Skip health check
        if request.path == '/health':
            return
            
        try:
            token = (await request.form).get('csrf_token') or request.headers.get('X-CSRF-Token')
            if not await validate_csrf_token(token):
                return jsonify({'error': 'Invalid CSRF token'}), 403
        except Exception as e:
            print(f"⚠️ CSRF validation error: {e}")
            return jsonify({'error': 'CSRF validation failed'}), 403

# Security Headers Middleware
@app.after_request
async def add_security_headers(response):
    """Add security headers to all responses"""
    try:
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['X-XSS-Protection'] = '1; mode=block'
        response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
        response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'
        
        # Simplified CSP - NO JavaScript
        response.headers['Content-Security-Policy'] = (
            "default-src 'self'; "
            "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
            "font-src 'self' https://cdn.jsdelivr.net; "
            "img-src 'self' data:; "
            "script-src 'none'; "
            "connect-src 'none'"
        )
        
        # Add CSRF token to all HTML responses
        if response.content_type and 'text/html' in response.content_type:
            try:
                response.headers['X-CSRF-Token'] = await generate_csrf_token()
            except:
                pass  # Don't fail the request if CSRF token generation fails
    except Exception as e:
        print(f"⚠️ Error adding security headers: {e}")
    
    return response

# Template globals
@app.context_processor
async def inject_template_globals():
    """Inject global variables into all templates"""
    try:
        return {
            'csrf_token': await generate_csrf_token(),
            'current_user_data': g.get('current_user_data')
        }
    except Exception as e:
        print(f"⚠️ Error injecting template globals: {e}")
        return {
            'csrf_token': '',
            'current_user_data': None
        }

# Initialize admin user
async def init_admin():
    """Create default admin user if not exists"""
    try:
        print("🔧 Initializing admin user...")
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
            print(f"✅ Created default admin user: {ADMIN_USERNAME}")
        else:
            # Ensure existing admin has correct admin status
            if not admin.is_admin:
                admin.is_admin = True
                await save_user(admin)
                print(f"✅ Fixed admin status for user: {ADMIN_USERNAME}")
            else:
                print(f"✅ Admin user already exists: {ADMIN_USERNAME}")
    except Exception as e:
        print(f"❌ Error initializing admin user: {e}")
        # Don't exit - let the app start anyway

@app.before_serving
async def startup():
    try:
        print("🚀 Running startup tasks...")
        await init_admin()
        print("✅ Startup tasks completed")
    except Exception as e:
        print(f"⚠️ Startup task error: {e}")

# Health check endpoint
@app.route('/health')
async def health():
    try:
        return jsonify({'status': 'healthy', 'service': 'devstral-chat'})
    except Exception as e:
        print(f"❌ Health check error: {e}")
        return jsonify({'status': 'error', 'error': str(e)}), 500

# Routes
@app.route('/')
async def index():
    try:
        if await current_user.is_authenticated:
            return redirect(url_for('chat.chat'))
        return redirect(url_for('auth.login'))
    except Exception as e:
        print(f"❌ Index route error: {e}")
        return f"Error: {e}", 500

# Error handlers
@app.errorhandler(500)
async def internal_error(error):
    print(f"❌ Internal server error: {error}")
    return jsonify({'error': 'Internal server error', 'details': str(error)}), 500

@app.errorhandler(404)
async def not_found(error):
    return jsonify({'error': 'Not found'}), 404

print("✅ Quart app configuration complete")

if __name__ == '__main__':
    print("🚀 Starting Quart app...")
    app.run(debug=True, host='0.0.0.0', port=8000)