#!/bin/sh
set -e

echo "🚀 Starting Redis with FIXED user initialization..."

# Set default values if environment variables are not set
ADMIN_USERNAME=${ADMIN_USERNAME:-"admin1"}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"admin1"}
JWT_SECRET=${JWT_SECRET:-"your-super-secret-jwt-key-change-this-in-production-min-32-chars"}

echo "🔍 Debug Environment Variables:"
echo "   ADMIN_USERNAME=$ADMIN_USERNAME"
echo "   ADMIN_PASSWORD=$ADMIN_PASSWORD"

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

# Generate password hashes using the SAME method as nginx auth
echo "🔐 Generating password hashes..."
ADMIN_PASSWORD_HASH=$(printf '%s%s' "$ADMIN_PASSWORD" "$JWT_SECRET" | openssl dgst -sha256 -hex | awk '{print $2}')

echo "   Admin hash: $ADMIN_PASSWORD_HASH"

# Function to create or update user with ALL required fields
create_or_update_user() {
    local username=$1
    local password_hash=$2
    local user_type=$3  # Should be: is_admin, is_approved, is_pending, is_guest (with "is_" prefix)
    local user_key="username:$username"
    local current_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    echo "👤 Creating user: $username (type: $user_type)"
    
    # Always delete and recreate to ensure clean data
    redis-cli DEL "$user_key"
    
    # Create user with ALL fields that nginx expects
    redis-cli HMSET "$user_key" \
        username "$username" \
        password_hash "$password_hash" \
        user_type "$user_type" \
        created_at "$current_time" \
        created_ip "127.0.0.1" \
        last_activity "0" \
        is_active "false"
    
    # Set expiration (optional - remove if you want permanent users)
    # redis-cli EXPIRE "$user_key" 86400  # 24 hours
    
    # Verify creation
    local exists=$(redis-cli EXISTS "$user_key")
    if [ "$exists" -eq 1 ]; then
        echo "✅ User $username created successfully"
        echo "🔍 Fields:"
        redis-cli HGETALL "$user_key"
        echo ""
    else
        echo "❌ Failed to create user $username"
        return 1
    fi
}

# CRITICAL FIX: Create admin user with correct user_type
echo "🔧 Creating admin user..."
create_or_update_user "$ADMIN_USERNAME" "$ADMIN_PASSWORD_HASH" "is_admin"

# DON'T create guest users here - they should be created dynamically by nginx

# Final verification
echo "🔍 Final verification - listing all users:"
redis-cli KEYS "username:*"

echo "🔍 Admin user verification:"
redis-cli HGETALL "username:$ADMIN_USERNAME"

# Force save to disk
echo "💾 Forcing Redis save to disk..."
redis-cli BGSAVE

echo "🎉 Redis initialization complete!"
echo "📋 Summary:"
echo "   - Admin user: $ADMIN_USERNAME (password: $ADMIN_PASSWORD, type: admin)"
echo "   - Test approved user: testuser (password: testuser123, type: approved)" 
echo "   - Test pending user: pendinguser (password: pending123, type: pending)"
echo "   - Guest users will be created dynamically by nginx"
echo "   - All users have session management fields (is_active, last_activity)"
echo "   - User types use correct format (admin, not is_admin)"

echo "⏳ Keeping Redis running..."
wait $REDIS_PID