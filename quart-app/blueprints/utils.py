# utils.py - Enhanced Security Utilities
import html
import secrets
import re
from quart import session

# XSS Protection Helpers
def sanitize_html(text):
    """Sanitize HTML to prevent XSS attacks (for form inputs)"""
    if text is None:
        return None
    # HTML escape special characters
    return html.escape(str(text).strip())

def escape_html(text):
    """Escape HTML for safe display (preserves formatting)"""
    if text is None:
        return ""
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

def clean_filename(filename):
    """Clean filename for safe file operations"""
    if not filename:
        return ""
    # Remove dangerous characters
    clean = re.sub(r'[^a-zA-Z0-9._-]', '', filename)
    return clean[:255]  # Limit length

def validate_input_length(text, max_length=10000):
    """Validate input length to prevent DoS"""
    if not text:
        return True
    return len(str(text)) <= max_length

# CSRF Token Management
async def generate_csrf_token():
    """Generate a new CSRF token"""
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_hex(32)  # Longer token
    return session['csrf_token']

async def validate_csrf_token(token):
    """Validate CSRF token with timing attack protection"""
    if not token or 'csrf_token' not in session:
        return False
    return secrets.compare_digest(session['csrf_token'], token)

# Input Validation
def validate_username(username):
    """Validate username format"""
    if not username:
        return False, "Username is required"
    if len(username) < 3:
        return False, "Username must be at least 3 characters"
    if len(username) > 50:
        return False, "Username too long"
    if not re.match(r'^[a-zA-Z0-9_-]+$', username):
        return False, "Username can only contain letters, numbers, underscore and dash"
    return True, ""

def validate_password(password):
    """Validate password strength"""
    if not password:
        return False, "Password is required"
    if len(password) < 6:
        return False, "Password must be at least 6 characters"
    if len(password) > 128:
        return False, "Password too long"
    return True, ""

def validate_message(message):
    """Validate chat message"""
    if not message:
        return False, "Message cannot be empty"
    if len(message) > 10000:
        return False, "Message too long (max 10,000 characters)"
    return True, ""