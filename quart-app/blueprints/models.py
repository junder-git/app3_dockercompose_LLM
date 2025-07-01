# models.py
from datetime import datetime

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