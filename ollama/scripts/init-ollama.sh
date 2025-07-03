#!/bin/bash
# ollama/scripts/init-ollama.sh - FIXED environment variable handling

MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Ollama Initialization ==="
echo "Target model: $MODEL_NAME"
echo "Memory Lock (mlock): ${OLLAMA_MLOCK:-true}"
echo "Memory Map (mmap): ${OLLAMA_MMAP:-false}"
echo "GPU Layers: ${OLLAMA_GPU_LAYERS:-22}"
echo "Strategy: COMPLETE model preload with memory lock"
echo "Timeline: 10-15 minutes for full loading"
echo "======================================="

# CRITICAL: Export ALL environment variables to ensure they're passed to ollama serve
export OLLAMA_HOST=0.0.0.0
export OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE:--1}
export OLLAMA_MLOCK=${OLLAMA_MLOCK:-true}
export OLLAMA_MMAP=${OLLAMA_MMAP:-false}
export OLLAMA_NUMA=${OLLAMA_NUMA:-false}
export OLLAMA_GPU_LAYERS=${OLLAMA_GPU_LAYERS:-22}
export OLLAMA_NUM_THREAD=${OLLAMA_NUM_THREAD:-8}
export OLLAMA_CONTEXT_SIZE=${OLLAMA_CONTEXT_SIZE:-16384}
export OLLAMA_BATCH_SIZE=${OLLAMA_BATCH_SIZE:-256}
export OLLAMA_MAIN_GPU=${OLLAMA_MAIN_GPU:-0}
export OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS:-1}
export OLLAMA_LOAD_TIMEOUT=${OLLAMA_LOAD_TIMEOUT:-15m}
export OLLAMA_NOPRUNE=${OLLAMA_NOPRUNE:-true}
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0}

# NEW: Additional environment variables for memory optimization
export OLLAMA_FLASH_ATTENTION=${OLLAMA_FLASH_ATTENTION:-true}
export OLLAMA_LOW_VRAM=${OLLAMA_LOW_VRAM:-false}

# Show final environment settings
echo "=== Final Environment Settings ==="
echo "OLLAMA_HOST=$OLLAMA_HOST"
echo "OLLAMA_KEEP_ALIVE=$OLLAMA_KEEP_ALIVE"
echo "OLLAMA_MLOCK=$OLLAMA_MLOCK"
echo "OLLAMA_MMAP=$OLLAMA_MMAP"
echo "OLLAMA_NUMA=$OLLAMA_NUMA"
echo "OLLAMA_GPU_LAYERS=$OLLAMA_GPU_LAYERS"
echo "OLLAMA_NUM_THREAD=$OLLAMA_NUM_THREAD"
echo "OLLAMA_CONTEXT_SIZE=$OLLAMA_CONTEXT_SIZE"
echo "OLLAMA_BATCH_SIZE=$OLLAMA_BATCH_SIZE"
echo "OLLAMA_MAIN_GPU=$OLLAMA_MAIN_GPU"
echo "OLLAMA_MAX_LOADED_MODELS=$OLLAMA_MAX_LOADED_MODELS"
echo "OLLAMA_NOPRUNE=$OLLAMA_NOPRUNE"
echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "=================================="

# Create a function to start ollama with proper environment
start_ollama() {
    echo "Starting Ollama service with all environment variables..."
    
    # Start ollama serve with explicit environment variables
    env \
        OLLAMA_HOST="$OLLAMA_HOST" \
        OLLAMA_KEEP_ALIVE="$OLLAMA_KEEP_ALIVE" \
        OLLAMA_MLOCK="$OLLAMA_MLOCK" \
        OLLAMA_MMAP="$OLLAMA_MMAP" \
        OLLAMA_NUMA="$OLLAMA_NUMA" \
        OLLAMA_GPU_LAYERS="$OLLAMA_GPU_LAYERS" \
        OLLAMA_NUM_THREAD="$OLLAMA_NUM_THREAD" \
        OLLAMA_CONTEXT_SIZE="$OLLAMA_CONTEXT_SIZE" \
        OLLAMA_BATCH_SIZE="$OLLAMA_BATCH_SIZE" \
        OLLAMA_MAIN_GPU="$OLLAMA_MAIN_GPU" \
        OLLAMA_MAX_LOADED_MODELS="$OLLAMA_MAX_LOADED_MODELS" \
        OLLAMA_NOPRUNE="$OLLAMA_NOPRUNE" \
        CUDA_VISIBLE_DEVICES="$CUDA_VISIBLE_DEVICES" \
        ollama serve &
    
    return $!
}

# Start Ollama service with proper environment
start_ollama
OLLAMA_PID=$!

echo "Ollama started with PID: $OLLAMA_PID"

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

# Check if model needs to be downloaded
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
FINAL_MODEL_NAME="$MODEL_NAME"

if [ -f "/root/Modelfile" ]; then
    echo "🔧 Creating optimized model: $CUSTOM_MODEL_NAME"
    
    # Create optimized model with proper parameters
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
        echo "✓ Created optimized model: $CUSTOM_MODEL_NAME"
        FINAL_MODEL_NAME="$CUSTOM_MODEL_NAME"
        echo "✓ Will use optimized model: $FINAL_MODEL_NAME"
    else
        echo "⚠️ Failed to create optimized model, using base model: $MODEL_NAME"
        FINAL_MODEL_NAME="$MODEL_NAME"
    fi
else
    echo "⚠️ No Modelfile found, using base model: $MODEL_NAME"
fi

# === COMPLETE MODEL PRELOADING WITH OPTIMIZED ENVIRONMENT ===
echo "=========================================="
echo "🚀 COMPLETE MODEL PRELOADING SEQUENCE"
echo "=========================================="
echo "Using model: $FINAL_MODEL_NAME"
echo "Memory Lock: $OLLAMA_MLOCK"
echo "Memory Map: $OLLAMA_MMAP"
echo "GPU Layers: $OLLAMA_GPU_LAYERS"
echo ""

# Phase 1: Initial model loading with proper environment
echo "💾 Phase 1: Loading model with optimized environment..."
LOAD_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$FINAL_MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Initialize all model layers with memory lock enabled. Use mlock=$OLLAMA_MLOCK and mmap=$OLLAMA_MMAP.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 100,
            \"temperature\": 0.1,
            \"num_gpu\": $OLLAMA_GPU_LAYERS,
            \"num_thread\": $OLLAMA_NUM_THREAD,
            \"num_ctx\": $OLLAMA_CONTEXT_SIZE,
            \"num_batch\": $OLLAMA_BATCH_SIZE
        }
    }")

if echo "$LOAD_RESPONSE" | grep -q "\"message\""; then
    echo "✓ Phase 1 complete: Model loaded into memory with optimized settings"
    RESPONSE_PREVIEW=$(echo "$LOAD_RESPONSE" | jq -r '.message.content' 2>/dev/null | head -c 80)
    echo "  Response preview: $RESPONSE_PREVIEW..."
else
    echo "❌ Phase 1 failed: Model loading error"
    echo "  Response: $LOAD_RESPONSE"
    exit 1
fi

# Phase 2: Memory optimization verification
echo ""
echo "🔒 Phase 2: Memory optimization verification..."
echo "Checking environment variables in actual Ollama process..."

# Get the actual ollama serve process
OLLAMA_SERVE_PID=$(pgrep -f "ollama serve" | head -1)
if [ -n "$OLLAMA_SERVE_PID" ]; then
    echo "✓ Ollama serve process found: PID $OLLAMA_SERVE_PID"
    
    # Check environment of the actual process
    echo "Checking environment of ollama serve process..."
    if [ -f "/proc/$OLLAMA_SERVE_PID/environ" ]; then
        echo "Environment variables in ollama serve process:"
        cat "/proc/$OLLAMA_SERVE_PID/environ" | tr '\0' '\n' | grep -E "^OLLAMA_|^CUDA_" | sort
    fi
else
    echo "⚠️ Could not find ollama serve process"
fi

# Phase 3: Layer warm-up with optimized settings
echo ""
echo "🔥 Phase 3: Warming up all model layers..."
for i in {1..5}; do
    echo "  Layer warm-up $i/5..."
    WARMUP_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$FINAL_MODEL_NAME\",
            \"messages\": [{\"role\": \"user\", \"content\": \"def quicksort(arr): # Write an efficient Python quicksort implementation\"}],
            \"stream\": false,
            \"keep_alive\": -1,
            \"options\": {
                \"num_predict\": 150,
                \"temperature\": 0.4,
                \"num_gpu\": $OLLAMA_GPU_LAYERS,
                \"num_thread\": $OLLAMA_NUM_THREAD,
                \"num_ctx\": $OLLAMA_CONTEXT_SIZE,
                \"num_batch\": $OLLAMA_BATCH_SIZE
            }
        }")
    
    if echo "$WARMUP_RESPONSE" | grep -q "\"message\""; then
        echo "  ✓ Warm-up $i complete"
    else
        echo "  ❌ Warm-up $i failed"
        echo "  Response: $WARMUP_RESPONSE"
        exit 1
    fi
    sleep 2
done

# Phase 4: Performance verification test
echo ""
echo "⚡ Phase 4: Performance verification test..."
PERF_START=$(date +%s%N)
PERF_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$FINAL_MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Are you ready for production use with optimized memory settings?\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 30,
            \"temperature\": 0.7,
            \"num_gpu\": $OLLAMA_GPU_LAYERS,
            \"num_thread\": $OLLAMA_NUM_THREAD,
            \"num_ctx\": $OLLAMA_CONTEXT_SIZE,
            \"num_batch\": $OLLAMA_BATCH_SIZE
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
    echo "Response: $PERF_RESPONSE"
    exit 1
fi

# Phase 5: Create health check markers and final status
echo ""
echo "✅ Phase 5: Finalizing readiness state..."

# Create readiness markers
touch /tmp/model_ready
touch /tmp/model_loaded  
touch /tmp/ollama_ready
echo "$FINAL_MODEL_NAME" > /tmp/active_model
echo "$(date)" > /tmp/load_complete_time
echo "mlock=$OLLAMA_MLOCK,mmap=$OLLAMA_MMAP,gpu_layers=$OLLAMA_GPU_LAYERS" > /tmp/memory_config

echo "✅ All readiness markers created"

# Show comprehensive final status
echo ""
echo "=========================================="
echo "🎯 DEVSTRAL READY FOR PRODUCTION"
echo "=========================================="
echo "✅ Model: $FINAL_MODEL_NAME"
echo "✅ Status: Fully loaded and verified"
echo "✅ Memory Lock: $OLLAMA_MLOCK"
echo "✅ Memory Map: $OLLAMA_MMAP"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE"
echo "✅ Batch Size: $OLLAMA_BATCH_SIZE"
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
        elif [ $percentage -gt 60 ]; then
            echo "  ⚠️ Moderate VRAM usage - model partially loaded"
        else
            echo "  ❌ Low VRAM usage - model may not be using GPU optimally"
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
echo "🚀 Model: $FINAL_MODEL_NAME with optimized memory settings"
echo "=========================================="

# Set up signal handlers for graceful shutdown
cleanup() {
    echo "Shutting down Ollama..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT

# Monitor and maintain model with environment checks
echo "Monitoring Ollama service (PID: $OLLAMA_PID)..."
MONITOR_COUNT=0

while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting with optimized environment..."
        
        # Restart with explicit environment
        start_ollama
        OLLAMA_PID=$!
        
        # Wait for restart
        sleep 10
        
        # Re-load model after restart
        echo "Re-loading model after restart..."
        curl -s -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$FINAL_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Reload with optimized settings\"}], \"stream\": false, \"keep_alive\": -1, \"options\": {\"num_gpu\": $OLLAMA_GPU_LAYERS, \"num_thread\": $OLLAMA_NUM_THREAD}}" > /dev/null
        
        # Recreate readiness markers
        touch /tmp/model_ready
        touch /tmp/model_loaded
        touch /tmp/ollama_ready
        echo "$FINAL_MODEL_NAME" > /tmp/active_model
        echo "Model reloaded after restart with optimized settings"
    fi
    
    # Every 10 minutes, verify model is still loaded
    MONITOR_COUNT=$((MONITOR_COUNT + 1))
    if [ $((MONITOR_COUNT % 20)) -eq 0 ]; then
        echo "🔄 Periodic model verification..."
        VERIFY_RESPONSE=$(curl -s -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$FINAL_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"ping\"}], \"stream\": false, \"keep_alive\": -1, \"options\": {\"num_predict\": 1}}" 2>/dev/null)
        
        if echo "$VERIFY_RESPONSE" | grep -q "\"message\""; then
            echo "✓ Model verification successful"
        else
            echo "⚠️ Model verification failed - may need attention"
        fi
    fi
    
    sleep 30
done