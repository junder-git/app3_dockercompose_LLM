# quart-app/app.py - FIXED version with proper routing and auth
import os
import markdown
from datetime import timedelta
from dotenv import load_dotenv
from markupsafe import Markup
from quart import Quart, redirect, url_for, session
from quart_auth import QuartAuth, current_user
from werkzeug.security import generate_password_hash
from blueprints import auth_bp, chat_bp, admin_bp
from blueprints.database import get_user_by_username, save_user, get_current_user_data
from blueprints.models import User
from blueprints.utils import generate_csrf_token

# Load environment variables
load_dotenv()

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

# Register blueprints
app.register_blueprint(auth_bp)
app.register_blueprint(chat_bp)
app.register_blueprint(admin_bp)

# Template globals
@app.context_processor
async def inject_template_globals():
    """Inject global variables into all templates"""
    csrf_token = await generate_csrf_token()
    current_user_data = None
    if await current_user.is_authenticated:
        current_user_data = await get_current_user_data(current_user.auth_id)       
    return {
        'csrf_token': csrf_token,
        'current_user_data': current_user_data
    }

# Initialize admin user
async def init_admin():
    """Create default admin user if not exists"""
    admin_user = await get_user_by_username(ADMIN_USERNAME)
    if not admin_user:
        admin_user = User(
            user_id=ADMIN_USER_ID, username=ADMIN_USERNAME,
            password_hash=generate_password_hash(ADMIN_PASSWORD),
            is_admin=True, is_approved=True
        )
        await save_user(admin_user)


@app.before_serving
async def startup():
    await init_admin()

# FIXED: Root route with proper logic
@app.route('/')
async def index():
    """Root route - redirect to appropriate page"""
    # Check if user is authenticated
    is_authenticated = await current_user.is_authenticated    
    if is_authenticated:
        # User is logged in, redirect to chat
        return redirect(url_for('chat.chat'))
    else:
        # User not logged in, redirect to login
        return redirect(url_for('auth.login'))

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8000)