#!/usr/bin/env python3
"""
GraphQL Schema for DeepSeek-Coder
This module defines the GraphQL types and queries for the DeepSeek-Coder application.
"""

import datetime
from typing import List, Optional

import strawberry
from strawberry.types import Info
from strawberry.permission import BasePermission

# Custom permission class for authentication
class IsAuthenticated(BasePermission):
    message = "User is not authenticated"
    
    async def has_permission(self, source, info: Info, **kwargs) -> bool:
        # Check if the user is authenticated through Quart-Auth session
        request = info.context["request"]
        return request.get("is_authenticated", False)

# Define GraphQL types
@strawberry.type
class User:
    id: int
    username: str
    email: Optional[str] = None
    full_name: Optional[str] = None
    is_admin: bool
    created_at: datetime.datetime
    last_login: Optional[datetime.datetime] = None

@strawberry.type
class Chat:
    id: int
    title: str
    created_at: datetime.datetime
    updated_at: datetime.datetime
    is_archived: bool
    messages: Optional[List["Message"]] = None
    artifacts: Optional[List["Artifact"]] = None

@strawberry.type
class Message:
    id: int
    chat_id: int
    role: str
    content: str
    created_at: datetime.datetime

@strawberry.type
class Artifact:
    id: int
    chat_id: int
    message_id: Optional[int] = None
    title: str
    content: str
    content_type: str
    language: Optional[str] = None
    created_at: datetime.datetime

@strawberry.type
class Session:
    id: str
    user_id: int
    created_at: datetime.datetime
    expires_at: datetime.datetime
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    is_current: bool

# Define GraphQL input types
@strawberry.input
class ChatInput:
    title: str

@strawberry.input
class MessageInput:
    chat_id: int
    content: str

@strawberry.input
class ArtifactInput:
    chat_id: int
    title: str
    content: str
    content_type: str = "text/plain"
    language: Optional[str] = None
    message_id: Optional[int] = None

# Define mutations
@strawberry.type
class Mutation:
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def create_chat(self, info: Info, input: ChatInput) -> Chat:
        # Implementation in resolvers.py
        from .resolvers import create_chat
        return await create_chat(info, input)
    
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def update_chat_title(self, info: Info, id: int, title: str) -> Chat:
        # Implementation in resolvers.py
        from .resolvers import update_chat_title
        return await update_chat_title(info, id, title)
    
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def archive_chat(self, info: Info, id: int) -> Chat:
        # Implementation in resolvers.py
        from .resolvers import archive_chat
        return await archive_chat(info, id)
    
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def restore_chat(self, info: Info, id: int) -> Chat:
        # Implementation in resolvers.py
        from .resolvers import restore_chat
        return await restore_chat(info, id)
    
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def delete_chat(self, info: Info, id: int) -> bool:
        # Implementation in resolvers.py
        from .resolvers import delete_chat
        return await delete_chat(info, id)
    
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def create_artifact(self, info: Info, input: ArtifactInput) -> Artifact:
        # Implementation in resolvers.py
        from .resolvers import create_artifact
        return await create_artifact(info, input)

# Define queries
@strawberry.type
class Query:
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def me(self, info: Info) -> User:
        # Implementation in resolvers.py
        from .resolvers import get_current_user
        return await get_current_user(info)
    
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def chat(self, info: Info, id: int) -> Optional[Chat]:
        # Implementation in resolvers.py
        from .resolvers import get_chat
        return await get_chat(info, id)
    
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def chats(self, info: Info, archived: bool = False) -> List[Chat]:
        # Implementation in resolvers.py
        from .resolvers import get_chats
        return await get_chats(info, archived)
    
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def artifacts(self, info: Info, chat_id: int) -> List[Artifact]:
        # Implementation in resolvers.py
        from .resolvers import get_artifacts
        return await get_artifacts(info, chat_id)
    
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def artifact(self, info: Info, id: int) -> Optional[Artifact]:
        # Implementation in resolvers.py
        from .resolvers import get_artifact
        return await get_artifact(info, id)
    
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def messages(self, info: Info, chat_id: int) -> List[Message]:
        # Implementation in resolvers.py
        from .resolvers import get_messages
        return await get_messages(info, chat_id)
    
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def sessions(self, info: Info) -> List[Session]:
        # Implementation in resolvers.py
        from .resolvers import get_sessions
        return await get_sessions(info)

# Create the schema
schema = strawberry.Schema(query=Query, mutation=Mutation)