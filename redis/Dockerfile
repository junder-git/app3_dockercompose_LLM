FROM redis/redis-stack-server

# Create redis user and set up directories with proper permissions
USER root

# Create necessary directories and set permissions
RUN mkdir -p /data /var/log/redis /var/run && \
    chown -R redis:redis /data /var/log/redis /var/run && \
    chmod -R 755 /data /var/log/redis /var/run

# Copy configuration
COPY redis.conf /usr/local/etc/redis/redis.conf
RUN chown redis:redis /usr/local/etc/redis/redis.conf

# Switch to redis user
USER redis

# Set working directory
WORKDIR /data

# Start Redis with the configuration
CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]