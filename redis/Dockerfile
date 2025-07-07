# redis/Dockerfile - Simple Redis without HTTP wrapper

FROM redis/redis-stack-server:latest

# Copy configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Create data directory with proper permissions
# The redis-stack-server image runs as root by default
RUN mkdir -p /data && \
    mkdir -p /var/log/redis && \
    chmod 777 /data && \
    chmod 777 /var/log/redis

# Expose Redis port
EXPOSE 6379

# Start Redis with our config
CMD ["redis-stack-server", "/usr/local/etc/redis/redis.conf"]