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
from quart_session import Session
import redis.asyncio as redis
from werkzeug.security import generate_password_hash, check_password_hash

# Load environment variables
load_dotenv()

# Initialize Quart app
app = Quart(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['QUART_AUTH_COOKIE_SECURE'] = os.environ.get('SECURE_COOKIES', 'false').lower() == 'true'
app.config['QUART_AUTH_COOKIE_HTTPONLY'] = True
app.config['QUART_AUTH_COOKIE_SAMESITE'] = 'Lax'
app.config['SESSION_TYPE'] = 'redis'
app.config['SESSION_REDIS'] = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
app.config['SESSION_COOKIE_NAME'] = 'session'


# CSRF Protection
app.config['WTF_CSRF_ENABLED'] = True
app.config['WTF_CSRF_TIME_LIMIT'] = None  # CSRF token doesn't expire

# Initialize extensions
auth = QuartAuth(app)
Session(app)

# Redis configuration
REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
CHAT_CACHE_TTL = 3600  # 1 hour cache for AI responses
USER_DATA_TTL = 0  # No expiry for user data
CHAT_HISTORY_TTL = 0  # No expiry for chat history
RATE_LIMIT_WINDOW = 60  # 1 minute
RATE_LIMIT_MAX = 10  # 10 messages per minute

# Admin credentials from environment
ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin123')

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

# User model for auth
class User(AuthUser):
    def __init__(self, user_id=None, username=None, password_hash=None, is_admin=False, created_at=None):
        self.id = user_id
        self.username = username
        self.password_hash = password_hash
        self.is_admin = is_admin
        self.created_at = created_at or datetime.utcnow().isoformat()
    
    @property
    def auth_id(self):
        return str(self.id)
    
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

# CSRF Token Management
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
@app.before_request
async def add_security_headers():
    """Add security headers to all responses"""
    @app.after_request
    async def set_security_headers(response):
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

async def save_user(user: User):
    """Save user to Redis"""
    r = await get_redis()
    user_data = user.to_dict()
    
    # Save user data
    await r.hset(f"user:{user.id}", mapping=user_data)
    
    # Add to username index for lookup
    await r.set(f"username:{user.username}", user.id)
    
    # Add to users set
    await r.sadd("users", user.id)

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

async def save_message(user_id: str, role: str, content: str, session_id: str):
    """Save chat message to Redis"""
    r = await get_redis()
    
    # Content is already sanitized when received
    message_id = f"{user_id}:{datetime.utcnow().timestamp()}"
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
    
    # Add to user's message list (sorted by timestamp)
    await r.zadd(f"user_messages:{user_id}", {message_id: datetime.utcnow().timestamp()})

async def get_user_messages(user_id: str, limit: int = 100) -> List[Dict]:
    """Get user's chat messages from Redis"""
    r = await get_redis()
    
    # Get message IDs sorted by timestamp (newest first)
    message_ids = await r.zrevrange(f"user_messages:{user_id}", 0, limit - 1)
    
    messages = []
    for msg_id in message_ids:
        msg_data = await r.hgetall(f"message:{msg_id}")
        if msg_data:
            messages.append(msg_data)
    
    return messages[::-1]  # Reverse to get oldest first

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

# Initialize admin user
async def init_admin():
    """Create default admin user if not exists"""
    admin = await get_user_by_username(ADMIN_USERNAME)
    if not admin:
        admin_user = User(
            user_id='1',
            username=ADMIN_USERNAME,
            password_hash=generate_password_hash(ADMIN_PASSWORD),
            is_admin=True
        )
        await save_user(admin_user)
        app.logger.info(f"Created default admin user: {ADMIN_USERNAME}")

@app.before_serving
async def startup():
    await init_admin()

# Auth callbacks - NOT NEEDED ANYMORE IN QUART
#@auth.user_loader
#async def load_user(user_id):
    #return await get_user_by_id(user_id)

# Decorators
def admin_required(f):
    @wraps(f)
    @login_required
    async def decorated_function(*args, **kwargs):
        if not current_user.is_admin:
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
            login_user(user)
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
        
        # Generate unique user ID
        r = await get_redis()
        user_id = await r.incr('user_id_counter')
        
        # Create new user
        new_user = User(
            user_id=str(user_id),
            username=username,
            password_hash=generate_password_hash(password),
            is_admin=False
        )
        await save_user(new_user)
        
        return redirect(url_for('login'))
    
    return await render_template('register.html')

@app.route('/logout')
@login_required
async def logout():
    logout_user()
    return redirect(url_for('login'))

@app.route('/chat')
@login_required
async def chat():
    return await render_template('chat.html', username=current_user.username)

@app.route('/api/chat/history')
@login_required
async def chat_history():
    messages = await get_user_messages(current_user.id)
    
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
        while True:
            data = await websocket.receive_json()
            
            if data['type'] == 'chat':
                # Check rate limit
                if not await check_rate_limit(current_user.id):
                    await websocket.send_json({
                        'type': 'error',
                        'message': 'Rate limit exceeded. Please wait a moment before sending another message.'
                    })
                    continue
                
                # Sanitize user input
                user_message = sanitize_html(data.get('message', ''))
                if not user_message:
                    continue
                
                session_id = session.get('session_id', f"{current_user.id}_{datetime.utcnow().timestamp()}")
                
                # Save user message to Redis asynchronously
                asyncio.create_task(save_message(current_user.id, 'user', user_message, session_id))
                
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
                    # Save to Redis asynchronously
                    asyncio.create_task(save_message(current_user.id, 'assistant', cached_response, session_id))
                else:
                    # Get AI response from Ollama
                    full_response = await get_ai_response(user_message, websocket)
                    
                    if full_response:
                        # Sanitize AI response before caching/saving
                        sanitized_response = sanitize_html(full_response)
                        
                        # Cache the response asynchronously
                        asyncio.create_task(cache_response(prompt_hash, sanitized_response))
                        # Save to Redis asynchronously
                        asyncio.create_task(save_message(current_user.id, 'assistant', sanitized_response, session_id))
                        
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

async def get_ai_response(prompt: str, ws) -> str:
    """Get response from Ollama AI model with streaming"""
    ollama_url = os.environ.get('OLLAMA_URL', 'http://localhost:11434')
    full_response = ""
    
    # Send typing indicator
    await ws.send_json({'type': 'typing', 'status': 'start'})
    
    try:
        timeout = aiohttp.ClientTimeout(total=300)  # 5 minute timeout
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f'{ollama_url}/api/generate',
                json={
                    'model': 'deepseek-r1:32b',
                    'prompt': prompt,
                    'stream': True,
                    'options': {
                        'temperature': 0.7,
                        'top_p': 0.9,
                        'num_predict': 2048
                    }
                }
            ) as response:
                async for line in response.content:
                    if line:
                        try:
                            chunk = json.loads(line)
                            if 'response' in chunk:
                                chunk_text = chunk['response']
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
            'message': 'AI response timeout. Please try again.'
        })
    except Exception as e:
        app.logger.error(f"Ollama API error: {e}")
        await ws.send_json({
            'type': 'error',
            'message': 'Failed to get AI response. Please try again.'
        })
    finally:
        # Stop typing indicator
        await ws.send_json({'type': 'typing', 'status': 'stop'})
    
    return full_response

if __name__ == '__main__':
    app.run()