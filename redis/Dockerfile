# redis/Dockerfile - Redis with admin user initialization

FROM redis:latest

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Copy configuration and initialization script
COPY redis.conf /usr/local/etc/redis/redis.conf
COPY init-redis.sh /usr/local/bin/init-redis.sh

# Make the init script executable
RUN chmod +x /usr/local/bin/init-redis.sh

# Create data directory with proper permissions
RUN mkdir -p /data && \
    mkdir -p /var/log/redis && \
    chmod 777 /data && \
    chmod 777 /var/log/redis

# Expose Redis port
EXPOSE 6379

# Use our initialization script as entrypoint
ENTRYPOINT ["/usr/local/bin/init-redis.sh"]