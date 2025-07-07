#!/bin/bash
# nginx/entrypoint.sh - Auto-initialize system on startup

set -e

echo "🚀 Starting Devstral Nginx..."

# Start nginx in background
nginx -g "daemon on;"

# Wait for nginx to be ready
echo "⏳ Waiting for nginx to start..."
sleep 5

# Try to reach nginx health check
for i in {1..30}; do
    if curl -f http://localhost/health 2>/dev/null; then
        echo "✅ Nginx is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "⚠️ Nginx health check timeout, continuing anyway..."
        break
    fi
    echo "   Nginx not ready yet... (attempt $i/30)"
    sleep 2
done

# Run initialization
echo "🔧 Running system initialization..."
if INIT_RESPONSE=$(curl -s http://localhost/api/init 2>/dev/null); then
    echo "✅ System initialization completed successfully"
    echo "   Response: $INIT_RESPONSE"
else
    echo "❌ System initialization failed or skipped"
    echo "   Continuing anyway..."
fi

# Stop the background nginx and start in foreground
echo "🎯 Starting nginx in foreground mode..."
nginx -s stop 2>/dev/null || true
sleep 2
exec nginx -g "daemon off;"