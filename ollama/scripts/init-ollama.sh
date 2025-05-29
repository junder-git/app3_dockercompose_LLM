#!/bin/bash

# Get model name from environment variable
MODEL_NAME=${OLLAMA_MODEL:-"deepseek-coder-v2:16b"}

# Start Ollama service in the background
echo "Starting Ollama service..."
ollama serve &

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
while ! curl -s http://localhost:11434/api/tags > /dev/null; do
    echo "Ollama not ready yet, waiting..."
    sleep 2
done

echo "Ollama is ready. Current status:"

# Check if the specified model exists
if ollama list | grep -q "$MODEL_NAME"; then
    echo "✓ $MODEL_NAME model already exists"
else
    echo "❌ $MODEL_NAME model not found. Available models:"
    ollama list
    
    echo "Attempting to pull $MODEL_NAME model..."
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully pulled $MODEL_NAME model"
    else
        echo "❌ Failed to pull $MODEL_NAME model"        
        MODEL_FOUND=false        
        if [ "$MODEL_FOUND" = false ]; then
            echo "❌ Could not find a working model. Listing available models:"
            ollama list
            echo "The service will continue but may not work properly."
        fi
    fi
fi

# Try to create a custom model from Modelfile if it exists
if [ -f "/root/Modelfile" ]; then
    echo "Found Modelfile, creating custom model..."
    CUSTOM_MODEL_NAME="${MODEL_NAME}-custom"
    
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile 2>/dev/null; then
        echo "✓ Created custom model: $CUSTOM_MODEL_NAME"
        MODEL_NAME="$CUSTOM_MODEL_NAME" 
        export OLLAMA_MODEL = MODEL_NAME
    else
        echo "⚠️ Failed to create custom model, using original"
    fi
fi

# List all available models
echo "Final model list:"
ollama list

# Set up signal handlers for graceful shutdown
cleanup() {
    echo "Shutting down Ollama..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT

# Final status check
echo "=== Ollama Initialization Complete ==="
echo "Active model: $MODEL_NAME"
echo "Service PID: $OLLAMA_PID"
echo "API endpoint: http://localhost:11434"
echo "Keeping service running..."

# Keep the container running and monitor the process
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=5m ollama serve &
        OLLAMA_PID=$!
        sleep 5
    fi
    sleep 30
done