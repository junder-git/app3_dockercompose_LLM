#!/bin/bash
# redis/init-redis.sh - Fixed initialization with JWT_SECRET password hashing

set -e

# Get admin credentials from environment variables
ADMIN_USERNAME="${ADMIN_USERNAME}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
ADMIN_USER_ID="${ADMIN_USER_ID:-admin}"
JWT_SECRET="${JWT_SECRET}"

echo "🚀 Starting Redis with conditional admin initialization..."

# Function to hash password using JWT_SECRET (consistent with Lua scripts)
hash_password() {
    local password="$ADMIN_PASSWORD"
    # Use JWT_SECRET as salt for consistency with Lua scripts
    local hash=$(printf '%s%s' "$password" "$JWT_SECRET" | openssl dgst -sha256 -hex | cut -d' ' -f2)
    echo "jwt_secret:${hash}"
}

# Generate admin password hash ONCE and store it
ADMIN_PASSWORD_HASH=$(hash_password "$ADMIN_PASSWORD")
echo "🔐 Generated admin password hash: $ADMIN_PASSWORD_HASH"

# Start Redis server in the background
redis-server /usr/local/etc/redis/redis.conf &
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
  
# Double-check if admin user exists (maybe from previous volume without flag)
if redis-cli EXISTS "user:$ADMIN_USERNAME" | grep -q "1"; then
echo "ℹ️  Admin user '$ADMIN_USERNAME' already exists from previous data"
redis-cli SET "password_hash" "$ADMIN_PASSWORD_HASH"
else
# Create timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Create admin user
redis-cli HMSET "user:$ADMIN_USERNAME" \
    "id" "$ADMIN_USER_ID" \
    "username" "$ADMIN_USERNAME" \
    "password_hash" "$ADMIN_PASSWORD_HASH" \
    "is_admin" "true" \
    "is_approved" "true" \
    "created_at" "$TIMESTAMP"
fi
echo "📝 Creating admin user in Redis with generated password hash..."
echo "🔐 Using password hash: $ADMIN_PASSWORD_HASH"
echo "🎉 Redis initialization complete!"

# Wait for Redis process (keeps container running)
wait $REDIS_PID