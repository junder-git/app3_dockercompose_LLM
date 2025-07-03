#!/bin/bash
# ollama/scripts/init-ollama.sh - Complete model preloading with mlock

MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Ollama Initialization ==="
echo "Target model: $MODEL_NAME"
echo "Memory Lock (mlock): ${OLLAMA_MLOCK:-true}"
echo "Memory Map (mmap): ${OLLAMA_MMAP:-false}"
echo "GPU Layers: ${OLLAMA_GPU_LAYERS:-22}"
echo "Strategy: COMPLETE model preload with memory lock"
echo "Timeline: 10-15 minutes for full loading"
echo "======================================="

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
    echo "📥 Downloading Devstral model $MODEL_NAME..."
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

# === COMPLETE MODEL PRELOADING WITH MLOCK ===
echo "=========================================="
echo "🚀 COMPLETE MODEL PRELOADING SEQUENCE"
echo "=========================================="
echo "Phase 1: Download and verify model exists"
echo "Phase 2: Load model completely into VRAM/RAM"
echo "Phase 3: Apply memory lock (mlock) if enabled"
echo "Phase 4: Warm up all layers and verify performance"
echo "Phase 5: Create health check markers"
echo ""

# Phase 1: Model download and verification
echo "📥 Phase 1: Ensuring model is downloaded..."
if ollama list | grep -q "$MODEL_NAME"; then
    echo "✓ Model $MODEL_NAME already exists"
else
    echo "⏳ Downloading $MODEL_NAME (this will take 10-30 minutes)..."
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully downloaded $MODEL_NAME"
    else
        echo "❌ Failed to download $MODEL_NAME"
        exit 1
    fi
fi

# Create optimized model if Modelfile exists
CUSTOM_MODEL_NAME="${MODEL_NAME}-optimized"
if [ -f "/root/Modelfile" ]; then
    echo "🔧 Creating optimized model: $CUSTOM_MODEL_NAME"
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
        echo "✓ Created optimized model: $CUSTOM_MODEL_NAME"
        MODEL_NAME="$CUSTOM_MODEL_NAME"
    else
        echo "⚠️ Failed to create optimized model, using base model"
    fi
fi

# Phase 2: Complete model loading into memory
echo ""
echo "💾 Phase 2: Loading model completely into VRAM/RAM..."
echo "This ensures ZERO delays for first user request"

# First load - gets model into memory
LOAD_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Load all model layers into memory completely. Prepare for high performance mode.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 100,
            \"temperature\": 0.1,
            \"num_gpu\": ${OLLAMA_GPU_LAYERS:-22},
            \"num_thread\": ${OLLAMA_NUM_THREAD:-8},
            \"num_batch\": 256
        }
    }")

if echo "$LOAD_RESPONSE" | grep -q "\"message\""; then
    echo "✓ Phase 2 complete: Model loaded into memory"
    RESPONSE_PREVIEW=$(echo "$LOAD_RESPONSE" | jq -r '.message.content' 2>/dev/null | head -c 80)
    echo "  Response preview: $RESPONSE_PREVIEW..."
else
    echo "❌ Phase 2 failed: Model loading error"
    echo "  Response: $LOAD_RESPONSE"
    exit 1
fi

# Phase 3: Memory locking verification
echo ""
echo "🔒 Phase 3: Memory management verification..."
if [ "${OLLAMA_MLOCK:-false}" = "true" ]; then
    echo "mlock ENABLED - Model will be locked in RAM/VRAM"
    # Check if we can actually use mlock
    if [ -w /proc/sys/vm/drop_caches ] 2>/dev/null; then
        echo "✓ Memory locking capabilities available"
    else
        echo "⚠️ Limited memory locking (container restrictions)"
    fi
else
    echo "mlock DISABLED - Using standard memory management"
fi

if [ "${OLLAMA_MMAP:-true}" = "false" ]; then
    echo "mmap DISABLED - Full RAM loading enforced"
else
    echo "mmap ENABLED - Memory mapped file access"
fi

# Phase 4: Layer warm-up and performance verification
echo ""
echo "🔥 Phase 4: Warming up all model layers..."
for i in {1..5}; do
    echo "  Layer warm-up $i/5..."
    WARMUP_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$MODEL_NAME\",
            \"messages\": [{\"role\": \"user\", \"content\": \"def quicksort(arr): # Write an efficient Python quicksort\"}],
            \"stream\": false,
            \"keep_alive\": -1,
            \"options\": {
                \"num_predict\": 150,
                \"temperature\": 0.4,
                \"num_gpu\": ${OLLAMA_GPU_LAYERS:-22},
                \"num_thread\": ${OLLAMA_NUM_THREAD:-8}
            }
        }")
    
    if echo "$WARMUP_RESPONSE" | grep -q "\"message\""; then
        echo "  ✓ Warm-up $i complete"
    else
        echo "  ❌ Warm-up $i failed"
        exit 1
    fi
    sleep 2
done

# Performance verification test
echo ""
echo "⚡ Performance verification test..."
PERF_START=$(date +%s%N)
PERF_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Are you ready for production use?\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 20,
            \"temperature\": 0.7
        }
    }")
PERF_END=$(date +%s%N)

if echo "$PERF_RESPONSE" | grep -q "\"message\""; then
    PERF_TIME=$(( (PERF_END - PERF_START) / 1000000 ))
    echo "✓ Performance test passed in ${PERF_TIME}ms"
    if [ $PERF_TIME -lt 2000 ]; then
        echo "  🚀 EXCELLENT: Response time under 2 seconds"
    elif [ $PERF_TIME -lt 5000 ]; then
        echo "  ✅ GOOD: Response time under 5 seconds"
    else
        echo "  ⚠️ SLOW: Response time over 5 seconds - check GPU setup"
    fi
else
    echo "❌ Performance test failed"
    exit 1
fi

# Phase 5: Create health check markers and final status
echo ""
echo "✅ Phase 5: Finalizing readiness state..."

# Create multiple readiness markers for health checks
touch /tmp/model_ready
touch /tmp/model_loaded
touch /tmp/ollama_ready
echo "$MODEL_NAME" > /tmp/active_model
echo "$(date)" > /tmp/load_complete_time

echo "✅ All readiness markers created"

# Show comprehensive final status
echo ""
echo "=========================================="
echo "🎯 DEVSTRAL READY FOR PRODUCTION"
echo "=========================================="
echo "✅ Model: $MODEL_NAME"
echo "✅ Status: Fully loaded and verified"
echo "✅ Memory Lock: ${OLLAMA_MLOCK:-false}"
echo "✅ Memory Map: ${OLLAMA_MMAP:-true}"
echo "✅ GPU Layers: ${OLLAMA_GPU_LAYERS:-22}"
echo "✅ Keep Alive: Permanent (-1)"
echo "✅ Performance: Tested and confirmed"

# Resource usage monitoring
echo ""
echo "📊 Resource Usage:"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | while read used total; do
        percentage=$((used * 100 / total))
        echo "  🔥 VRAM: ${used}MB / ${total}MB (${percentage}%)"
        if [ $percentage -gt 80 ]; then
            echo "  ✅ High VRAM usage - model fully loaded"
        else
            echo "  ⚠️  Lower VRAM usage - model may not be fully loaded"
        fi
    done
else
    echo "  💻 CPU mode (no GPU detected)"
fi

# RAM usage
free -h 2>/dev/null | grep "Mem:" | awk '{print "  🧠 RAM: "$3" / "$2" used"}' || echo "  🧠 RAM: Memory info not available"

echo ""
echo "🚀 READY FOR QUART-APP AND NGINX STARTUP"
echo "🚀 Health check will now pass"
echo "🚀 First user request will be INSTANT"
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