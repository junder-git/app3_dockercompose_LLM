# File: Dockerfile
# Directory: /deepseek-coder-setup/redis/

FROM redis:alpine

# Create directory for Redis config and data
RUN mkdir -p /usr/local/etc/redis

# Copy custom redis configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Expose Redis port
EXPOSE 6379

# Set healthcheck
HEALTHCHECK --interval=5s --timeout=3s --retries=5 \
  CMD redis-cli -a "${REDIS_PASSWORD}" ping | grep PONG

# Start Redis with the custom config
CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]