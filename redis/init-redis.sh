#!/bin/sh
set -e

echo "🚀 Starting Redis with conditional admin initialization..."

# Load .env if exists
if [ -f "/app/.env" ]; then
  export $(grep -v '^#' /app/.env | xargs)
  echo "✅ Loaded .env file"
fi

echo "🔍 Debug: ADMIN_USERNAME='${ADMIN_USERNAME}'"
echo "🔍 Debug: ADMIN_USER_ID='${ADMIN_USER_ID}'"
echo "🔍 Debug: JWT_SECRET='${JWT_SECRET}'"
echo "🔍 Debug: ADMIN_PASSWORD='${ADMIN_PASSWORD}'"

# Start Redis in background
redis-server --appendonly yes &
REDIS_PID=$!

echo "⏳ Redis server started in background with PID: $REDIS_PID"

# Wait a bit for Redis to fully start
sleep 3

# Generate password hash
ADMIN_PASSWORD_HASH=$(printf '%s%s' "$ADMIN_PASSWORD" "$JWT_SECRET" | openssl dgst -sha256 -hex | awk '{print $2}')
REDIS_PASSWORD_HASH="jwt_secret:${ADMIN_PASSWORD_HASH}"

echo "🔐 Admin password hash generated successfully: ${ADMIN_PASSWORD_HASH}"

# Check if user already exists
USER_EXISTS=$(redis-cli EXISTS "user:${ADMIN_USERNAME}")

if [ "$USER_EXISTS" -eq 1 ]; then
  echo "⚠️  Admin user '${ADMIN_USERNAME}' already exists in Redis. Skipping creation."
else
  echo "✅ Creating admin user '${ADMIN_USERNAME}' in Redis..."
  redis-cli HMSET "user:${ADMIN_USERNAME}" \
    id "$ADMIN_USER_ID" \
    username "$ADMIN_USERNAME" \
    password_hash "$REDIS_PASSWORD_HASH" \
    is_admin "true" \
    is_approved "true" \
    created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "🎉 Admin user created successfully in Redis!"
fi

echo "⏳ Waiting for Redis process (keeps container running)..."
wait $REDIS_PID

#tail -f /dev/null
