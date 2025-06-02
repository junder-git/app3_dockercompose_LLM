# database.py - Modified for single session per user
import os
import secrets
from datetime import datetime
from typing import Optional, List, Dict, Any
import redis.asyncio as redis
from werkzeug.security import generate_password_hash

from .models import User, ChatSession

# Redis configuration
REDIS_URL = os.environ.get('REDIS_URL', 'redis://redis:6379/0')
CHAT_CACHE_TTL = int(os.environ.get('CHAT_CACHE_TTL_SECONDS', '3600'))
RATE_LIMIT_WINDOW = 60
RATE_LIMIT_MAX = int(os.environ.get('RATE_LIMIT_MESSAGES_PER_MINUTE', '10'))

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

# Helper functions
async def get_redis():
    return await redis_pool.get_client()

async def get_next_user_id():
    """Get the next available user ID"""
    r = await get_redis()
    return await r.incr('user_id_counter')

# User management functions
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

async def get_current_user_data(user_id: str) -> Optional[User]:
    """Get current user data from Redis"""
    return await get_user_by_id(user_id)

# Chat session management - MODIFIED FOR SINGLE SESSION
async def get_or_create_user_session(user_id: str) -> ChatSession:
    """Get or create the single session for a user"""
    r = await get_redis()
    
    # Check if user already has a session
    session_id = await r.get(f"user_session:{user_id}")
    
    if session_id:
        # Get existing session
        session_data = await r.hgetall(f"session:{session_id}")
        if session_data:
            return ChatSession.from_dict(session_data)
    
    # Create new session
    session = ChatSession(user_id=user_id, title="My Chat")
    session.id = f"{user_id}_session"  # Fixed session ID per user
    
    # Save session data
    await r.hset(f"session:{session.id}", mapping=session.to_dict())
    
    # Save session ID reference
    await r.set(f"user_session:{user_id}", session.id)
    
    return session

async def get_chat_session(session_id: str) -> Optional[ChatSession]:
    """Get chat session by ID"""
    r = await get_redis()
    session_data = await r.hgetall(f"session:{session_id}")
    
    if session_data:
        return ChatSession.from_dict(session_data)
    return None

async def clear_user_chat(user_id: str) -> Dict[str, Any]:
    """Clear all messages in user's chat session"""
    r = await get_redis()
    result = {'success': False, 'message': '', 'deleted_count': 0}
    
    try:
        # Get user's session
        session_id = await r.get(f"user_session:{user_id}")
        if not session_id:
            result['message'] = "No chat session found"
            return result
        
        # Delete all messages in the session
        message_ids = await r.zrange(f"session_messages:{session_id}", 0, -1)
        deleted_count = 0
        
        for msg_id in message_ids:
            await r.delete(f"message:{msg_id}")
            deleted_count += 1
        
        # Clear the session messages list
        await r.delete(f"session_messages:{session_id}")
        
        # Update session timestamp
        session = await get_chat_session(session_id)
        if session:
            session.updated_at = datetime.utcnow().isoformat()
            await r.hset(f"session:{session_id}", mapping=session.to_dict())
        
        result['success'] = True
        result['message'] = f"Cleared {deleted_count} messages"
        result['deleted_count'] = deleted_count
        
    except Exception as e:
        result['message'] = f"Failed to clear chat: {str(e)}"
    
    return result

async def compress_user_chat(user_id: str, keep_count: int = 50) -> Dict[str, Any]:
    """Compress chat by keeping only the most recent messages"""
    r = await get_redis()
    result = {'success': False, 'message': '', 'deleted_count': 0, 'kept_count': 0}
    
    try:
        # Get user's session
        session_id = await r.get(f"user_session:{user_id}")
        if not session_id:
            result['message'] = "No chat session found"
            return result
        
        # Get all message IDs sorted by timestamp
        all_message_ids = await r.zrange(f"session_messages:{session_id}", 0, -1)
        total_messages = len(all_message_ids)
        
        if total_messages <= keep_count:
            result['message'] = f"Chat has only {total_messages} messages, no compression needed"
            result['kept_count'] = total_messages
            return result
        
        # Get message IDs to delete (older messages)
        messages_to_delete = all_message_ids[:-keep_count]
        deleted_count = 0
        
        for msg_id in messages_to_delete:
            await r.delete(f"message:{msg_id}")
            await r.zrem(f"session_messages:{session_id}", msg_id)
            deleted_count += 1
        
        result['success'] = True
        result['message'] = f"Compressed chat from {total_messages} to {keep_count} messages"
        result['deleted_count'] = deleted_count
        result['kept_count'] = keep_count
        
    except Exception as e:
        result['message'] = f"Failed to compress chat: {str(e)}"
    
    return result

async def get_or_create_current_session(user_id: str) -> str:
    """Get current session ID or create a new one"""
    session = await get_or_create_user_session(user_id)
    return session.id

# Message management
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
    """Get messages for a user's single session"""
    r = await get_redis()
    
    # Get user's session
    session_id = await r.get(f"user_session:{user_id}")
    if not session_id:
        return []
    
    return await get_session_messages(session_id, limit)

async def get_chat_statistics(user_id: str) -> Dict[str, Any]:
    """Get statistics about user's chat"""
    r = await get_redis()
    stats = {
        'total_messages': 0,
        'user_messages': 0,
        'assistant_messages': 0,
        'oldest_message': None,
        'newest_message': None,
        'session_created': None
    }
    
    try:
        # Get user's session
        session_id = await r.get(f"user_session:{user_id}")
        if not session_id:
            return stats
        
        # Get session info
        session = await get_chat_session(session_id)
        if session:
            stats['session_created'] = session.created_at
        
        # Get all messages
        messages = await get_session_messages(session_id, limit=None)
        stats['total_messages'] = len(messages)
        
        for msg in messages:
            if msg['role'] == 'user':
                stats['user_messages'] += 1
            elif msg['role'] == 'assistant':
                stats['assistant_messages'] += 1
        
        if messages:
            stats['oldest_message'] = messages[0]['timestamp']
            stats['newest_message'] = messages[-1]['timestamp']
    
    except Exception as e:
        print(f"Error getting chat statistics: {e}")
    
    return stats

# Rate limiting
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
        print(f"Redis cache get error: {e}")
    return None

async def cache_response(prompt_hash: str, response: str):
    """Cache AI response in Redis"""
    try:
        r = await get_redis()
        await r.setex(f"ai_response:{prompt_hash}", CHAT_CACHE_TTL, response)
    except Exception as e:
        print(f"Redis cache set error: {e}")

# Database management functions (keeping existing functions)
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
                # Get message count for user's single session
                session_id = await r.get(f"user_session:{user_id}")
                message_count = 0
                if session_id:
                    message_count = await r.zcard(f"session_messages:{session_id}")
                
                users_data.append({
                    'id': user_id,
                    'username': user_data.get('username'),
                    'is_admin': user_data.get('is_admin') == 'true',
                    'created_at': user_data.get('created_at'),
                    'message_count': message_count
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
        print(f"Error getting database stats: {e}")
        return {'error': str(e)}

# User deletion functions
async def delete_user(user_id: str) -> Dict[str, Any]:
    """Delete a specific user and all their data"""
    r = await get_redis()
    result = {'success': False, 'message': '', 'deleted_data': {}}
    
    try:
        # Get user data first
        user = await get_user_by_id(user_id)
        if not user:
            result['message'] = f"User with ID {user_id} not found"
            return result
        
        # Don't allow deleting the admin user
        if user.is_admin:
            result['message'] = "Cannot delete admin user"
            return result
        
        deleted_counts = {
            'messages': 0,
            'cache_entries': 0
        }
        
        # Delete user's session and messages
        session_id = await r.get(f"user_session:{user_id}")
        if session_id:
            # Delete all messages in the session
            message_ids = await r.zrange(f"session_messages:{session_id}", 0, -1)
            for msg_id in message_ids:
                await r.delete(f"message:{msg_id}")
                deleted_counts['messages'] += 1
            
            # Delete session messages list
            await r.delete(f"session_messages:{session_id}")
            
            # Delete session data
            await r.delete(f"session:{session_id}")
            
            # Delete user session reference
            await r.delete(f"user_session:{user_id}")
        
        # Delete rate limit keys for this user
        rate_limit_key = f"rate_limit:{user_id}"
        if await r.exists(rate_limit_key):
            await r.delete(rate_limit_key)
        
        # Delete user data
        await r.delete(f"user:{user_id}")
        
        # Remove from username index
        await r.delete(f"username:{user.username}")
        
        # Remove from users set
        await r.srem("users", user_id)
        
        result['success'] = True
        result['message'] = f"Successfully deleted user {user.username} (ID: {user_id})"
        result['deleted_data'] = deleted_counts
        
    except Exception as e:
        result['message'] = f"Failed to delete user: {str(e)}"
        print(f"Error deleting user {user_id}: {e}")
    
    return result

async def delete_user_messages_only(user_id: str) -> Dict[str, Any]:
    """Delete only the messages for a user, keeping the user account"""
    r = await get_redis()
    result = {'success': False, 'message': '', 'deleted_count': 0}
    
    try:
        # Check if user exists
        user = await get_user_by_id(user_id)
        if not user:
            result['message'] = f"User with ID {user_id} not found"
            return result
        
        # Get user's session
        session_id = await r.get(f"user_session:{user_id}")
        if not session_id:
            result['message'] = "No chat session found"
            return result
        
        # Delete all messages in the session
        message_ids = await r.zrange(f"session_messages:{session_id}", 0, -1)
        deleted_count = 0
        
        for msg_id in message_ids:
            await r.delete(f"message:{msg_id}")
            deleted_count += 1
        
        # Clear the session messages list
        await r.delete(f"session_messages:{session_id}")
        
        result['success'] = True
        result['message'] = f"Successfully deleted {deleted_count} messages for user {user.username}"
        result['deleted_count'] = deleted_count
        
    except Exception as e:
        result['message'] = f"Failed to delete messages: {str(e)}"
        print(f"Error deleting messages for user {user_id}: {e}")
    
    return result

async def cleanup_database(cleanup_type: str, admin_user_id: str):
    """Perform database cleanup operations"""
    r = await get_redis()
    result = {'success': False, 'message': '', 'stats': {}}
    
    try:
        print(f"Database cleanup initiated by admin user {admin_user_id}, type: {cleanup_type}")
        
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
            existing_admin_id = await r.get(f"username:{os.environ.get('ADMIN_USERNAME', 'admin')}")
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
        
        print(f"Database cleanup completed successfully: {cleanup_type}")
        
    except Exception as e:
        result['message'] = f"Cleanup failed: {str(e)}"
        print(f"Database cleanup failed: {e}")
    
    return result

async def recreate_admin_user():
    """Helper function to recreate admin user with proper settings"""
    r = await get_redis()
    
    ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
    ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin123')
    
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