import os
import json
import asyncio
import aiohttp
import html
import hashlib
import secrets
from datetime import datetime, timedelta
from functools import wraps
from typing import Optional, Dict, Any, List
from dotenv import load_dotenv

from quart import Quart, render_template, request, jsonify, websocket, redirect, url_for, session, make_response
from quart_auth import AuthUser, QuartAuth, login_user, logout_user, login_required, current_user
import redis.asyncio as redis
from werkzeug.security import generate_password_hash, check_password_hash

# Load environment variables
load_dotenv()

# Redis configuration
REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
CHAT_CACHE_TTL = int(os.environ.get('CHAT_CACHE_TTL_SECONDS', '3600'))  # 1 hour cache for AI responses
USER_DATA_TTL = 0  # No expiry for user data
CHAT_HISTORY_TTL = 0  # No expiry for chat history
RATE_LIMIT_WINDOW = 60  # 1 minute
RATE_LIMIT_MAX = int(os.environ.get('RATE_LIMIT_MESSAGES_PER_MINUTE', '10'))  # messages per minute
MAX_CHATS_PER_USER = 5  # Maximum number of chat sessions per user

# AI Model configuration
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
OLLAMA_MODEL = os.environ.get('OLLAMA_MODEL', 'deepseek-coder-v2:16b')
MODEL_TEMPERATURE = float(os.environ.get('MODEL_TEMPERATURE', '0.7'))
MODEL_TOP_P = float(os.environ.get('MODEL_TOP_P', '0.9'))
MODEL_MAX_TOKENS = int(os.environ.get('MODEL_MAX_TOKENS', '2048'))
MODEL_TIMEOUT = int(os.environ.get('MODEL_TIMEOUT', '300'))

# Admin credentials from environment
ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin123')

# Initialize Quart app
app = Quart(__name__)

# Configure Quart 0.20.0 built-in sessions
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=int(os.environ.get('SESSION_LIFETIME_DAYS', '7')))

# Configure auth
app.config['QUART_AUTH_COOKIE_SECURE'] = os.environ.get('SECURE_COOKIES', 'false').lower() == 'true'
app.config['QUART_AUTH_COOKIE_HTTPONLY'] = True
app.config['QUART_AUTH_COOKIE_SAMESITE'] = 'Lax'

# Initialize extensions
auth = QuartAuth(app)

# Make sessions permanent by default
@app.before_request
async def make_session_permanent():
    """Make sessions permanent (persist across browser sessions)"""
    session.permanent = True

# Database management functions (add to your app.py)
async def get_database_stats():
    """Get comprehensive database statistics"""
    r = await get_redis()
    stats = {}
    
    try:
        # Get all keys
        all_keys = await r.keys("*")
        stats['total_keys'] = len(all_keys)
        
        # Group keys by type
        key_types = {}
        for key in all_keys:
            key_type = key.split(':')[0] if ':' in key else key
            key_types[key_type] = key_types.get(key_type, 0) + 1
        
        stats['key_types'] = key_types
        
        # Get user statistics
        user_ids = await r.smembers("users")
        users_data = []
        
        for user_id in user_ids:
            user_data = await r.hgetall(f"user:{user_id}")
            if user_data:
                # Get session count for this user
                session_count = len(await r.zrange(f"user_sessions:{user_id}", 0, -1))
                
                # Get total message count
                total_messages = 0
                session_ids = await r.zrange(f"user_sessions:{user_id}", 0, -1)
                for session_id in session_ids:
                    message_count = await r.zcard(f"session_messages:{session_id}")
                    total_messages += message_count
                
                users_data.append({
                    'id': user_id,
                    'username': user_data.get('username'),
                    'is_admin': user_data.get('is_admin') == 'true',
                    'created_at': user_data.get('created_at'),
                    'session_count': session_count,
                    'message_count': total_messages
                })
        
        stats['users'] = users_data
        stats['user_count'] = len(users_data)
        
        # Get next user ID
        stats['next_user_id'] = await r.get("user_id_counter") or "Not set"
        
        # Memory usage (if available)
        try:
            info = await r.info('memory')
            stats['memory_usage'] = {
                'used_memory': info.get('used_memory_human'),
                'used_memory_peak': info.get('used_memory_peak_human'),
                'used_memory_dataset': info.get('used_memory_dataset')
            }
        except:
            stats['memory_usage'] = None
        
        return stats
        
    except Exception as e:
        app.logger.error(f"Error getting database stats: {e}")
        return {'error': str(e)}

async def cleanup_database(cleanup_type: str, admin_user_id: str):
    """Perform database cleanup operations"""
    r = await get_redis()
    result = {'success': False, 'message': '', 'stats': {}}
    
    try:
        # Log the cleanup attempt
        app.logger.warning(f"Database cleanup initiated by admin user {admin_user_id}, type: {cleanup_type}")
        
        if cleanup_type == "complete_reset":
            # Get stats before cleanup
            before_stats = await get_database_stats()
            
            # Complete database flush
            await r.flushdb()
            result['message'] = "Complete database reset performed"
            
            # Recreate admin user
            await recreate_admin_user()
            
        elif cleanup_type == "fix_users":
            # Delete user-related keys only
            user_keys = await r.keys("user:*")
            username_keys = await r.keys("username:*")
            
            deleted_count = 0
            if user_keys:
                await r.delete(*user_keys)
                deleted_count += len(user_keys)
            if username_keys:
                await r.delete(*username_keys)
                deleted_count += len(username_keys)
            
            await r.delete("users")
            await r.delete("user_id_counter")
            deleted_count += 2
            
            # Recreate admin user
            await recreate_admin_user()
            
            result['message'] = f"User data cleanup completed. {deleted_count} keys deleted."
            
        elif cleanup_type == "recreate_admin":
            # Just recreate admin user
            existing_admin_id = await r.get(f"username:{ADMIN_USERNAME}")
            if existing_admin_id and existing_admin_id != 'admin':
                # Remove old admin
                await r.delete(f"user:{existing_admin_id}")
                await r.srem("users", existing_admin_id)
            
            await recreate_admin_user()
            result['message'] = "Admin user recreated successfully"
            
        elif cleanup_type == "clear_cache":
            # Clear only AI response cache
            cache_keys = await r.keys("ai_response:*")
            rate_limit_keys = await r.keys("rate_limit:*")
            
            deleted_count = 0
            if cache_keys:
                await r.delete(*cache_keys)
                deleted_count += len(cache_keys)
            if rate_limit_keys:
                await r.delete(*rate_limit_keys)
                deleted_count += len(rate_limit_keys)
            
            result['message'] = f"Cache cleared. {deleted_count} cache keys deleted."
            
        elif cleanup_type == "fix_sessions":
            # Fix orphaned sessions and messages
            all_session_keys = await r.keys("session:*")
            all_message_keys = await r.keys("session_messages:*")
            
            # Get valid user IDs
            valid_users = await r.smembers("users")
            
            deleted_sessions = 0
            for session_key in all_session_keys:
                session_data = await r.hgetall(session_key)
                if session_data:
                    user_id = session_data.get('user_id')
                    if user_id not in valid_users:
                        # Delete orphaned session
                        session_id = session_key.split(':')[1]
                        await r.delete(session_key)
                        await r.delete(f"session_messages:{session_id}")
                        
                        # Delete associated messages
                        message_ids = await r.zrange(f"session_messages:{session_id}", 0, -1)
                        for msg_id in message_ids:
                            await r.delete(f"message:{msg_id}")
                        
                        deleted_sessions += 1
            
            result['message'] = f"Session cleanup completed. {deleted_sessions} orphaned sessions removed."
        
        else:
            result['message'] = "Invalid cleanup type"
            return result
        
        # Get updated stats
        result['stats'] = await get_database_stats()
        result['success'] = True
        result['timestamp'] = datetime.utcnow().isoformat()
        
        # Log successful cleanup
        app.logger.info(f"Database cleanup completed successfully: {cleanup_type}")
        
    except Exception as e:
        result['message'] = f"Cleanup failed: {str(e)}"
        app.logger.error(f"Database cleanup failed: {e}")
    
    return result

async def recreate_admin_user():
    """Helper function to recreate admin user with proper settings"""
    r = await get_redis()
    
    admin_data = {
        'id': 'admin',
        'username': ADMIN_USERNAME,
        'password_hash': generate_password_hash(ADMIN_PASSWORD),
        'is_admin': 'true',
        'created_at': datetime.utcnow().isoformat()
    }
    
    # Save admin user
    await r.hset("user:admin", mapping=admin_data)
    await r.set(f"username:{ADMIN_USERNAME}", "admin")
    await r.sadd("users", "admin")
    
    # Set user ID counter for regular users
    await r.set("user_id_counter", "1000")

# API endpoints for admin database management (add these to your routes)

@app.route('/api/admin/database/stats')
@admin_required
async def get_admin_database_stats():
    """Get database statistics for admin panel"""
    stats = await get_database_stats()
    return jsonify(stats)

@app.route('/api/admin/database/cleanup', methods=['POST'])
@admin_required
async def admin_database_cleanup():
    """Perform database cleanup operations"""
    data = await request.get_json()
    cleanup_type = data.get('type')
    
    if not cleanup_type:
        return jsonify({'error': 'Cleanup type is required'}), 400
    
    valid_types = ['complete_reset', 'fix_users', 'recreate_admin', 'clear_cache', 'fix_sessions']
    if cleanup_type not in valid_types:
        return jsonify({'error': 'Invalid cleanup type'}), 400
    
    # Perform cleanup
    result = await cleanup_database(cleanup_type, current_user.auth_id)
    
    if result['success']:
        return jsonify(result)
    else:
        return jsonify(result), 500

@app.route('/api/admin/database/backup')
@admin_required
async def create_database_backup():
    """Create a simple database backup (key dump)"""
    try:
        r = await get_redis()
        
        # Get all keys and their data
        all_keys = await r.keys("*")
        backup_data = {}
        
        for key in all_keys:
            key_type = await r.type(key)
            
            if key_type == 'string':
                backup_data[key] = {
                    'type': 'string',
                    'value': await r.get(key)
                }
            elif key_type == 'hash':
                backup_data[key] = {
                    'type': 'hash',
                    'value': await r.hgetall(key)
                }
            elif key_type == 'set':
                backup_data[key] = {
                    'type': 'set',
                    'value': list(await r.smembers(key))
                }
            elif key_type == 'zset':
                backup_data[key] = {
                    'type': 'zset',
                    'value': await r.zrange(key, 0, -1, withscores=True)
                }
        
        backup = {
            'timestamp': datetime.utcnow().isoformat(),
            'total_keys': len(all_keys),
            'data': backup_data
        }
        
        return jsonify(backup)
        
    except Exception as e:
        app.logger.error(f"Backup creation failed: {e}")
        return jsonify({'error': str(e)}), 500
    
# Redis connection pool
class RedisPool:
    _instance = None
    _pool = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(RedisPool, cls).__new__(cls)
        return cls._instance
    
    async def get_pool(self):
        if self._pool is None:
            self._pool = redis.ConnectionPool.from_url(
                REDIS_URL,
                max_connections=50,
                decode_responses=True,
                socket_keepalive=True,
                retry_on_timeout=True,
            )
        return self._pool
    
    async def get_client(self):
        pool = await self.get_pool()
        return redis.Redis(connection_pool=pool)

redis_pool = RedisPool()

# User model - separate from AuthUser for Quart-Auth 0.11.0
class User:
    def __init__(self, user_id=None, username=None, password_hash=None, is_admin=False, created_at=None):
        self.id = str(user_id) if user_id else None
        self.username = username
        self.password_hash = password_hash
        self.is_admin = is_admin
        self.created_at = created_at or datetime.utcnow().isoformat()
    
    def to_dict(self):
        return {
            'id': str(self.id),
            'username': str(self.username),
            'password_hash': str(self.password_hash),
            'is_admin': str(self.is_admin).lower(),  # Convert boolean to string
            'created_at': str(self.created_at)
        }
    
    @classmethod
    def from_dict(cls, data):
        return cls(
            user_id=data.get('id'),
            username=data.get('username'),
            password_hash=data.get('password_hash'),
            is_admin=data.get('is_admin', 'false').lower() == 'true',  # Convert string back to boolean
            created_at=data.get('created_at')
        )

# Chat Session model
class ChatSession:
    def __init__(self, session_id=None, user_id=None, title=None, created_at=None, updated_at=None):
        self.id = session_id or f"{user_id}_{datetime.utcnow().timestamp()}"
        self.user_id = str(user_id)
        self.title = title or f"Chat {datetime.utcnow().strftime('%Y-%m-%d %H:%M')}"
        self.created_at = created_at or datetime.utcnow().isoformat()
        self.updated_at = updated_at or datetime.utcnow().isoformat()
    
    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'title': self.title,
            'created_at': self.created_at,
            'updated_at': self.updated_at
        }
    
    @classmethod
    def from_dict(cls, data):
        return cls(
            session_id=data.get('id'),
            user_id=data.get('user_id'),
            title=data.get('title'),
            created_at=data.get('created_at'),
            updated_at=data.get('updated_at')
        )

# Helper function to get current user data
async def get_current_user_data():
    """Get current user data from Redis using current_user.auth_id"""
    if await current_user.is_authenticated:
        return await get_user_by_id(current_user.auth_id)
    return None

# CSRF Token Management using Quart's built-in sessions
async def generate_csrf_token():
    """Generate a new CSRF token"""
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_hex(16)
    return session['csrf_token']

async def validate_csrf_token(token):
    """Validate CSRF token"""
    return token and 'csrf_token' in session and secrets.compare_digest(session['csrf_token'], token)

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

# Security Headers Middleware
@app.after_request
async def add_security_headers(response):
    """Add security headers to all responses"""
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'
    
    # Add CSRF token to all HTML responses
    if response.content_type and 'text/html' in response.content_type:
        response.headers['X-CSRF-Token'] = await generate_csrf_token()
    
    return response

# CSRF Protection for POST requests
@app.before_request
async def csrf_protect():
    """Validate CSRF token for state-changing requests"""
    if request.method in ['POST', 'PUT', 'DELETE', 'PATCH']:
        # Skip CSRF for WebSocket and API endpoints that use different auth
        if request.path.startswith('/ws') or request.path.startswith('/api/'):
            return
        
        token = (await request.form).get('csrf_token') or request.headers.get('X-CSRF-Token')
        if not await validate_csrf_token(token):
            return jsonify({'error': 'Invalid CSRF token'}), 403

# Template globals
@app.context_processor
async def inject_csrf_token():
    """Inject CSRF token into all templates"""
    return {'csrf_token': await generate_csrf_token()}

# Redis helper functions
async def get_redis():
    return await redis_pool.get_client()

async def get_next_user_id():
    """Get the next available user ID"""
    r = await get_redis()
    return await r.incr('user_id_counter')

async def save_user(user: User):
    """Save user to Redis with proper ID management"""
    r = await get_redis()
    
    # If user doesn't have an ID, generate one
    if not user.id:
        user.id = str(await get_next_user_id())
    
    user_data = user.to_dict()
    
    # Save user data
    await r.hset(f"user:{user.id}", mapping=user_data)
    
    # Add to username index for lookup
    await r.set(f"username:{user.username}", user.id)
    
    # Add to users set
    await r.sadd("users", user.id)
    
    app.logger.info(f"Saved user: {user.username} with ID: {user.id}, is_admin: {user.is_admin}")

async def get_user_by_id(user_id: str) -> Optional[User]:
    """Get user by ID from Redis"""
    r = await get_redis()
    user_data = await r.hgetall(f"user:{user_id}")
    
    if user_data:
        return User.from_dict(user_data)
    return None

async def get_user_by_username(username: str) -> Optional[User]:
    """Get user by username from Redis"""
    r = await get_redis()
    user_id = await r.get(f"username:{username}")
    
    if user_id:
        return await get_user_by_id(user_id)
    return None

async def get_all_users() -> List[User]:
    """Get all users from Redis"""
    r = await get_redis()
    user_ids = await r.smembers("users")
    
    users = []
    for user_id in user_ids:
        user = await get_user_by_id(user_id)
        if user:
            users.append(user)
    
    return users

# Chat session management
async def create_chat_session(user_id: str, title: str = None) -> ChatSession:
    """Create a new chat session for a user"""
    r = await get_redis()
    
    # Check if user has reached max chat limit
    user_sessions = await r.zrange(f"user_sessions:{user_id}", 0, -1)
    if len(user_sessions) >= MAX_CHATS_PER_USER:
        # Remove oldest session
        oldest_session_id = user_sessions[0]
        await delete_chat_session(user_id, oldest_session_id)
    
    # Create new session
    session = ChatSession(user_id=user_id, title=title)
    
    # Save session data
    await r.hset(f"session:{session.id}", mapping=session.to_dict())
    
    # Add to user's session list (sorted by creation time)
    await r.zadd(f"user_sessions:{user_id}", {session.id: datetime.utcnow().timestamp()})
    
    return session

async def get_chat_session(session_id: str) -> Optional[ChatSession]:
    """Get chat session by ID"""
    r = await get_redis()
    session_data = await r.hgetall(f"session:{session_id}")
    
    if session_data:
        return ChatSession.from_dict(session_data)
    return None

async def get_user_chat_sessions(user_id: str) -> List[ChatSession]:
    """Get all chat sessions for a user"""
    r = await get_redis()
    session_ids = await r.zrevrange(f"user_sessions:{user_id}", 0, -1)
    
    sessions = []
    for session_id in session_ids:
        session = await get_chat_session(session_id)
        if session:
            sessions.append(session)
    
    return sessions

async def delete_chat_session(user_id: str, session_id: str):
    """Delete a chat session and all its messages"""
    r = await get_redis()
    
    # Delete all messages in this session
    message_ids = await r.zrange(f"session_messages:{session_id}", 0, -1)
    for msg_id in message_ids:
        await r.delete(f"message:{msg_id}")
    
    # Delete session messages list
    await r.delete(f"session_messages:{session_id}")
    
    # Delete session data
    await r.delete(f"session:{session_id}")
    
    # Remove from user's session list
    await r.zrem(f"user_sessions:{user_id}", session_id)

async def get_or_create_current_session(user_id: str) -> str:
    """Get current session ID or create a new one"""
    # Use session storage for current session tracking
    session_key = f"current_session_{user_id}"
    
    if session_key in session:
        session_id = session[session_key]
        # Verify session still exists
        if await get_chat_session(session_id):
            return session_id
    
    # Create new session
    chat_session = await create_chat_session(user_id)
    session[session_key] = chat_session.id
    return chat_session.id

async def save_message(user_id: str, role: str, content: str, session_id: str):
    """Save chat message to Redis with proper session isolation"""
    r = await get_redis()
    
    # Content is already sanitized when received
    message_id = f"{session_id}:{datetime.utcnow().timestamp()}:{secrets.token_hex(4)}"
    message_data = {
        'id': message_id,
        'user_id': user_id,
        'role': role,
        'content': content,  # Already sanitized
        'timestamp': datetime.utcnow().isoformat(),
        'session_id': session_id
    }
    
    # Save message data
    await r.hset(f"message:{message_id}", mapping=message_data)
    
    # Add to session's message list (sorted by timestamp)
    await r.zadd(f"session_messages:{session_id}", {message_id: datetime.utcnow().timestamp()})
    
    # Update session last activity
    session_obj = await get_chat_session(session_id)
    if session_obj:
        session_obj.updated_at = datetime.utcnow().isoformat()
        await r.hset(f"session:{session_id}", mapping=session_obj.to_dict())

async def get_session_messages(session_id: str, limit: int = None) -> List[Dict]:
    """Get messages for a specific chat session"""
    if limit is None:
        limit = int(os.environ.get('CHAT_HISTORY_LIMIT', '100'))
    
    r = await get_redis()
    
    # Get message IDs sorted by timestamp (newest first)
    message_ids = await r.zrevrange(f"session_messages:{session_id}", 0, limit - 1)
    
    messages = []
    for msg_id in message_ids:
        msg_data = await r.hgetall(f"message:{msg_id}")
        if msg_data:
            messages.append(msg_data)
    
    return messages[::-1]  # Reverse to get oldest first

async def get_user_messages(user_id: str, limit: int = None) -> List[Dict]:
    """Get ALL messages for a user across all sessions (for admin view)"""
    r = await get_redis()
    
    # Get all user sessions
    session_ids = await r.zrange(f"user_sessions:{user_id}", 0, -1)
    
    all_messages = []
    for session_id in session_ids:
        session_messages = await get_session_messages(session_id, limit)
        all_messages.extend(session_messages)
    
    # Sort all messages by timestamp
    all_messages.sort(key=lambda x: x.get('timestamp', ''))
    
    if limit:
        return all_messages[-limit:]  # Return most recent messages
    return all_messages

async def check_rate_limit(user_id: str) -> bool:
    """Check if user has exceeded rate limit"""
    r = await get_redis()
    key = f"rate_limit:{user_id}"
    
    current = await r.incr(key)
    if current == 1:
        await r.expire(key, RATE_LIMIT_WINDOW)
    
    return current <= RATE_LIMIT_MAX

# Cache helper functions
async def get_cached_response(prompt_hash: str) -> Optional[str]:
    """Get cached AI response from Redis"""
    try:
        r = await get_redis()
        cached = await r.get(f"ai_response:{prompt_hash}")
        return cached
    except Exception as e:
        app.logger.error(f"Redis cache get error: {e}")
    return None

async def cache_response(prompt_hash: str, response: str):
    """Cache AI response in Redis"""
    try:
        r = await get_redis()
        await r.setex(f"ai_response:{prompt_hash}", CHAT_CACHE_TTL, response)
    except Exception as e:
        app.logger.error(f"Redis cache set error: {e}")

# Initialize admin user with fixed ID
async def init_admin():
    """Create default admin user if not exists"""
    admin = await get_user_by_username(ADMIN_USERNAME)
    if not admin:
        # Create admin with fixed ID = 'admin'
        admin_user = User(
            user_id='admin',  # Fixed ID for admin
            username=ADMIN_USERNAME,
            password_hash=generate_password_hash(ADMIN_PASSWORD),
            is_admin=True
        )
        await save_user(admin_user)
        app.logger.info(f"Created default admin user: {ADMIN_USERNAME} with ID: admin")
    else:
        # Ensure existing admin has correct admin status
        if not admin.is_admin:
            admin.is_admin = True
            await save_user(admin)
            app.logger.info(f"Fixed admin status for user: {ADMIN_USERNAME}")

@app.before_serving
async def startup():
    await init_admin()

# Decorators
def admin_required(f):
    @wraps(f)
    @login_required
    async def decorated_function(*args, **kwargs):
        user_data = await get_current_user_data()
        if not user_data or not user_data.is_admin:
            return redirect(url_for('chat'))
        return await f(*args, **kwargs)
    return decorated_function

# Routes
@app.route('/')
async def index():
    if await current_user.is_authenticated:
        return redirect(url_for('chat'))
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
async def login():
    if request.method == 'POST':
        data = await request.form
        username = sanitize_html(data.get('username'))
        password = data.get('password')  # Don't sanitize passwords
        
        user = await get_user_by_username(username)
        
        if user and check_password_hash(user.password_hash, password):
            # In quart-auth 0.11.0, we just pass the user ID to AuthUser
            login_user(AuthUser(user.id))
            app.logger.info(f"User logged in: {username} (ID: {user.id}, admin: {user.is_admin})")
            return redirect(url_for('chat'))
        else:
            return await render_template('login.html', error='Invalid username or password')
    
    return await render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
async def register():
    if request.method == 'POST':
        data = await request.form
        username = sanitize_html(data.get('username'))
        password = data.get('password')  # Don't sanitize passwords
        
        # Validate inputs
        if len(username) < 3:
            return await render_template('register.html', error='Username must be at least 3 characters')
        if len(password) < 6:
            return await render_template('register.html', error='Password must be at least 6 characters')
        
        # Check if user exists
        existing_user = await get_user_by_username(username)
        if existing_user:
            return await render_template('register.html', error='Username already exists')
        
        # Create new user - let save_user handle ID generation
        new_user = User(
            username=username,
            password_hash=generate_password_hash(password),
            is_admin=False  # Regular users are never admin
        )
        await save_user(new_user)
        
        app.logger.info(f"New user registered: {username} (ID: {new_user.id})")
        return redirect(url_for('login'))
    
    return await render_template('register.html')

@app.route('/logout')
@login_required
async def logout():
    logout_user()
    # Clear session data
    session.clear()
    return redirect(url_for('login'))

@app.route('/chat')
@login_required
async def chat():
    # Get current user data
    user_data = await get_current_user_data()
    if not user_data:
        return redirect(url_for('login'))
    
    # Get or create current session
    current_session_id = await get_or_create_current_session(user_data.id)
    
    return await render_template('chat.html', username=user_data.username)

@app.route('/api/chat/history')
@login_required
async def chat_history():
    # Get current session for this user
    current_session_id = await get_or_create_current_session(current_user.auth_id)
    messages = await get_session_messages(current_session_id)
    
    # Messages are already sanitized when saved
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'id': msg.get('id'),
            'role': msg.get('role'),
            'content': msg.get('content', ''),  # Already sanitized
            'timestamp': msg.get('timestamp')
        })
    
    return jsonify({'messages': formatted_messages})

@app.route('/admin')
@admin_required
async def admin():
    return await render_template('admin.html')

@app.route('/api/admin/users')
@admin_required
async def admin_users():
    users = await get_all_users()
    
    users_data = []
    for user in users:
        users_data.append({
            'id': user.id,
            'username': user.username,
            'is_admin': user.is_admin,
            'created_at': user.created_at
        })
    
    return jsonify({'users': users_data})

@app.route('/api/admin/chat/<user_id>')
@admin_required
async def admin_user_chat(user_id):
    # Get all messages for the user across all sessions
    messages = await get_user_messages(user_id)
    
    # Messages are already sanitized
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'id': msg.get('id'),
            'role': msg.get('role'),
            'content': msg.get('content', ''),  # Already sanitized
            'timestamp': msg.get('timestamp')
        })
    
    return jsonify({'messages': formatted_messages})

# WebSocket handler for chat
@app.websocket('/ws')
@login_required
async def ws():
    """WebSocket endpoint for real-time chat"""
    try:
        # Get current session for this user
        current_session_id = await get_or_create_current_session(current_user.auth_id)
        
        while True:
            data = await websocket.receive_json()
            
            if data['type'] == 'chat':
                # Check rate limit
                if not await check_rate_limit(current_user.auth_id):
                    await websocket.send_json({
                        'type': 'error',
                        'message': 'Rate limit exceeded. Please wait a moment before sending another message.'
                    })
                    continue
                
                # Sanitize user input
                user_message = sanitize_html(data.get('message', ''))
                if not user_message:
                    continue
                
                # Save user message to current session
                asyncio.create_task(save_message(current_user.auth_id, 'user', user_message, current_session_id))
                
                # Send user message back for display
                await websocket.send_json({
                    'type': 'message',
                    'role': 'user',
                    'content': user_message
                })
                
                # Check cache first
                prompt_hash = hashlib.md5(user_message.encode()).hexdigest()
                cached_response = await get_cached_response(prompt_hash)
                
                if cached_response:
                    # Send cached response
                    await websocket.send_json({
                        'type': 'message',
                        'role': 'assistant',
                        'content': cached_response,
                        'cached': True
                    })
                    # Save to current session
                    asyncio.create_task(save_message(current_user.auth_id, 'assistant', cached_response, current_session_id))
                else:
                    # Get AI response from Ollama with chat history
                    chat_history = await get_session_messages(current_session_id, 10)  # Last 10 messages for context
                    full_response = await get_ai_response(user_message, websocket, chat_history)
                    
                    if full_response:
                        # Sanitize AI response before caching/saving
                        sanitized_response = sanitize_html(full_response)
                        
                        # Cache the response asynchronously
                        asyncio.create_task(cache_response(prompt_hash, sanitized_response))
                        # Save to current session
                        asyncio.create_task(save_message(current_user.auth_id, 'assistant', sanitized_response, current_session_id))
                        
                        # Send completion signal
                        await websocket.send_json({
                            'type': 'complete',
                            'role': 'assistant',
                            'content': sanitized_response
                        })
                
    except asyncio.CancelledError:
        pass
    except Exception as e:
        app.logger.error(f"WebSocket error: {e}")

async def get_ai_response(prompt: str, ws, chat_history: List[Dict] = None) -> str:
    """Get response from Ollama AI model with streaming and chat history"""
    full_response = ""
    
    # Send typing indicator
    await ws.send_json({'type': 'typing', 'status': 'start'})
    
    try:
        # Build conversation context
        conversation = []
        if chat_history:
            for msg in chat_history[-10:]:  # Last 10 messages for context
                conversation.append({
                    "role": msg.get('role'),
                    "content": msg.get('content', '')
                })
        
        # Add current prompt
        conversation.append({"role": "user", "content": prompt})
        
        timeout = aiohttp.ClientTimeout(total=MODEL_TIMEOUT)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            # Use chat endpoint for better conversation handling
            async with session.post(
                f'{OLLAMA_URL}/api/chat',
                json={
                    'model': OLLAMA_MODEL,
                    'messages': conversation,
                    'stream': True,
                    'options': {
                        'temperature': MODEL_TEMPERATURE,
                        'top_p': MODEL_TOP_P,
                        'num_predict': MODEL_MAX_TOKENS
                    }
                }
            ) as response:
                if response.status != 200:
                    error_text = await response.text()
                    app.logger.error(f"Ollama API error {response.status}: {error_text}")
                    await ws.send_json({
                        'type': 'error',
                        'message': f'AI service error (HTTP {response.status}). Please try again.'
                    })
                    return ""

                async for line in response.content:
                    if line:
                        try:
                            chunk = json.loads(line)
                            if 'message' in chunk and 'content' in chunk['message']:
                                chunk_text = chunk['message']['content']
                                full_response += chunk_text
                                # Stream each chunk to client
                                await ws.send_json({
                                    'type': 'stream',
                                    'content': chunk_text
                                })
                                
                            if chunk.get('done', False):
                                break
                                
                        except json.JSONDecodeError:
                            continue
                        
    except asyncio.TimeoutError:
        await ws.send_json({
            'type': 'error',
            'message': f'AI response timeout after {MODEL_TIMEOUT}s. Please try again.'
        })
    except Exception as e:
        app.logger.error(f"Ollama API error: {e}")
        await ws.send_json({
            'type': 'error',
            'message': 'Failed to get AI response. Please check if the AI service is running.'
        })
    finally:
        # Stop typing indicator
        await ws.send_json({'type': 'typing', 'status': 'stop'})
    
    return full_response

# Session management API endpoints
@app.route('/api/chat/sessions')
@login_required
async def get_user_sessions():
    """Get all chat sessions for the current user"""
    sessions = await get_user_chat_sessions(current_user.auth_id)
    
    session_data = []
    for session in sessions:
        # Get message count for each session
        messages = await get_session_messages(session.id, limit=1)
        message_count = len(await get_session_messages(session.id))
        
        session_data.append({
            'id': session.id,
            'title': session.title,
            'created_at': session.created_at,
            'updated_at': session.updated_at,
            'message_count': message_count
        })
    
    return jsonify({'sessions': session_data})

@app.route('/api/chat/sessions', methods=['POST'])
@login_required
async def create_new_session():
    """Create a new chat session"""
    data = await request.get_json()
    title = sanitize_html(data.get('title', '')) if data else None
    
    session = await create_chat_session(current_user.auth_id, title)
    
    # Update current session in user's session storage
    session[f"current_session_{current_user.auth_id}"] = session.id
    
    return jsonify({
        'session': {
            'id': session.id,
            'title': session.title,
            'created_at': session.created_at,
            'updated_at': session.updated_at
        }
    })

@app.route('/api/chat/sessions/<session_id>/switch', methods=['POST'])
@login_required
async def switch_session(session_id):
    """Switch to a different chat session"""
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != current_user.auth_id:
        return jsonify({'error': 'Session not found'}), 404
    
    # Update current session
    session[f"current_session_{current_user.auth_id}"] = session_id
    
    # Get messages for this session
    messages = await get_session_messages(session_id)
    
    formatted_messages = []
    for msg in messages:
        formatted_messages.append({
            'id': msg.get('id'),
            'role': msg.get('role'),
            'content': msg.get('content', ''),
            'timestamp': msg.get('timestamp')
        })
    
    return jsonify({
        'session': {
            'id': session_obj.id,
            'title': session_obj.title,
            'created_at': session_obj.created_at,
            'updated_at': session_obj.updated_at
        },
        'messages': formatted_messages
    })

@app.route('/api/chat/sessions/<session_id>', methods=['DELETE'])
@login_required
async def delete_session(session_id):
    """Delete a chat session"""
    # Verify session belongs to user
    session_obj = await get_chat_session(session_id)
    if not session_obj or session_obj.user_id != current_user.auth_id:
        return jsonify({'error': 'Session not found'}), 404
    
    # Don't allow deleting the last session
    user_sessions = await get_user_chat_sessions(current_user.auth_id)
    if len(user_sessions) <= 1:
        return jsonify({'error': 'Cannot delete the last session'}), 400
    
    await delete_chat_session(current_user.auth_id, session_id)
    
    # If this was the current session, switch to another one
    current_session_key = f"current_session_{current_user.auth_id}"
    if session.get(current_session_key) == session_id:
        remaining_sessions = await get_user_chat_sessions(current_user.auth_id)
        if remaining_sessions:
            session[current_session_key] = remaining_sessions[0].id
    
    return jsonify({'success': True})

if __name__ == '__main__':
    app.run(debug=True)