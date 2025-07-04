FROM redis/redis-stack-server

# Stay as root to set up directories
USER root

# Check what user exists and create directories with broad permissions
RUN mkdir -p /data /var/log/redis /var/run && \
    chmod -R 777 /data /var/log/redis /var/run

# Copy configuration 
COPY redis.conf /usr/local/etc/redis/redis.conf
RUN chmod 644 /usr/local/etc/redis/redis.conf

# Don't switch users - let the base image handle it
# Set working directory
WORKDIR /data

# Start Redis with the configuration
CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]