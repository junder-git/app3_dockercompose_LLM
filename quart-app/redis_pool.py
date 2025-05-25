# redis_pool.py - Add this file to the quart-app directory

import redis.asyncio as redis
from redis.asyncio.connection import ConnectionPool
import os

class RedisPool:
    """Singleton Redis connection pool for optimal performance"""
    _instance = None
    _pool = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(RedisPool, cls).__new__(cls)
        return cls._instance
    
    async def get_pool(self):
        if self._pool is None:
            redis_url = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
            self._pool = ConnectionPool.from_url(
                redis_url,
                max_connections=50,
                decode_responses=True,
                socket_keepalive=True,
                socket_keepalive_options={
                    1: 1,  # TCP_KEEPIDLE
                    2: 1,  # TCP_KEEPINTVL
                    3: 5,  # TCP_KEEPCNT
                },
                retry_on_timeout=True,
                socket_connect_timeout=5,
                socket_timeout=5,
            )
        return self._pool
    
    async def get_client(self):
        pool = await self.get_pool()
        return redis.Redis(connection_pool=pool)
    
    async def close(self):
        if self._pool:
            await self._pool.disconnect()
            self._pool = None

# Usage in app.py:
# from redis_pool import RedisPool
# redis_pool = RedisPool()
# redis_client = await redis_pool.get_client()