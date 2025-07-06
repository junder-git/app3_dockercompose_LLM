# blueprints/__init__.py
from .auth import auth_bp
from .chat import chat_bp
from .admin import admin_bp

__all__ = []
if auth_bp:
    __all__.append('auth_bp')
if chat_bp:
    __all__.append('chat_bp')
if admin_bp:
    __all__.append('admin_bp')

print(f"✅ Blueprints loaded: {__all__}")