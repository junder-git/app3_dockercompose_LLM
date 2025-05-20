#!/usr/bin/env python3
"""
GraphQL Resolvers for DeepSeek-Coder
This module contains the resolver functions for GraphQL queries and mutations.
"""

from typing import List, Optional, Dict, Any
import datetime

from strawberry.types import Info

# Import schema types
from .schema import User, Chat, Message, Artifact, Session
from .schema import ChatInput, MessageInput, ArtifactInput

# Redis client
import aioredis
from typing import Union

# Global Redis connection pool
redis_pool = None

async def init_redis_pool(app):
    """Initialize Redis connection pool"""
    global redis_pool
    redis_host = app.config.get("REDIS_HOST", "redis")
    redis_port = app.config.get("REDIS_PORT", 6379)
    redis_password = app.config.get("REDIS_PASSWORD", None)
    redis_db = app.config.get("REDIS_DB", 0)
    
    redis_url = f"redis://:{redis_password}@{redis_host}:{redis_port}/{redis_db}"
    redis_pool = aioredis.from_url(
        redis_url,
        encoding="utf-8",
        decode_responses=True
    )
    return redis_pool

async def close_redis_pool():
    """Close Redis connection pool"""
    global redis_pool
    if redis_pool:
        await redis_pool.close()

# Cache decorator
def cache(ttl: int = 300):
    """Cache decorator for resolver functions"""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            global redis_pool
            if not redis_pool:
                return await func(*args, **kwargs)
            
            # Generate cache key
            cache_key = f"graphql:{func.__name__}:{str(args)}:{str(kwargs)}"
            
            # Try to get from cache
            cached = await redis_pool.get(cache_key)
            if cached:
                import json
                return json.loads(cached)
            
            # Execute function
            result = await func(*args, **kwargs)
            
            # Store in cache
            if result is not None:
                import json
                await redis_pool.setex(
                    cache_key, 
                    ttl,
                    json.dumps(result, default=lambda o: o.__dict__ if hasattr(o, "__dict__") else str(o))
                )
            
            return result
        return wrapper
    return decorator

# Helper for getting DB connection from Quart app
async def get_db_conn(info: Info):
    """Get database connection from Quart app context"""
    request = info.context["request"]
    app = request.get("app")
    if not app:
        raise Exception("App context not available")
    
    return await app.db_pool.acquire()

# Helper for getting current user ID
async def get_current_user_id(info: Info) -> int:
    """Get current user ID from Quart auth session"""
    request = info.context["request"]
    user_id = request.get("user_id")
    if not user_id:
        raise Exception("User not authenticated")
    return user_id

# User resolvers
async def get_current_user(info: Info) -> User:
    """Get the current authenticated user"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        user_data = await conn.fetchrow(
            """
            SELECT id, username, email, full_name, is_admin, created_at, last_login
            FROM users
            WHERE id = $1
            """,
            user_id
        )
    
    if not user_data:
        raise Exception("User not found")
    
    return User(
        id=user_data["id"],
        username=user_data["username"],
        email=user_data["email"],
        full_name=user_data["full_name"],
        is_admin=user_data["is_admin"],
        created_at=user_data["created_at"],
        last_login=user_data["last_login"]
    )

# Chat resolvers
@cache(ttl=60)
async def get_chats(info: Info, archived: bool = False) -> List[Chat]:
    """Get all chats for the current user"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        chats_data = await conn.fetch(
            """
            SELECT id, title, created_at, updated_at, is_archived
            FROM chats
            WHERE user_id = $1 AND is_archived = $2
            ORDER BY updated_at DESC
            """,
            user_id, archived
        )
    
    return [
        Chat(
            id=chat["id"],
            title=chat["title"],
            created_at=chat["created_at"],
            updated_at=chat["updated_at"],
            is_archived=chat["is_archived"]
        )
        for chat in chats_data
    ]

@cache(ttl=30)
async def get_chat(info: Info, id: int) -> Optional[Chat]:
    """Get a specific chat by ID"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        chat_data = await conn.fetchrow(
            """
            SELECT id, title, created_at, updated_at, is_archived
            FROM chats
            WHERE id = $1 AND user_id = $2
            """,
            id, user_id
        )
    
    if not chat_data:
        return None
    
    # Get messages for this chat
    messages = await get_messages(info, id)
    
    # Get artifacts for this chat
    artifacts = await get_artifacts(info, id)
    
    return Chat(
        id=chat_data["id"],
        title=chat_data["title"],
        created_at=chat_data["created_at"],
        updated_at=chat_data["updated_at"],
        is_archived=chat_data["is_archived"],
        messages=messages,
        artifacts=artifacts
    )

async def create_chat(info: Info, input: ChatInput) -> Chat:
    """Create a new chat"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        chat_id = await conn.fetchval(
            """
            INSERT INTO chats (user_id, title)
            VALUES ($1, $2)
            RETURNING id
            """,
            user_id, input.title
        )
        
        chat_data = await conn.fetchrow(
            """
            SELECT id, title, created_at, updated_at, is_archived
            FROM chats
            WHERE id = $1
            """,
            chat_id
        )
    
    # Invalidate cache for chats list
    if redis_pool:
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': False}}")
    
    return Chat(
        id=chat_data["id"],
        title=chat_data["title"],
        created_at=chat_data["created_at"],
        updated_at=chat_data["updated_at"],
        is_archived=chat_data["is_archived"],
        messages=[],
        artifacts=[]
    )

async def update_chat_title(info: Info, id: int, title: str) -> Chat:
    """Update a chat's title"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Verify chat belongs to user
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            id, user_id
        )
        
        if not chat:
            raise Exception("Chat not found")
        
        # Update chat title
        await conn.execute(
            """
            UPDATE chats
            SET title = $1, updated_at = CURRENT_TIMESTAMP
            WHERE id = $2
            """,
            title, id
        )
        
        # Get updated chat data
        chat_data = await conn.fetchrow(
            """
            SELECT id, title, created_at, updated_at, is_archived
            FROM chats
            WHERE id = $1
            """,
            id
        )
    
    # Invalidate caches
    if redis_pool:
        await redis_pool.delete(f"graphql:get_chat:{str((info,))}:{{\'id\': {id}}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': False}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': True}}")
    
    return Chat(
        id=chat_data["id"],
        title=chat_data["title"],
        created_at=chat_data["created_at"],
        updated_at=chat_data["updated_at"],
        is_archived=chat_data["is_archived"]
    )

async def archive_chat(info: Info, id: int) -> Chat:
    """Archive a chat"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Verify chat belongs to user
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            id, user_id
        )
        
        if not chat:
            raise Exception("Chat not found")
        
        # Archive the chat
        await conn.execute(
            """
            UPDATE chats
            SET is_archived = TRUE, updated_at = CURRENT_TIMESTAMP
            WHERE id = $1
            """,
            id
        )
        
        # Get updated chat data
        chat_data = await conn.fetchrow(
            """
            SELECT id, title, created_at, updated_at, is_archived
            FROM chats
            WHERE id = $1
            """,
            id
        )
    
    # Invalidate caches
    if redis_pool:
        await redis_pool.delete(f"graphql:get_chat:{str((info,))}:{{\'id\': {id}}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': False}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': True}}")
    
    return Chat(
        id=chat_data["id"],
        title=chat_data["title"],
        created_at=chat_data["created_at"],
        updated_at=chat_data["updated_at"],
        is_archived=chat_data["is_archived"]
    )

async def restore_chat(info: Info, id: int) -> Chat:
    """Restore an archived chat"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Verify chat belongs to user
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            id, user_id
        )
        
        if not chat:
            raise Exception("Chat not found")
        
        # Restore the chat
        await conn.execute(
            """
            UPDATE chats
            SET is_archived = FALSE, updated_at = CURRENT_TIMESTAMP
            WHERE id = $1
            """,
            id
        )
        
        # Get updated chat data
        chat_data = await conn.fetchrow(
            """
            SELECT id, title, created_at, updated_at, is_archived
            FROM chats
            WHERE id = $1
            """,
            id
        )
    
    # Invalidate caches
    if redis_pool:
        await redis_pool.delete(f"graphql:get_chat:{str((info,))}:{{\'id\': {id}}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': False}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': True}}")
    
    return Chat(
        id=chat_data["id"],
        title=chat_data["title"],
        created_at=chat_data["created_at"],
        updated_at=chat_data["updated_at"],
        is_archived=chat_data["is_archived"]
    )

async def delete_chat(info: Info, id: int) -> bool:
    """Delete a chat"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Verify chat belongs to user
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            id, user_id
        )
        
        if not chat:
            raise Exception("Chat not found")
        
        # Delete all related data first
        await conn.execute("DELETE FROM artifacts WHERE chat_id = $1", id)
        await conn.execute("DELETE FROM messages WHERE chat_id = $1", id)
        
        # Delete the chat
        await conn.execute("DELETE FROM chats WHERE id = $1", id)
    
    # Invalidate caches
    if redis_pool:
        await redis_pool.delete(f"graphql:get_chat:{str((info,))}:{{\'id\': {id}}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': False}}")
        await redis_pool.delete(f"graphql:get_chats:{str((info,))}:{{\'archived\': True}}")
    
    return True

# Message resolvers
@cache(ttl=30)
async def get_messages(info: Info, chat_id: int) -> List[Message]:
    """Get all messages for a chat"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Verify chat belongs to user
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            chat_id, user_id
        )
        
        if not chat:
            raise Exception("Chat not found")
        
        # Get messages
        messages_data = await conn.fetch(
            """
            SELECT id, chat_id, role, content, created_at
            FROM messages
            WHERE chat_id = $1
            ORDER BY created_at
            """,
            chat_id
        )
    
    return [
        Message(
            id=message["id"],
            chat_id=message["chat_id"],
            role=message["role"],
            content=message["content"],
            created_at=message["created_at"]
        )
        for message in messages_data
    ]

# Artifact resolvers
@cache(ttl=60)
async def get_artifacts(info: Info, chat_id: int) -> List[Artifact]:
    """Get all artifacts for a chat"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Verify chat belongs to user
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            chat_id, user_id
        )
        
        if not chat:
            raise Exception("Chat not found")
        
        # Get artifacts
        artifacts_data = await conn.fetch(
            """
            SELECT id, chat_id, message_id, title, content, content_type, language, created_at
            FROM artifacts
            WHERE chat_id = $1
            ORDER BY created_at
            """,
            chat_id
        )
    
    return [
        Artifact(
            id=artifact["id"],
            chat_id=artifact["chat_id"],
            message_id=artifact["message_id"],
            title=artifact["title"],
            content=artifact["content"],
            content_type=artifact["content_type"],
            language=artifact["language"],
            created_at=artifact["created_at"]
        )
        for artifact in artifacts_data
    ]

@cache(ttl=60)
async def get_artifact(info: Info, id: int) -> Optional[Artifact]:
    """Get a specific artifact by ID"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Get artifact with verification that it belongs to user
        artifact_data = await conn.fetchrow(
            """
            SELECT a.id, a.chat_id, a.message_id, a.title, a.content, a.content_type, a.language, a.created_at
            FROM artifacts a
            JOIN chats c ON a.chat_id = c.id
            WHERE a.id = $1 AND c.user_id = $2
            """,
            id, user_id
        )
    
    if not artifact_data:
        return None
    
    return Artifact(
        id=artifact_data["id"],
        chat_id=artifact_data["chat_id"],
        message_id=artifact_data["message_id"],
        title=artifact_data["title"],
        content=artifact_data["content"],
        content_type=artifact_data["content_type"],
        language=artifact_data["language"],
        created_at=artifact_data["created_at"]
    )

async def create_artifact(info: Info, input: ArtifactInput) -> Artifact:
    """Create a new artifact"""
    user_id = await get_current_user_id(info)
    
    async with await get_db_conn(info) as conn:
        # Verify chat belongs to user
        chat = await conn.fetchrow(
            "SELECT id FROM chats WHERE id = $1 AND user_id = $2",
            input.chat_id, user_id
        )
        
        if not chat:
            raise Exception("Chat not found")
        
        # Create artifact
        artifact_id = await conn.fetchval(
            """
            INSERT INTO artifacts (chat_id, message_id, title, content, content_type, language)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id
            """,
            input.chat_id,
            input.message_id,
            input.title,
            input.content,
            input.content_type,
            input.language
        )
        
        # Get created artifact
        artifact_data = await conn.fetchrow(
            """
            SELECT id, chat_id, message_id, title, content, content_type, language, created_at
            FROM artifacts
            WHERE id = $1
            """,
            artifact_id
        )
    
    # Invalidate cache
    if redis_pool:
        await redis_pool.delete(f"graphql:get_artifacts:{str((info,))}:{{\'chat_id\': {input.chat_id}}}")
        await redis_pool.delete(f"graphql:get_chat:{str((info,))}:{{\'id\': {input.chat_id}}}")
    
    return Artifact(
        id=artifact_data["id"],
        chat_id=artifact_data["chat_id"],
        message_id=artifact_data["message_id"],
        title=artifact_data["title"],
        content=artifact_data["content"],
        content_type=artifact_data["content_type"],
        language=artifact_data["language"],
        created_at=artifact_data["created_at"]
    )

# Session resolvers
@cache(ttl=60)
async def get_sessions(info: Info) -> List[Session]:
    """Get all active sessions for the current user"""
    user_id = await get_current_user_id(info)
    request = info.context["request"]
    current_session_id = request.get("session_id")
    
    async with await get_db_conn(info) as conn:
        sessions_data = await conn.fetch(
            """
            SELECT session_id, created_at, expires_at, ip_address, user_agent
            FROM sessions
            WHERE user_id = $1 AND expires_at > CURRENT_TIMESTAMP
            ORDER BY created_at DESC
            """,
            user_id
        )
    
    return [
        Session(
            id=session["session_id"],
            user_id=user_id,
            created_at=session["created_at"],
            expires_at=session["expires_at"],
            ip_address=session["ip_address"],
            user_agent=session["user_agent"],
            is_current=(session["session_id"] == current_session_id)
        )
        for session in sessions_data
    ]