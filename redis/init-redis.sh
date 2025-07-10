#!/bin/bash

set -e

# Get admin credentials from environment variables
ADMIN_USERNAME="${ADMIN_USERNAME}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
ADMIN_USER_ID="${ADMIN_USER_ID:-admin}"
JWT_SECRET="${JWT_SECRET}"

echo "🚀 Starting Redis with conditional admin initialization..."

# SECURITY: Never log actual passwords or secrets in production
echo "🔍 Debug: ADMIN_USERNAME='$ADMIN_USERNAME'"
echo "🔍 Debug: ADMIN_USER_ID='$ADMIN_USER_ID'"
echo "🔍 Debug: JWT_SECRET length: ${#JWT_SECRET}"
echo "🔍 Debug: ADMIN_PASSWORD length: ${#ADMIN_PASSWORD}"

# Function to hash password using JWT_SECRET (consistent with Lua scripts)
hash_password() {
    # Check if required variables are set
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        echo "❌ Error: ADMIN_PASSWORD is empty" >&2  # Send to stderr, not stdout
        return 1
    fi
    
    if [[ -z "$JWT_SECRET" ]]; then
        echo "❌ Error: JWT_SECRET is empty" >&2      # Send to stderr, not stdout
        return 1
    fi
    
    # FIXED: Send debug output to stderr, not stdout
    local combined="${ADMIN_PASSWORD}${JWT_SECRET}"
    echo "🔍 Debug: Combined string length: ${#combined}" >&2
    
    # Generate hash
    local hash=$(echo -n "$combined" | openssl dgst -sha256 -hex | cut -d' ' -f2)
    
    if [[ -z "$hash" ]]; then
        echo "❌ Error: Hash generation failed" >&2     # Send to stderr, not stdout
        return 1
    fi
    
    echo "🔍 Debug: Hash generated successfully (length: ${#hash})" >&2
    
    # ONLY the final result should go to stdout
    echo "jwt_secret:${hash}"
}
# Generate admin password hash ONCE and store it
ADMIN_PASSWORD_HASH=$(hash_password)

# SECURITY: Never log the actual hash
echo "🔐 Admin password hash generated successfully (length: ${#ADMIN_PASSWORD_HASH})"

# Start Redis server in the background
redis-server /usr/local/etc/redis/redis.conf &
REDIS_PID=$!

echo "⏳ Redis server started with PID: $REDIS_PID"

# Wait for Redis to be ready and data to be loaded
echo "⏳ Waiting for Redis to be ready and data to load..."
until redis-cli ping > /dev/null 2>&1; do
    sleep 1
done

# Give Redis extra time to load AOF/RDB data from volume
sleep 5

echo "✅ Redis is ready"
  
# Double-check if admin user exists (maybe from previous volume without flag)
if redis-cli EXISTS "user:$ADMIN_USERNAME" | grep -q "1"; then
    echo "ℹ️  Admin user '$ADMIN_USERNAME' already exists from previous data"
    # Update password hash if it changed
    redis-cli HSET "user:$ADMIN_USERNAME" "password_hash" "$ADMIN_PASSWORD_HASH" > /dev/null
    echo "🔐 Admin password hash updated"
else
    # Create timestamp
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "📝 Creating admin user in Redis..."
    
    # Create admin user
    redis-cli HMSET "user:$ADMIN_USERNAME" \
        "id" "$ADMIN_USER_ID" \
        "username" "$ADMIN_USERNAME" \
        "password_hash" "$ADMIN_PASSWORD_HASH" \
        "is_admin" "true" \
        "is_approved" "true" \
        "created_at" "$TIMESTAMP" > /dev/null
    
    echo "✅ Admin user created successfully"
fi

echo "🎉 Redis initialization complete!"

# Wait for Redis process (keeps container running)
wait $REDIS_PID