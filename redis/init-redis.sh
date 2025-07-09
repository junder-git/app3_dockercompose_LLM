#!/bin/bash
# redis/init-redis.sh - Start Redis and initialize admin user

set -e

# Get admin credentials from environment variables
ADMIN_USERNAME="${ADMIN_USERNAME:-admin1}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin1}"
ADMIN_USER_ID="${ADMIN_USER_ID:-admin}"

echo "🚀 Starting Redis with admin initialization..."

# Start Redis server in the background
redis-stack-server /usr/local/etc/redis/redis.conf &
REDIS_PID=$!

echo "⏳ Redis server started with PID: $REDIS_PID"

# Wait for Redis to be ready
echo "⏳ Waiting for Redis to be ready..."
until redis-cli ping > /dev/null 2>&1; do
    sleep 1
done

echo "✅ Redis is ready"

# Initialize admin user
echo "🔧 Initializing admin user: $ADMIN_USERNAME"

# Check if admin user already exists
if redis-cli EXISTS "user:$ADMIN_USERNAME" | grep -q "1"; then
    echo "ℹ️  Admin user '$ADMIN_USERNAME' already exists, skipping creation"
else
    # Create timestamp
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "📝 Creating admin user in Redis..."

    # Create admin user
    redis-cli HMSET "user:$ADMIN_USERNAME" \
        "id" "$ADMIN_USER_ID" \
        "username" "$ADMIN_USERNAME" \
        "password_hash" "$ADMIN_PASSWORD" \
        "is_admin" "true" \
        "is_approved" "true" \
        "created_at" "$TIMESTAMP"

    if [ $? -eq 0 ]; then
        echo "✅ Admin user '$ADMIN_USERNAME' created successfully!"
        echo "🔑 Login credentials:"
        echo "   Username: $ADMIN_USERNAME"
        echo "   Password: $ADMIN_PASSWORD"
    else
        echo "❌ Failed to create admin user"
        exit 1
    fi
fi

echo "🎉 Redis initialization complete!"

# Wait for Redis process (keeps container running)
wait $REDIS_PID