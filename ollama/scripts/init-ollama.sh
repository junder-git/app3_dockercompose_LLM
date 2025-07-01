#!/bin/bash
# ollama/scripts/init-devstral.sh - Download and permanently load Devstral

# Get model name from environment variable
MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Ollama Initialization ==="
echo "Target model: $MODEL_NAME"
echo "GPU VRAM: Configuring for hybrid CPU+GPU setup"
echo "Memory: Keeping model permanently loaded in RAM"

# Start Ollama service in the background and capture PID
echo "Starting Ollama service..."
OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=-1 ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
MAX_ATTEMPTS=60
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

# Check if Devstral model exists
echo "Checking for Devstral model: $MODEL_NAME..."
if ollama list | grep -q "$MODEL_NAME"; then
    echo "✓ Devstral model $MODEL_NAME already exists"
else
    echo "❌ Devstral model $MODEL_NAME not found. Downloading..."
    echo "⚠️  This is a 14GB download and may take 10-30 minutes depending on internet speed"
    
    # Download Devstral model
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully downloaded Devstral model $MODEL_NAME"
    else
        echo "❌ Failed to download $MODEL_NAME model"
        echo "Available models:"
        ollama list
        echo "⚠️ Continuing with available models, but Devstral may not work"
        exit 1
    fi
fi

# Create optimized custom model from Modelfile
CUSTOM_MODEL_NAME="${MODEL_NAME}-optimized"

if [ -f "/root/Modelfile" ]; then
    echo "Creating optimized Devstral model: $CUSTOM_MODEL_NAME"
    
    # Show the Modelfile content for debugging
    echo "Modelfile content:"
    cat /root/Modelfile
    echo "---"
    
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
        echo "✓ Created optimized model: $CUSTOM_MODEL_NAME"
        MODEL_NAME="$CUSTOM_MODEL_NAME"
    else
        echo "❌ Failed to create optimized model, using base model"
    fi
else
    echo "⚠️ No Modelfile found at /root/Modelfile, using base model"
fi

# Pre-load the model into memory and keep it there permanently
echo "Pre-loading Devstral model into memory..."
echo "This may take 1-2 minutes for initial load with hybrid GPU+CPU setup..."

# Send a test prompt to load the model
TEST_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello, confirm you are ready\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 20,
            \"temperature\": 0.1,
            \"num_gpu\": 15,
            \"num_thread\": 8
        }
    }")

if echo "$TEST_RESPONSE" | grep -q "\"message\""; then
    echo "✓ Devstral model loaded successfully and responding"
    echo "✓ Model will remain permanently loaded in memory (OLLAMA_KEEP_ALIVE=-1)"
else
    echo "❌ Devstral model test failed"
    echo "Response: $TEST_RESPONSE"
    echo "⚠️ Model may still work but initial load failed"
fi

# Configure GPU memory and CPU threads for hybrid setup
echo "Configuring hybrid GPU+CPU setup for RTX 3060 Ti..."
echo "- GPU Layers: 15 (fits in 8GB VRAM)"
echo "- CPU Threads: 8 (uses available CPU cores)"
echo "- Memory: Model permanently loaded in RAM"

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

# Write the final model name to a file that the Python client can read
echo "$MODEL_NAME" > /tmp/active_model

echo "=== Devstral Initialization Complete ==="
echo "Active model: $MODEL_NAME"
echo "Service PID: $OLLAMA_PID" 
echo "API endpoint: http://localhost:11434"
echo "Model status: Permanently loaded in memory"
echo "GPU setup: Hybrid CPU+GPU (15 layers on GPU, rest on CPU)"

echo "Keeping Devstral service running..."

# Keep the container running and monitor the process
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=-1 ollama serve &
        OLLAMA_PID=$!
        
        # Re-load the model after restart
        sleep 10
        echo "Re-loading Devstral model after restart..."
        curl -s -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Ready\"}], \"stream\": false, \"keep_alive\": -1}" > /dev/null
    fi
    sleep 30
done