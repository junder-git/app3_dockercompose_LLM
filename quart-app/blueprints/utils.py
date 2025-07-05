# utils.py - Environment-driven Security Utilities
import html
import secrets
import re
import os
from quart import session

# Get validation settings from environment
MIN_USERNAME_LENGTH = int(os.environ['MIN_USERNAME_LENGTH'])
MAX_USERNAME_LENGTH = int(os.environ['MAX_USERNAME_LENGTH'])
MIN_PASSWORD_LENGTH = int(os.environ['MIN_PASSWORD_LENGTH'])
MAX_PASSWORD_LENGTH = int(os.environ['MAX_PASSWORD_LENGTH'])
MAX_MESSAGE_LENGTH = int(os.environ['MAX_MESSAGE_LENGTH'])
MAX_FILENAME_LENGTH = int(os.environ['MAX_FILENAME_LENGTH'])
CSRF_TOKEN_LENGTH = int(os.environ['CSRF_TOKEN_LENGTH'])

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
    return clean[:MAX_FILENAME_LENGTH]  # Limit length from environment

def validate_input_length(text, max_length=None):
    """Validate input length to prevent DoS"""
    if max_length is None:
        max_length = MAX_MESSAGE_LENGTH
    if not text:
        return True
    return len(str(text)) <= max_length

# CSRF Token Management
async def generate_csrf_token():
    """Generate a new CSRF token"""
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_hex(CSRF_TOKEN_LENGTH)  # Length from environment
    return session['csrf_token']

async def validate_csrf_token(token):
    """Validate CSRF token with timing attack protection"""
    if not token or 'csrf_token' not in session:
        return False
    return secrets.compare_digest(session['csrf_token'], token)

# Input Validation
def validate_username(username):
    """Validate username format using environment variables"""
    if not username:
        return False, "Username is required"
    if len(username) < MIN_USERNAME_LENGTH:
        return False, f"Username must be at least {MIN_USERNAME_LENGTH} characters"
    if len(username) > MAX_USERNAME_LENGTH:
        return False, f"Username must be no more than {MAX_USERNAME_LENGTH} characters"
    if not re.match(r'^[a-zA-Z0-9_-]+$', username):
        return False, "Username can only contain letters, numbers, underscore and dash"
    return True, ""

def validate_password(password):
    """Validate password strength using environment variables"""
    if not password:
        return False, "Password is required"
    if len(password) < MIN_PASSWORD_LENGTH:
        return False, f"Password must be at least {MIN_PASSWORD_LENGTH} characters"
    if len(password) > MAX_PASSWORD_LENGTH:
        return False, f"Password must be no more than {MAX_PASSWORD_LENGTH} characters"
    return True, ""

def validate_message(message):
    """Validate chat message using environment variables"""
    if not message:
        return False, "Message cannot be empty"
    if len(message) > MAX_MESSAGE_LENGTH:
        return False, f"Message too long (max {MAX_MESSAGE_LENGTH:,} characters)"
    return True, ""