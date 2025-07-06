# redis/Dockerfile - Redis with HTTP interface

FROM redis/redis-stack-server:latest

# Install Node.js for HTTP wrapper
RUN apt-get update && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy package.json and install dependencies
COPY package.json ./
RUN npm install

# Copy HTTP wrapper
COPY redis-http-wrapper.js ./

# Copy Redis configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Create start script
RUN echo '#!/bin/bash\n\
# Start Redis Stack in background\n\
redis-stack-server /usr/local/etc/redis/redis.conf &\n\
REDIS_PID=$!\n\
\n\
# Wait for Redis to be ready\n\
echo "Waiting for Redis to start..."\n\
while ! redis-cli ping > /dev/null 2>&1; do\n\
    sleep 1\n\
done\n\
echo "Redis started successfully"\n\
\n\
# Start HTTP wrapper\n\
echo "Starting Redis HTTP wrapper..."\n\
REDIS_URL=redis://localhost:6379 HTTP_PORT=8001 node redis-http-wrapper.js &\n\
HTTP_PID=$!\n\
\n\
# Wait for either process to exit\n\
wait $REDIS_PID $HTTP_PID\n\
' > /app/start.sh && chmod +x /app/start.sh

# Expose ports
EXPOSE 6379 8001

# Set proper permissions
RUN mkdir -p /data /var/log/redis && \
    chmod -R 777 /data /var/log/redis

# Start script
CMD ["/app/start.sh"]