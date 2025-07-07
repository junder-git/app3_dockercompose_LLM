#!/bin/bash
# nginx/entrypoint.sh - Auto-initialize system on startup

set -e

echo "🚀 Starting Devstral Nginx..."

# Start nginx in background
nginx -g "daemon on;"

# Wait for nginx to be ready
echo "⏳ Waiting for nginx to start..."
until curl -f http://localhost/health 2>/dev/null; do
    echo "   Nginx not ready yet..."
    sleep 2
done

echo "✅ Nginx is ready!"

# Run initialization
echo "🔧 Running system initialization..."
INIT_RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost/api/init)
INIT_CODE=$(echo "$INIT_RESPONSE" | tail -n1)
INIT_BODY=$(echo "$INIT_RESPONSE" | head -n -1)

if [ "$INIT_CODE" = "200" ]; then
    echo "✅ System initialization completed successfully"
    echo "   Response: $INIT_BODY"
else
    echo "❌ System initialization failed (HTTP $INIT_CODE)"
    echo "   Response: $INIT_BODY"
    echo "   Continuing anyway..."
fi

# Stop the background nginx and start in foreground
echo "🎯 Starting nginx in foreground mode..."
nginx -s stop
sleep 2
exec nginx -g "daemon off;"