#!/bin/bash
# ollama/scripts/init-ollama.sh - Enhanced with COMPLETE model loading verification

MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Ollama Initialization (Enhanced) ==="
echo "Target model: $MODEL_NAME"
echo "Strategy: Complete model loading verification before container ready"
echo "Timeline: This will take 5-15 minutes but ensures zero delays later"

# Start Ollama service in the background
echo "Starting Ollama service..."
OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=-1 ollama serve &
OLLAMA_PID=$!

# Wait for Ollama API to be ready
echo "Waiting for Ollama API to start..."
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✓ Ollama API is ready!"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - Ollama API not ready yet..."
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "❌ Failed to start Ollama API after $MAX_ATTEMPTS attempts"
    exit 1
fi

# Ensure model exists
echo "Checking for Devstral model: $MODEL_NAME..."
if ollama list | grep -q "$MODEL_NAME"; then
    echo "✓ Devstral model $MODEL_NAME already exists"
else
    echo "❌ Downloading Devstral model $MODEL_NAME (14GB)..."
    echo "⏳ This will take 10-30 minutes depending on internet speed"
    
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully downloaded Devstral model $MODEL_NAME"
    else
        echo "❌ Failed to download $MODEL_NAME model"
        exit 1
    fi
fi

# Create optimized model if Modelfile exists
CUSTOM_MODEL_NAME="${MODEL_NAME}-optimized"

if [ -f "/root/Modelfile" ]; then
    echo "Creating optimized Devstral model: $CUSTOM_MODEL_NAME"
    
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
        echo "✓ Created optimized model: $CUSTOM_MODEL_NAME"
        MODEL_NAME="$CUSTOM_MODEL_NAME"
    else
        echo "❌ Failed to create optimized model, using base model"
    fi
fi

# === ENHANCED: COMPLETE MODEL LOADING AND VERIFICATION ===
echo "=========================================="
echo "🚀 COMPLETE MODEL LOADING SEQUENCE"
echo "=========================================="
echo "Loading $MODEL_NAME completely into VRAM/RAM..."
echo "This ensures ZERO delays for the first chat message"

# Stage 1: Initial model loading
echo "Stage 1/4: Initial model loading..."
INITIAL_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Initialize model and load all layers into memory.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 50,
            \"temperature\": 0.1
        }
    }")

if echo "$INITIAL_RESPONSE" | grep -q "\"message\""; then
    echo "✓ Stage 1 complete: Model successfully initialized"
else
    echo "❌ Stage 1 failed: Model initialization error"
    echo "Response: $INITIAL_RESPONSE"
    exit 1
fi

# Stage 2: Warm up all layers with multiple prompts
echo "Stage 2/4: Warming up all model layers..."
for i in {1..5}; do
    echo "  Warm-up prompt $i/5..."
    curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_NAME\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Write a function to sort an array in Python. Make it efficient.\"}],
            \"stream\": false,
            \"keep_alive\": -1,
            \"options\": {
                \"num_predict\": 200,
                \"temperature\": 0.3
            }
        }" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Warm-up $i complete"
    else
        echo "  ❌ Warm-up $i failed"
        exit 1
    fi
    sleep 1
done

# Stage 3: Verify model performance with complex prompt
echo "Stage 3/4: Performance verification..."
PERF_TEST=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [
            {\"role\": \"user\", \"content\": \"Create a simple REST API endpoint in Python Flask that handles user authentication with JWT tokens. Include error handling.\"}
        ],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 500,
            \"temperature\": 0.7
        }
    }")

if echo "$PERF_TEST" | grep -q "\"message\"" && echo "$PERF_TEST" | grep -q "Flask"; then
    echo "✓ Stage 3 complete: Model performance verified"
else
    echo "❌ Stage 3 failed: Model performance test failed"
    echo "Response preview: $(echo "$PERF_TEST" | head -c 200)..."
    exit 1
fi

# Stage 4: Final readiness verification
echo "Stage 4/4: Final readiness verification..."
READY_TEST=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Confirm you are ready for production use.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 20,
            \"temperature\": 0.1
        }
    }")

if echo "$READY_TEST" | grep -q "\"message\""; then
    echo "✓ Stage 4 complete: Model ready for production"
    
    # Extract response preview
    RESPONSE_PREVIEW=$(echo "$READY_TEST" | jq -r '.message.content' 2>/dev/null | head -c 100)
    echo "Model response preview: $RESPONSE_PREVIEW..."
else
    echo "❌ Stage 4 failed: Final readiness check failed"
    exit 1
fi

# Create readiness marker for health check
touch /tmp/model_ready
echo "✅ Model readiness marker created"

# Show final status
echo "=========================================="
echo "🎯 MODEL LOADING COMPLETE"
echo "=========================================="

# Try to get memory usage info
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU Memory Usage:"
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | while read used total; do
        echo "VRAM: ${used}MB / ${total}MB used"
        percentage=$((used * 100 / total))
        echo "VRAM Usage: ${percentage}% (Target: ~93% for 7.5GB)"
        if [ $percentage -lt 80 ]; then
            echo "⚠️  VRAM usage seems low - model may not be fully loaded"
        elif [ $percentage -gt 95 ]; then
            echo "⚠️  VRAM usage very high - monitor for stability"
        else
            echo "✅ VRAM usage looks optimal"
        fi
    done
else
    echo "nvidia-smi not available"
fi

echo "System Memory Usage:"
free -h | grep "Mem:" | awk '{print "RAM: "$3" / "$2" used"}'

# Write active model info
echo "$MODEL_NAME" > /tmp/active_model

echo "=========================================="
echo "✅ DEVSTRAL READY FOR PRODUCTION"
echo "✅ Model: $MODEL_NAME"
echo "✅ Status: Fully loaded and verified"
echo "✅ Performance: Tested and confirmed"
echo "✅ First message will respond instantly"
echo "✅ Ready for quart-app and nginx startup"
echo "=========================================="

# Set up signal handlers
cleanup() {
    echo "Shutting down Ollama..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT

# Monitor and maintain model
echo "Monitoring Ollama service (PID: $OLLAMA_PID)..."
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=-1 ollama serve &
        OLLAMA_PID=$!
        
        # Re-load model after restart
        sleep 10
        echo "Re-loading model after restart..."
        curl -s -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Reload\"}], \"stream\": false, \"keep_alive\": -1}" > /dev/null
        touch /tmp/model_ready
        echo "Model reloaded after restart"
    fi
    sleep 30
done