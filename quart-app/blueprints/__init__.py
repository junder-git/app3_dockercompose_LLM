# blueprints/__init__.py - COMPLETELY FIXED
print("🔍 Loading blueprints...")

try:
    from .auth import auth_bp
    print("✅ Auth blueprint imported")
except Exception as e:
    print(f"❌ Auth blueprint import failed: {e}")
    auth_bp = None

try:
    from .chat import chat_bp
    print("✅ Chat blueprint imported")
except Exception as e:
    print(f"❌ Chat blueprint import failed: {e}")
    chat_bp = None

try:
    from .admin import admin_bp
    print("✅ Admin blueprint imported")
except Exception as e:
    print(f"❌ Admin blueprint import failed: {e}")
    admin_bp = None

# Only export successfully imported blueprints
__all__ = []
if auth_bp:
    __all__.append('auth_bp')
if chat_bp:
    __all__.append('chat_bp')
if admin_bp:
    __all__.append('admin_bp')

print(f"✅ Blueprints loaded: {__all__}")