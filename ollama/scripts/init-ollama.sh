#!/bin/bash

# Get model name from environment variable
MODEL_NAME=${OLLAMA_MODEL:-"deepseek-coder-v2:16b"}

echo "=== Ollama Initialization ==="
echo "Target model: $MODEL_NAME"

# Start Ollama service in the background and capture PID
echo "Starting Ollama service..."
OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=5m ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✓ Ollama service is ready!"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - Ollama not ready yet, waiting..."
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "❌ Failed to start Ollama after $MAX_ATTEMPTS attempts"
    exit 1
fi

echo "Ollama is ready. Current status:"
curl -s http://localhost:11434/api/tags || echo "Could not fetch model list"

# Check if the base model exists first
echo "Checking for base model $MODEL_NAME..."
if ollama list | grep -q "$MODEL_NAME"; then
    echo "✓ Base model $MODEL_NAME already exists"
else
    echo "❌ Base model $MODEL_NAME not found. Attempting to pull..."
    
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully pulled base model $MODEL_NAME"
    else
        echo "❌ Failed to pull $MODEL_NAME model"
        echo "Available models:"
        ollama list
        echo "⚠️ Will continue with available models, but custom model creation may fail"
    fi
fi

# Try to create a custom model from Modelfile if it exists
CUSTOM_MODEL_NAME="${MODEL_NAME}-custom"

if [ -f "/root/Modelfile" ]; then
    echo "Found Modelfile, creating custom model: $CUSTOM_MODEL_NAME"
    
    # Show the Modelfile content for debugging
    echo "Modelfile content:"
    cat /root/Modelfile
    echo "---"
    
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
        echo "✓ Created custom model: $CUSTOM_MODEL_NAME"
        
        # Test the custom model
        echo "Testing custom model..."
        TEST_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$CUSTOM_MODEL_NAME\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}],
                \"stream\": false,
                \"options\": {\"num_predict\": 10}
            }")
        
        if echo "$TEST_RESPONSE" | grep -q "\"message\""; then
            echo "✓ Custom model test successful"
            MODEL_NAME="$CUSTOM_MODEL_NAME"
            echo "Will use custom model: $MODEL_NAME"
        else
            echo "❌ Custom model test failed"
            echo "Response: $TEST_RESPONSE"
            echo "Will use base model instead"
        fi
    else
        echo "❌ Failed to create custom model, using base model"
        echo "Make sure the Modelfile references an existing model"
    fi
else
    echo "⚠️ No Modelfile found at /root/Modelfile"
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

# Write the final model name to a file that the Python client can read
echo "$MODEL_NAME" > /tmp/active_model

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