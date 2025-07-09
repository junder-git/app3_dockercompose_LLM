#!/bin/bash
# redis/init-redis.sh - Fixed initialization with proper persistence handling

set -e

# Get admin credentials from environment variables
ADMIN_USERNAME="${ADMIN_USERNAME:-admin1}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin1}"
ADMIN_USER_ID="${ADMIN_USER_ID:-admin}"

echo "🚀 Starting Redis with conditional admin initialization..."

# Start Redis server in the background
redis-stack-server /usr/local/etc/redis/redis.conf &
REDIS_PID=$!

echo "⏳ Redis server started with PID: $REDIS_PID"

# Wait for Redis to be ready and data to be loaded
echo "⏳ Waiting for Redis to be ready and data to load..."
until redis-cli ping > /dev/null 2>&1; do
    sleep 1
done

# Give Redis extra time to load AOF/RDB data from volume (increased for safety)
sleep 5

echo "✅ Redis is ready"

# Use a file-based flag in the persistent volume instead of Redis key
INIT_FLAG_FILE="/data/devstral_initialized"

# Check if we've already initialized this Redis instance
if [ -f "$INIT_FLAG_FILE" ]; then
    echo "ℹ️  Redis already initialized (flag file found), skipping admin user creation"
    echo "ℹ️  Admin user should already exist from previous initialization"
    
    # Verify admin user still exists
    if redis-cli EXISTS "user:$ADMIN_USERNAME" | grep -q "1"; then
        echo "✅ Admin user '$ADMIN_USERNAME' confirmed to exist"
    else
        echo "⚠️  Admin user missing but init flag exists - recreating admin user"
        # Recreate admin user if missing
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        redis-cli HMSET "user:$ADMIN_USERNAME" \
            "id" "$ADMIN_USER_ID" \
            "username" "$ADMIN_USERNAME" \
            "password_hash" "$ADMIN_PASSWORD" \
            "is_admin" "true" \
            "is_approved" "true" \
            "created_at" "$TIMESTAMP"
        echo "✅ Admin user '$ADMIN_USERNAME' recreated"
    fi
else
    echo "🔧 First-time initialization - checking for admin user: $ADMIN_USERNAME"
    
    # Double-check if admin user exists (maybe from previous volume without flag)
    if redis-cli EXISTS "user:$ADMIN_USERNAME" | grep -q "1"; then
        echo "ℹ️  Admin user '$ADMIN_USERNAME' already exists from previous data"
        # Mark as initialized
        touch "$INIT_FLAG_FILE"
        echo "✅ Initialization flag file created"
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
            
            # Mark as initialized with file flag
            touch "$INIT_FLAG_FILE"
            echo "✅ Initialization flag file created"
        else
            echo "❌ Failed to create admin user"
            exit 1
        fi
    fi
fi

echo "🎉 Redis initialization complete!"

# Wait for Redis process (keeps container running)
wait $REDIS_PID