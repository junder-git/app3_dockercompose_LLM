# quart-app/app.py - FIXED version with proper routing and auth
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

print("🔍 Starting Quart app initialization - FIXED version...")

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
    from blueprints.utils import generate_csrf_token
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

# Enhanced markdown filter
def markdown_filter(text):
    """Convert markdown text to HTML with enhanced features"""
    if not text:
        return ""
    
    md = markdown.Markdown(
        extensions=[
            'codehilite', 'fenced_code', 'tables', 'nl2br', 'toc',
            'attr_list', 'def_list', 'abbr', 'footnotes', 'md_in_html',
            'pymdownx.superfences', 'pymdownx.highlight', 'pymdownx.inlinehilite',
            'pymdownx.tasklist', 'pymdownx.tilde', 'pymdownx.caret',
            'pymdownx.mark', 'pymdownx.keys', 'pymdownx.smartsymbols'
        ],
        extension_configs={
            'codehilite': {
                'css_class': 'highlight', 'use_pygments': True, 'noclasses': True,
                'linenos': True, 'linenostart': 1, 'linenostep': 1,
                'linenospecial': 0, 'nobackground': False
            },
            'pymdownx.highlight': {
                'css_class': 'highlight', 'use_pygments': True,
                'pygments_style': 'github-dark', 'noclasses': True,
                'linenums': True, 'linenums_style': 'pymdownx-inline'
            },
            'pymdownx.superfences': {
                'custom_fences': [{
                    'name': 'mermaid', 'class': 'mermaid',
                    'format': lambda source, language, css_class, options, md, **kwargs: f'<div class="{css_class}">{source}</div>'
                }]
            },
            'pymdownx.tasklist': {'custom_checkbox': True, 'clickable_checkbox': False},
            'toc': {'permalink': True, 'permalink_class': 'toc-permalink', 'permalink_title': 'Link to this section'}
        }
    )
    
    return Markup(md.convert(text))

# Initialize Quart app
app = Quart(__name__)
app.jinja_env.filters['markdown'] = markdown_filter

# Configure Quart
app.config['SECRET_KEY'] = SECRET_KEY
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=SESSION_LIFETIME_DAYS)
app.config['QUART_AUTH_COOKIE_SECURE'] = SECURE_COOKIES
app.config['QUART_AUTH_COOKIE_HTTPONLY'] = True
app.config['QUART_AUTH_COOKIE_SAMESITE'] = 'Lax'

# Initialize extensions
auth = QuartAuth(app)
print("✅ QuartAuth initialized")

# Register blueprints
app.register_blueprint(auth_bp)
app.register_blueprint(chat_bp)
app.register_blueprint(admin_bp)
print("✅ Blueprints registered")

# Minimal middleware
@app.before_request
async def make_session_permanent():
    """Make sessions permanent"""
    session.permanent = True

# Template globals
@app.context_processor
async def inject_template_globals():
    """Inject global variables into all templates"""
    try:
        csrf_token = await generate_csrf_token()
        current_user_data = None
        
        if await current_user.is_authenticated:
            try:
                current_user_data = await get_current_user_data(current_user.auth_id)
            except Exception as e:
                print(f"⚠️ Error loading user data: {e}")
        
        return {
            'csrf_token': csrf_token,
            'current_user_data': current_user_data
        }
    except Exception as e:
        print(f"⚠️ Error injecting template globals: {e}")
        return {'csrf_token': '', 'current_user_data': None}

# Initialize admin user
async def init_admin():
    """Create default admin user if not exists"""
    try:
        print("🔧 Initializing admin user...")
        admin = await get_user_by_username(ADMIN_USERNAME)
        if not admin:
            admin_user = User(
                user_id=ADMIN_USER_ID, username=ADMIN_USERNAME,
                password_hash=generate_password_hash(ADMIN_PASSWORD),
                is_admin=True, is_approved=True
            )
            await save_user(admin_user)
            print(f"✅ Created admin user: {ADMIN_USERNAME}")
        else:
            if not admin.is_admin or not admin.is_approved:
                admin.is_admin = True
                admin.is_approved = True
                await save_user(admin)
                print(f"✅ Fixed admin status: {ADMIN_USERNAME}")
            else:
                print(f"✅ Admin user exists: {ADMIN_USERNAME}")
    except Exception as e:
        print(f"❌ Error initializing admin: {e}")

@app.before_serving
async def startup():
    await init_admin()

# Health check
@app.route('/health')
async def health():
    return jsonify({'status': 'healthy', 'service': 'devstral-chat'})

# FIXED: Root route with proper logic
@app.route('/')
async def index():
    """Root route - redirect to appropriate page"""
    print(f"🔗 Root route accessed")
    
    try:
        # Check if user is authenticated
        is_authenticated = await current_user.is_authenticated
        print(f"🔗 User authenticated: {is_authenticated}")
        
        if is_authenticated:
            # User is logged in, redirect to chat
            print(f"🔗 Redirecting authenticated user to chat")
            return redirect(url_for('chat.chat'))
        else:
            # User not logged in, redirect to login
            print(f"🔗 Redirecting unauthenticated user to login")
            return redirect(url_for('auth.login'))
            
    except Exception as e:
        print(f"❌ Error in root route: {e}")
        # Fallback to login on any error
        return redirect(url_for('auth.login'))

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8000)