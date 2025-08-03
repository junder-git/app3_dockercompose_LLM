#!/bin/sh
set -e

echo "🚀 Starting Redis with conditional admin && 2 guests initialization..."

# Set default values if environment variables are not set
ADMIN_USERNAME=${ADMIN_USERNAME:-"admin1"}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"admin1"}
JWT_SECRET=${JWT_SECRET:-"your-super-secret-jwt-key-change-this-in-production-min-32-chars"}

echo "🔍 Debug Environment Variables:"
echo "   ADMIN_USERNAME=$ADMIN_USERNAME"
echo "   ADMIN_PASSWORD=$ADMIN_PASSWORD"
echo "   JWT_SECRET=$JWT_SECRET" # Only show first 20 chars for security

# Start Redis server in background
echo "📦 Starting Redis server..."
redis-server /usr/local/etc/redis/redis.conf &
REDIS_PID=$!
echo "⏳ Redis server started with PID: $REDIS_PID"

# Wait for Redis to be ready
echo "🔄 Waiting for Redis to be ready..."
sleep 3

# Test Redis connection
echo "🧪 Testing Redis connection..."
redis-cli ping
if [ $? -ne 0 ]; then
    echo "❌ Redis connection failed!"
    exit 1
fi
echo "✅ Redis is ready!"

# Generate password hashes
echo "🔐 Generating password hashes..."
ADMIN_PASSWORD_HASH=$(printf '%s%s' "$ADMIN_PASSWORD" "$JWT_SECRET" | openssl dgst -sha256 -hex | awk '{print $2}')
GUEST_1_PASSWORD_HASH=$(printf '%s%s' 'nkcukfulnckfckufnckdgjvjgv' "$JWT_SECRET" | openssl dgst -sha256 -hex | awk '{print $2}')

echo "   Admin hash: $ADMIN_PASSWORD_HASH"
echo "   Guest1 hash: $GUEST_1_PASSWORD_HASH..."

# Function to create or update user
create_or_update_user() {
    local username=$1
    local password_hash=$2
    local user_type=$3
    local user_key="username:$username"
    
    echo "👤 Processing user: $username"
    
    # Always delete and recreate to ensure clean data
    redis-cli DEL "$user_key"
    
    # Create user with clean field names (no colons)
    redis-cli HMSET "$user_key" \
        username "$username" \
        password_hash "$password_hash" \
        user_type "$user_type" \
        created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        created_ip "127.0.0.1" \
        last_active "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Verify creation
    local exists=$(redis-cli EXISTS "$user_key")
    if [ "$exists" -eq 1 ]; then
        echo "✅ User $username created successfully"
        echo "🔍 Verification:"
        redis-cli HGETALL "$user_key"
    else
        echo "❌ Failed to create user $username"
        return 1
    fi
}

# Create admin user
echo "🔧 Creating admin user..."
create_or_update_user "$ADMIN_USERNAME" "$ADMIN_PASSWORD_HASH" "is_admin"

# Create guest users
echo "🔧 Creating guest users..."
create_or_update_user "guest_user_1" "$GUEST_1_PASSWORD_HASH" "is_guest"

# Final verification
echo "🔍 Final verification - listing all users:"
redis-cli KEYS "username:*"

echo "🔍 Admin user details:"
redis-cli HGETALL "username:$ADMIN_USERNAME"

# Force save to disk
echo "💾 Forcing Redis save to disk..."
redis-cli BGSAVE

# Test admin login hash generation
echo "🧪 Testing admin hash generation:"
echo "   Expected: $ADMIN_PASSWORD_HASH"
TEST_HASH=$(printf '%s%s' "$ADMIN_PASSWORD" "$JWT_SECRET" | openssl dgst -sha256 -hex | awk '{print $2}')
echo "   Generated: $TEST_HASH"
if [ "$ADMIN_PASSWORD_HASH" = "$TEST_HASH" ]; then
    echo "✅ Hash generation is consistent"
else
    echo "❌ Hash generation mismatch!"
fi

echo "🎉 Redis initialization complete!"
echo "📋 Summary:"
echo "   - Admin user: $ADMIN_USERNAME (password: $ADMIN_PASSWORD)"
echo "   - Guest users: guest_user_1"
echo "   - All users have clean field names (no colons)"
echo "   - Data saved to disk"

echo "⏳ Keeping Redis running..."
wait $REDIS_PID