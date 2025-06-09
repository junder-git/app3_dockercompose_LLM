#!/bin/bash
# open-webui/entrypoint.sh - Custom entrypoint for Open WebUI with model initialization

set -e

echo "=== Open WebUI + Ollama Startup ==="

# Start Ollama in the background
echo "🚀 Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!

# Start Open WebUI in the background
echo "🚀 Starting Open WebUI..."
cd /app
python -m open_webui.main &
WEBUI_PID=$!

# Wait a bit for services to initialize
sleep 10

# Initialize models in the background
echo "📥 Starting model initialization..."
/app/init-models.sh &

# Function to handle shutdown
cleanup() {
    echo "🛑 Shutting down services..."
    kill $OLLAMA_PID 2>/dev/null || true
    kill $WEBUI_PID 2>/dev/null || true
    wait $OLLAMA_PID 2>/dev/null || true
    wait $WEBUI_PID 2>/dev/null || true
    echo "✅ Services stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Monitor services and restart if they die
while true; do
    # Check if Ollama is still running
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        ollama serve &
        OLLAMA_PID=$!
    fi
    
    # Check if Open WebUI is still running
    if ! kill -0 $WEBUI_PID 2>/dev/null; then
        echo "❌ Open WebUI process died, restarting..."
        cd /app
        python -m open_webui.main &
        WEBUI_PID=$!
    fi
    
    sleep 30
done