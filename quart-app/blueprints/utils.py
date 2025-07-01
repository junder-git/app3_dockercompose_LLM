# utils.py
import html
import secrets
from quart import session

# XSS Protection Helper
def sanitize_html(text):
    """Sanitize HTML to prevent XSS attacks"""
    if text is None:
        return None
    # HTML escape special characters
    return html.escape(str(text))

def sanitize_dict(data):
    """Recursively sanitize all string values in a dictionary"""
    if isinstance(data, dict):
        return {k: sanitize_dict(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_dict(item) for item in data]
    elif isinstance(data, str):
        return sanitize_html(data)
    else:
        return data

# CSRF Token Management
async def generate_csrf_token():
    """Generate a new CSRF token"""
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_hex(16)
    return session['csrf_token']

async def validate_csrf_token(token):
    """Validate CSRF token"""
    return token and 'csrf_token' in session and secrets.compare_digest(session['csrf_token'], token)