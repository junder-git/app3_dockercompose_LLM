#!/bin/sh
set -e

echo "🚀 Starting Redis with conditional admin && 2 guests initialization..."

# Load .env if exists
if [ -f "/app/.env" ]; then
  export $(grep -v '^#' /app/.env | xargs)
  echo "✅ Loaded .env file"
fi

echo "🔍 Debug: ADMIN_USERNAME=$ADMIN_USERNAME"
echo "🔍 Debug: ADMIN_USER_ID=$ADMIN_USER_ID"
echo "🔍 Debug: JWT_SECRET=$JWT_SECRET"
echo "🔍 Debug: ADMIN_PASSWORD=$ADMIN_PASSWORD"

# Start Redis in background
redis-server --appendonly yes &
REDIS_PID=$!

echo "⏳ Redis server started in background with PID: $REDIS_PID"

# Wait for Redis to fully start
sleep 3




# Generate password hash without prefix
ADMIN_PASSWORD_HASH=$(printf '%s%s' $ADMIN_PASSWORD $JWT_SECRET | openssl dgst -sha256 -hex | awk '{print $2}')
# Generate password hash without prefix
GUEST_1_PASSWORD_HASH=$(printf '%s%s' nkcukfulnckfckufnckdgjvjgv $JWT_SECRET | openssl dgst -sha256 -hex | awk '{print $2}')
# Generate password hash without prefix
GUEST_2_PASSWORD_HASH=$(printf '%s%s' ymbkclhfpbdfbsdfwdsbwfdsbp $JWT_SECRET | openssl dgst -sha256 -hex | awk '{print $2}')
echo "🔐 Admin & guest password hash generated successfully, admin:$ADMIN_PASSWORD_HASH"




# Check if ADMIN user already exists
USER_EXISTS=$(redis-cli EXISTS username:$ADMIN_USERNAME)
if [ $USER_EXISTS -eq 1 ]; then
  echo "⚠️  Admin user $ADMIN_USERNAME already exists in Redis. Skipping creation."
else
  echo "✅ Creating admin user $ADMIN_USERNAME in Redis..."
  redis-cli HMSET username:$ADMIN_USERNAME password_hash:$ADMIN_PASSWORD_HASH user_type:is_admin created_at:$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "🎉 Admin user created successfully in Redis!"
fi

# Check if GUEST_1 user already exists
USER_EXISTS=$(redis-cli EXISTS username:guest_user_1)
if [ $USER_EXISTS -eq 1 ]; then
  echo "⚠️  Guest_1 user guest_user_1 already exists in Redis. Skipping creation."
else
  redis-cli HMSET username:guest_user_1 password_hash:$GUEST_1_PASSWORD_HASH user_type:is_guest created_at:$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "🎉 Guest_1 user created successfully in Redis!"
fi

# Check if GUEST_2 user already exists
USER_EXISTS=$(redis-cli EXISTS "username:guest_user_2")
if [ "$USER_EXISTS" -eq 1 ]; then
  echo "⚠️  Guest_1 user guest_user_2 already exists in Redis. Skipping creation."
else
  redis-cli HMSET username:guest_user_2 password_hash:$GUEST_2_PASSWORD_HASH user_type:is_guest created_at:$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "🎉 Guest_2 user created successfully in Redis!"
fi

echo "⏳ Waiting for Redis process (keeps container running)..."
wait $REDIS_PID
