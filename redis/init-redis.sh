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

# Generate password hash
ADMIN_PASSWORD_HASH=$(printf '%s%s' "$ADMIN_PASSWORD" "$JWT_SECRET" | openssl dgst -sha256 -hex | awk '{print $2}')
REDIS_PASSWORD_HASH="jwt_secret:${ADMIN_PASSWORD_HASH}"

echo "🔐 Admin password hash generated successfully: ${ADMIN_PASSWORD_HASH}"

# Wait for Redis to be up
sleep 3

# Check if user already exists
USER_EXISTS=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EXISTS "user:${ADMIN_USERNAME}")

if [ "$USER_EXISTS" -eq 1 ]; then
  echo "⚠️  Admin user '${ADMIN_USERNAME}' already exists in Redis. Skipping creation."
else
  echo "✅ Creating admin user '${ADMIN_USERNAME}' in Redis..."
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" HMSET "user:${ADMIN_USERNAME}" \
    id "$ADMIN_USER_ID" \
    username "$ADMIN_USERNAME" \
    password_hash "$REDIS_PASSWORD_HASH" \
    is_admin "true" \
    is_approved "true" \
    created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "🎉 Admin user created successfully in Redis!"
fi

echo "⏳ Redis server will now keep running..."
exec redis-server --appendonly yes
