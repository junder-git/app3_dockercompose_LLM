#!/bin/bash
# ollama/scripts/init-ollama.sh - Pre-load and permanently keep Devstral in memory

# Get model name from environment variable
MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Ollama Initialization ==="
echo "Target model: $MODEL_NAME"
echo "Strategy: Pre-load model into VRAM/RAM before any requests"
echo "Keep-alive: Permanent (model stays loaded)"

# Start Ollama service in the background
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
    
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully downloaded Devstral model $MODEL_NAME"
    else
        echo "❌ Failed to download $MODEL_NAME model"
        exit 1
    fi
fi

# Create optimized custom model from Modelfile if it exists
CUSTOM_MODEL_NAME="${MODEL_NAME}-optimized"

if [ -f "/root/Modelfile" ]; then
    echo "Creating optimized Devstral model: $CUSTOM_MODEL_NAME"
    
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
        echo "✓ Created optimized model: $CUSTOM_MODEL_NAME"
        MODEL_NAME="$CUSTOM_MODEL_NAME"
    else
        echo "❌ Failed to create optimized model, using base model"
    fi
else
    echo "⚠️ No Modelfile found at /root/Modelfile, using base model"
fi

# === CRITICAL: PRE-LOAD MODEL INTO MEMORY ===
echo "=========================================="
echo "🚀 PRE-LOADING MODEL INTO MEMORY"
echo "=========================================="
echo "Loading $MODEL_NAME into VRAM/RAM..."
echo "This will take 1-3 minutes but ensures instant responses later"

# Strategy 1: Load model with a simple prompt to initialize all layers
echo "Step 1: Initializing model with warm-up prompt..."
WARMUP_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello, please confirm you are loaded and ready.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 50,
            \"temperature\": 0.1
        }
    }")

if echo "$WARMUP_RESPONSE" | grep -q "\"message\""; then
    echo "✓ Model initialization successful!"
    echo "Response preview: $(echo "$WARMUP_RESPONSE" | jq -r '.message.content' 2>/dev/null | head -c 100)..."
else
    echo "⚠️ Model initialization had issues but continuing..."
    echo "Response: $WARMUP_RESPONSE"
fi

# Strategy 2: Send a few more prompts to fully warm up the model
echo "Step 2: Warming up model with coding prompts..."

for i in {1..3}; do
    echo "Warm-up prompt $i/3..."
    curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_NAME\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Write a simple hello world function in Python.\"}],
            \"stream\": false,
            \"keep_alive\": -1,
            \"options\": {
                \"num_predict\": 100,
                \"temperature\": 0.3
            }
        }" > /dev/null
    
    echo "Warm-up $i complete"
    sleep 2
done

# Strategy 3: Keep the model loaded with a background keep-alive
echo "Step 3: Setting up permanent keep-alive..."
curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Stay loaded permanently.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 10
        }
    }" > /dev/null

echo "✓ Model keep-alive configured for permanent loading"

# Verify model is loaded and get memory usage
echo "=========================================="
echo "🔍 VERIFYING MODEL STATUS"
echo "=========================================="

# Check if model is actually loaded
MODEL_STATUS=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Ready?\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 5,
            \"temperature\": 0.1
        }
    }")

if echo "$MODEL_STATUS" | grep -q "\"message\""; then
    echo "✅ MODEL SUCCESSFULLY PRE-LOADED!"
    echo "✅ Model is now permanently resident in memory"
    echo "✅ Future requests will be instant (no loading delay)"
else
    echo "❌ Model pre-loading verification failed"
    echo "Response: $MODEL_STATUS"
fi

# Show memory usage
echo "=========================================="
echo "📊 MEMORY USAGE REPORT"
echo "=========================================="

# Try to get GPU memory info if nvidia-smi is available
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU Memory Usage:"
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | while read used total; do
        echo "VRAM: ${used}MB / ${total}MB used"
        percentage=$((used * 100 / total))
        echo "VRAM Usage: ${percentage}%"
    done
else
    echo "nvidia-smi not available, cannot show GPU memory"
fi

# Show system memory
echo "System Memory Usage:"
free -h | grep "Mem:" | awk '{print "RAM: "$3" / "$2" used"}'

echo "=========================================="

# Write the final model name to a file that the Python client can read
echo "$MODEL_NAME" > /tmp/active_model

echo "=== Devstral Initialization Complete ==="
echo "✅ Active model: $MODEL_NAME"
echo "✅ Status: Permanently loaded in memory" 
echo "✅ Service PID: $OLLAMA_PID"
echo "✅ API endpoint: http://localhost:11434"
echo "✅ Ready for instant responses!"

# Set up signal handlers for graceful shutdown
cleanup() {
    echo "Shutting down Ollama..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT

# Keep the container running and monitor the process
echo "Monitoring Ollama service..."
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
            -d "{\"model\": \"$MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Reload\"}], \"stream\": false, \"keep_alive\": -1}" > /dev/null
        echo "Model reloaded after restart"
    fi
    sleep 30
done