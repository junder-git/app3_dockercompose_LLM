# redis/Dockerfile - Just Redis, no HTTP wrapper

FROM redis/redis-stack-server:latest

# Copy configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Create data directory
RUN mkdir -p /data && chmod 777 /data

# Expose Redis port
EXPOSE 6379

# Start Redis with our config
CMD ["redis-stack-server", "/usr/local/etc/redis/redis.conf"]