# redis/Dockerfile - Simple Redis without HTTP wrapper

FROM redis/redis-stack-server:latest

# Copy configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Create data directory with proper permissions
RUN mkdir -p /data && \
    mkdir -p /var/log/redis && \
    chown -R redis:redis /data && \
    chown -R redis:redis /var/log/redis && \
    chmod 755 /data && \
    chmod 755 /var/log/redis

# Expose Redis port
EXPOSE 6379

# Switch to redis user for security
USER redis

# Start Redis with our config
CMD ["redis-stack-server", "/usr/local/etc/redis/redis.conf"]