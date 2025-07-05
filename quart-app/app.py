# quart-app/app.py - Enhanced security with strict rate limiting
import os
import sys
import secrets
import asyncio
import markdown
from datetime import timedelta
from dotenv import load_dotenv
from markupsafe import Markup
from markdown.extensions import codehilite, fenced_code, tables, toc
from pymdownx import superfences, highlight

print("🔍 Starting Quart app initialization with enhanced security...")

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
    from blueprints.auth_middleware import enforce_endpoint_access, add_security_context
    print("✅ Blueprint imports successful")
except Exception as e:
    print(f"❌ Blueprint import failed: {e}")
    sys.exit(1)

# Load environment variables
load_dotenv()
print("✅ Environment loaded")

# Get all configuration from environment
SESSION_LIFETIME_DAYS = int(os.environ['SESSION_LIFETIME_DAYS'])
SECURE_COOKIES = os.environ['SECURE_COOKIES'].lower() == 'true'
ADMIN_USERNAME = os.environ['ADMIN_USERNAME']
ADMIN_PASSWORD = os.environ['ADMIN_PASSWORD']
ADMIN_USER_ID = os.environ['ADMIN_USER_ID']
SECRET_KEY = os.environ['SECRET_KEY']

# Enhanced markdown filter with better code block support
def markdown_filter(text):
    """Convert markdown text to HTML with enhanced features"""
    if not text:
        return ""
    
    # Configure markdown with comprehensive extensions
    md = markdown.Markdown(
        extensions=[
            'codehilite',
            'fenced_code',
            'tables',
            'nl2br',
            'toc',
            'attr_list',
            'def_list',
            'abbr',
            'footnotes',
            'md_in_html',
            'pymdownx.superfences',
            'pymdownx.highlight',
            'pymdownx.inlinehilite',
            'pymdownx.tasklist',
            'pymdownx.tilde',
            'pymdownx.caret',
            'pymdownx.mark',
            'pymdownx.keys',
            'pymdownx.smartsymbols'
        ],
        extension_configs={
            'codehilite': {
                'css_class': 'highlight',
                'use_pygments': True,
                'noclasses': True,
                'linenos': True,
                'linenostart': 1,
                'linenostep': 1,
                'linenospecial': 0,
                'nobackground': False
            },
            'pymdownx.highlight': {
                'css_class': 'highlight',
                'use_pygments': True,
                'pygments_style': 'github-dark',
                'noclasses': True,
                'linenums': True,
                'linenums_style': 'pymdownx-inline'
            },
            'pymdownx.superfences': {
                'custom_fences': [
                    {
                        'name': 'mermaid',
                        'class': 'mermaid',
                        'format': lambda source, language, css_class, options, md, **kwargs: f'<div class="{css_class}">{source}</div>'
                    }
                ]
            },
            'pymdownx.tasklist': {
                'custom_checkbox': True,
                'clickable_checkbox': False
            },
            'toc': {
                'permalink': True,
                'permalink_class': 'toc-permalink',
                'permalink_title': 'Link to this section'
            }
        }
    )
    
    # Convert markdown to HTML
    html = md.convert(text)
    
    # Return as safe HTML (won't be escaped)
    return Markup(html)

# Initialize Quart app
app = Quart(__name__)

# Register the enhanced markdown filter
app.jinja_env.filters['markdown'] = markdown_filter

print("✅ Quart app created with enhanced markdown support")

# Configure Quart - ALL from environment
app.config['SECRET_KEY'] = SECRET_KEY
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=SESSION_LIFETIME_DAYS)

# Configure auth - ALL from environment
app.config['QUART_AUTH_COOKIE_SECURE'] = SECURE_COOKIES
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

# Enhanced access control middleware
@app.before_request
async def enhanced_access_control():
    """Enhanced access control and rate limiting context"""
    # Add security context first
    await add_security_context()
    
    # Enforce endpoint access controls
    response = await enforce_endpoint_access()
    if response:
        return response

# Load user data for templates
@app.before_request
async def load_user_data():
    """Load current user data for template context"""
    g.current_user_data = None
    try:
        if await current_user.is_authenticated:
            user_data = await get_current_user_data(current_user.auth_id)
            # Check if user is approved (or admin)
            if user_data and (user_data.is_admin or user_data.is_approved):
                g.current_user_data = user_data
            else:
                # User not approved, clear session
                session.clear()
                g.current_user_data = None
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

# Enhanced Security Headers Middleware
@app.after_request
async def add_security_headers(response):
    """Add enhanced security headers to all responses"""
    try:
        # Basic security headers
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['X-XSS-Protection'] = '1; mode=block'
        response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
        response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'
        
        # Enhanced CSP
        response.headers['Content-Security-Policy'] = (
            "default-src 'self'; "
            "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
            "font-src 'self' https://cdn.jsdelivr.net; "
            "img-src 'self' data:; "
            "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
            "connect-src 'self'"
        )
        
        # Add rate limiting headers based on endpoint type
        if hasattr(g, 'endpoint_limits'):
            limits = g.endpoint_limits
            response.headers['X-RateLimit-Limit'] = str(limits['rate'])
            response.headers['X-RateLimit-Burst'] = str(limits['burst'])
            if hasattr(g, 'is_unlimited_endpoint') and g.is_unlimited_endpoint:
                response.headers['X-RateLimit-Type'] = 'unlimited'
            else:
                response.headers['X-RateLimit-Type'] = 'strict'
        
        # Add CSRF token to HTML responses
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
            'current_user_data': g.get('current_user_data'),
            'is_unlimited_endpoint': g.get('is_unlimited_endpoint', False),
            'is_strict_endpoint': g.get('is_strict_endpoint', True)
        }
    except Exception as e:
        print(f"⚠️ Error injecting template globals: {e}")
        return {
            'csrf_token': '',
            'current_user_data': None,
            'is_unlimited_endpoint': False,
            'is_strict_endpoint': True
        }

# Initialize admin user
async def init_admin():
    """Create default admin user if not exists"""
    try:
        print("🔧 Initializing admin user...")
        
        admin = await get_user_by_username(ADMIN_USERNAME)
        if not admin:
            admin_user = User(
                user_id=ADMIN_USER_ID,  # Use environment variable
                username=ADMIN_USERNAME,
                password_hash=generate_password_hash(ADMIN_PASSWORD),
                is_admin=True,
                is_approved=True  # Admin is always approved
            )
            await save_user(admin_user)
            print(f"✅ Created default admin user: {ADMIN_USERNAME}")
        else:
            # Ensure existing admin has correct admin status and approval
            if not admin.is_admin or not admin.is_approved:
                admin.is_admin = True
                admin.is_approved = True
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

@app.errorhandler(403)
async def forbidden(error):
    return jsonify({'error': 'Forbidden - Access denied'}), 403

@app.errorhandler(401)
async def unauthorized(error):
    return jsonify({'error': 'Unauthorized - Authentication required'}), 401

@app.errorhandler(429)
async def rate_limited(error):
    return jsonify({'error': 'Rate limit exceeded - Please slow down'}), 429

print("✅ Quart app configuration complete with enhanced security")
print("📝 Configuration loaded from environment:")
print(f"  - Admin Username: {ADMIN_USERNAME}")
print(f"  - Admin User ID: {ADMIN_USER_ID}")
print(f"  - Session Lifetime: {SESSION_LIFETIME_DAYS} days")
print(f"  - Secure Cookies: {SECURE_COOKIES}")
print("🔒 Security features enabled:")
print("  - Strict rate limiting for auth endpoints")
print("  - Unlimited rate limiting for chat/admin (authenticated users only)")
print("  - Enhanced access control middleware")
print("  - CSRF protection for state-changing requests")
print("  - Comprehensive security headers")
print("📝 Markdown features enabled:")
print("  - Syntax highlighting with line numbers")
print("  - Tables, task lists, and footnotes")
print("  - Table of contents generation")
print("  - Enhanced code blocks with language detection")
print("  - GitHub-style markdown extensions")

if __name__ == '__main__':
    print("🚀 Starting Quart app with enhanced security...")
    app.run(debug=True, host='0.0.0.0', port=8000)