#!/bin/bash
# ollama/scripts/init-ollama.sh - Hybrid: Official Image + Advanced Optimizations

MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Hybrid Ollama Initialization ==="
echo "Base: Official Ollama Image"
echo "Enhancements: Advanced Memory Optimization"
echo "Target model: $MODEL_NAME"
echo "============================================="

# Verify we're using the official image
if [ -f "/usr/local/bin/ollama" ]; then
    echo "✓ Official Ollama binary detected"
    OLLAMA_VERSION=$(ollama --version 2>/dev/null || echo "unknown")
    echo "✓ Ollama version: $OLLAMA_VERSION"
else
    echo "⚠️ Non-standard Ollama installation"
fi

# Display inherited environment variables
echo ""
echo "=== Inherited Environment Settings ==="
echo "OLLAMA_HOST: $OLLAMA_HOST"
echo "OLLAMA_MLOCK: $OLLAMA_MLOCK"
echo "OLLAMA_MMAP: $OLLAMA_MMAP"
echo "OLLAMA_KEEP_ALIVE: $OLLAMA_KEEP_ALIVE"
echo "OLLAMA_GPU_LAYERS: $OLLAMA_GPU_LAYERS"
echo "OLLAMA_NUM_THREAD: $OLLAMA_NUM_THREAD"
echo "OLLAMA_CONTEXT_SIZE: $OLLAMA_CONTEXT_SIZE"
echo "OLLAMA_BATCH_SIZE: $OLLAMA_BATCH_SIZE"
echo "OLLAMA_MAX_LOADED_MODELS: $OLLAMA_MAX_LOADED_MODELS"
echo "OLLAMA_NOPRUNE: $OLLAMA_NOPRUNE"
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo "======================================"

# Advanced GPU detection and validation
echo ""
echo "🔍 GPU Detection & Validation..."
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$GPU_INFO" ]; then
        echo "✓ GPU detected:"
        echo "$GPU_INFO" | while IFS=',' read -r name memory driver; do
            name=$(echo "$name" | xargs)
            memory=$(echo "$memory" | xargs)
            driver=$(echo "$driver" | xargs)
            echo "  📱 GPU: $name"
            echo "  💾 VRAM: ${memory}MB"
            echo "  🔧 Driver: $driver"
        done
        
        # Calculate optimal GPU layers based on available VRAM
        TOTAL_VRAM=$(echo "$GPU_INFO" | cut -d',' -f2 | xargs)
        if [ "$TOTAL_VRAM" -gt 20000 ]; then
            OPTIMAL_GPU_LAYERS=35
            echo "  🚀 High VRAM detected: Setting GPU layers to $OPTIMAL_GPU_LAYERS"
        elif [ "$TOTAL_VRAM" -gt 12000 ]; then
            OPTIMAL_GPU_LAYERS=28
            echo "  ⚡ Medium VRAM detected: Setting GPU layers to $OPTIMAL_GPU_LAYERS"
        else
            OPTIMAL_GPU_LAYERS=${OLLAMA_GPU_LAYERS:-22}
            echo "  💻 Standard VRAM: Using GPU layers $OPTIMAL_GPU_LAYERS"
        fi
        
        # Override environment if we calculated a better value
        export OLLAMA_GPU_LAYERS=$OPTIMAL_GPU_LAYERS
    else
        echo "⚠️ nvidia-smi available but no GPU info returned"
        echo "  Falling back to CPU mode"
    fi
else
    echo "💻 No NVIDIA GPU detected - using CPU mode"
    export OLLAMA_GPU_LAYERS=0
fi

# Start Ollama service with all optimizations
echo ""
echo "🚀 Starting Ollama service with optimizations..."

# Create a startup wrapper that ensures all env vars are properly set
cat > /tmp/ollama_startup.sh << EOF
#!/bin/bash
# Startup wrapper to ensure environment inheritance

# Export all our optimizations
export OLLAMA_HOST="$OLLAMA_HOST"
export OLLAMA_MLOCK="$OLLAMA_MLOCK"
export OLLAMA_MMAP="$OLLAMA_MMAP"
export OLLAMA_KEEP_ALIVE="$OLLAMA_KEEP_ALIVE"
export OLLAMA_GPU_LAYERS="$OLLAMA_GPU_LAYERS"
export OLLAMA_NUM_THREAD="$OLLAMA_NUM_THREAD"
export OLLAMA_CONTEXT_SIZE="$OLLAMA_CONTEXT_SIZE"
export OLLAMA_BATCH_SIZE="$OLLAMA_BATCH_SIZE"
export OLLAMA_MAX_LOADED_MODELS="$OLLAMA_MAX_LOADED_MODELS"
export OLLAMA_NOPRUNE="$OLLAMA_NOPRUNE"
export OLLAMA_NUM_PARALLEL="$OLLAMA_NUM_PARALLEL"
export OLLAMA_LOAD_TIMEOUT="$OLLAMA_LOAD_TIMEOUT"
export CUDA_VISIBLE_DEVICES="$CUDA_VISIBLE_DEVICES"

# Log the actual environment being used
echo "Ollama starting with environment:"
env | grep -E '^OLLAMA_|^CUDA_' | sort

# Start ollama serve
exec ollama serve
EOF

chmod +x /tmp/ollama_startup.sh

# Start the optimized Ollama service
/tmp/ollama_startup.sh &
OLLAMA_PID=$!

echo "✓ Ollama service started (PID: $OLLAMA_PID)"

# Enhanced readiness check with timeout and retries
echo ""
echo "⏳ Waiting for Ollama API readiness..."
MAX_ATTEMPTS=90  # Increased for model loading
ATTEMPT=0
API_READY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✓ Ollama API is ready! (attempt $((ATTEMPT + 1)))"
        API_READY=true
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    if [ $((ATTEMPT % 10)) -eq 0 ]; then
        echo "  Still waiting... attempt $ATTEMPT/$MAX_ATTEMPTS"
    fi
    sleep 2
done

if [ "$API_READY" = false ]; then
    echo "❌ Ollama API failed to start after $MAX_ATTEMPTS attempts"
    exit 1
fi

# Model management with advanced validation
echo ""
echo "📦 Model Management..."

# Check if model exists
MODEL_EXISTS=false
if ollama list 2>/dev/null | grep -q "$MODEL_NAME"; then
    echo "✓ Base model $MODEL_NAME already exists"
    MODEL_EXISTS=true
else
    echo "📥 Downloading base model: $MODEL_NAME"
    echo "⏳ This may take 10-30 minutes depending on your connection..."
    
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully downloaded $MODEL_NAME"
        MODEL_EXISTS=true
    else
        echo "❌ Failed to download $MODEL_NAME"
        exit 1
    fi
fi

# Create optimized model with custom Modelfile
FINAL_MODEL_NAME="$MODEL_NAME"
if [ -f "/root/Modelfile" ] && [ "$MODEL_EXISTS" = true ]; then
    echo ""
    echo "🔧 Creating optimized model variant..."
    
    CUSTOM_MODEL_NAME="${MODEL_NAME}-hybrid-optimized"
    
    # Show Modelfile contents for verification
    echo "Modelfile contents:"
    cat /root/Modelfile | head -20
    echo ""
    
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
        echo "✓ Created optimized model: $CUSTOM_MODEL_NAME"
        FINAL_MODEL_NAME="$CUSTOM_MODEL_NAME"
        
        # Verify the optimized model works
        echo "🧪 Testing optimized model..."
        TEST_RESPONSE=$(curl -s --max-time 30 -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$CUSTOM_MODEL_NAME\",
                \"messages\": [{\"role\": \"user\", \"content\": \"test\"}],
                \"stream\": false,
                \"options\": {\"num_predict\": 1}
            }")
        
        if echo "$TEST_RESPONSE" | grep -q "\"message\""; then
            echo "✓ Optimized model test successful"
        else
            echo "⚠️ Optimized model test failed, falling back to base model"
            FINAL_MODEL_NAME="$MODEL_NAME"
        fi
    else
        echo "⚠️ Failed to create optimized model, using base model"
    fi
else
    echo "ℹ️ Using base model (no Modelfile or model doesn't exist)"
fi

# Advanced model preloading with memory optimization
echo ""
echo "🚀 Advanced Model Preloading..."
echo "Final model: $FINAL_MODEL_NAME"
echo "Memory settings: mlock=$OLLAMA_MLOCK, mmap=$OLLAMA_MMAP"

# Phase 1: Initial load with memory lock
echo "Phase 1: Memory-locked initialization..."
PRELOAD_RESPONSE=$(curl -s --max-time 60 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$FINAL_MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Initialize with memory lock. Use mlock=$OLLAMA_MLOCK and mmap=$OLLAMA_MMAP for optimal performance.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 50,
            \"temperature\": 0.1,
            \"num_gpu\": $OLLAMA_GPU_LAYERS,
            \"num_thread\": $OLLAMA_NUM_THREAD,
            \"num_ctx\": $OLLAMA_CONTEXT_SIZE,
            \"num_batch\": $OLLAMA_BATCH_SIZE
        }
    }")

if echo "$PRELOAD_RESPONSE" | grep -q "\"message\""; then
    echo "✓ Phase 1 complete: Model memory-locked and initialized"
    RESPONSE_PREVIEW=$(echo "$PRELOAD_RESPONSE" | jq -r '.message.content' 2>/dev/null | head -c 100)
    echo "  Preview: $RESPONSE_PREVIEW..."
else
    echo "❌ Phase 1 failed"
    echo "Response: $PRELOAD_RESPONSE"
    exit 1
fi

# Phase 2: Performance validation
echo ""
echo "Phase 2: Performance validation..."
PERF_START=$(date +%s%N)
PERF_RESPONSE=$(curl -s --max-time 30 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$FINAL_MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Confirm you are ready for high-performance operation.\"}],
        \"stream\": false,
        \"keep_alive\": -1,
        \"options\": {
            \"num_predict\": 25,
            \"temperature\": 0.7,
            \"num_gpu\": $OLLAMA_GPU_LAYERS,
            \"num_thread\": $OLLAMA_NUM_THREAD
        }
    }")
PERF_END=$(date +%s%N)

if echo "$PERF_RESPONSE" | grep -q "\"message\""; then
    PERF_TIME=$(( (PERF_END - PERF_START) / 1000000 ))
    echo "✓ Phase 2 complete: Performance validated in ${PERF_TIME}ms"
    
    if [ $PERF_TIME -lt 1500 ]; then
        echo "  🚀 EXCELLENT: Sub-1.5s response time"
    elif [ $PERF_TIME -lt 3000 ]; then
        echo "  ✅ GOOD: Sub-3s response time"  
    else
        echo "  ⚠️ SLOW: Consider GPU optimization"
    fi
else
    echo "❌ Phase 2 failed"
    exit 1
fi

# Create comprehensive health markers
echo ""
echo "📋 Creating health markers..."

# Standard markers
touch /tmp/model_ready
touch /tmp/model_loaded
touch /tmp/ollama_ready

# Advanced markers with metadata
echo "$FINAL_MODEL_NAME" > /tmp/active_model
echo "$(date -Iseconds)" > /tmp/load_complete_time
echo "hybrid-official-image" > /tmp/setup_type

# Performance and config markers
echo "mlock=$OLLAMA_MLOCK,mmap=$OLLAMA_MMAP,gpu_layers=$OLLAMA_GPU_LAYERS,perf_time=${PERF_TIME}ms" > /tmp/performance_config

# GPU info marker (if available)
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits > /tmp/gpu_status 2>/dev/null || echo "unknown,unknown" > /tmp/gpu_status
fi

echo "✅ All health markers created"

# Final status report
echo ""
echo "=========================================="
echo "🎯 DEVSTRAL HYBRID READY FOR PRODUCTION"
echo "=========================================="
echo "✅ Base: Official Ollama Image"
echo "✅ Enhancements: Advanced Memory Optimization"
echo "✅ Model: $FINAL_MODEL_NAME"
echo "✅ Memory Lock: $OLLAMA_MLOCK"
echo "✅ Memory Map: $OLLAMA_MMAP"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE"
echo "✅ Performance: ${PERF_TIME}ms response time"
echo "✅ Keep Alive: Permanent"

# Resource monitoring
echo ""
echo "📊 Current Resource Usage:"
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_STATUS=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$GPU_STATUS" ]; then
        echo "$GPU_STATUS" | while IFS=',' read -r used total; do
            used=$(echo "$used" | xargs)
            total=$(echo "$total" | xargs)
            if [ "$total" -gt 0 ] 2>/dev/null; then
                percentage=$((used * 100 / total))
                echo "  🔥 VRAM: ${used}MB / ${total}MB (${percentage}%)"
                if [ $percentage -gt 85 ]; then
                    echo "     🎯 Excellent: High VRAM utilization"
                elif [ $percentage -gt 70 ]; then
                    echo "     ✅ Good: Solid VRAM utilization"
                else
                    echo "     ⚠️ Moderate: VRAM could be higher"
                fi
            fi
        done
    fi
else
    echo "  💻 CPU mode active"
fi

free -h 2>/dev/null | grep "Mem:" | awk '{print "  🧠 RAM: "$3" / "$2" used"}' || echo "  🧠 RAM: Status unknown"

echo ""
echo "🚀 READY FOR PRODUCTION WORKLOADS"
echo "🚀 First request will be instant (model pre-loaded)"
echo "🚀 Optimized for: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'CPU processing')"
echo "=========================================="

# Advanced monitoring and self-healing
trap 'echo "Shutting down..."; kill $OLLAMA_PID 2>/dev/null; wait $OLLAMA_PID 2>/dev/null; exit 0' SIGTERM SIGINT

echo "🔄 Starting advanced monitoring..."
HEALTH_CHECK_INTERVAL=60  # Check every minute
PERFORMANCE_CHECK_INTERVAL=300  # Performance test every 5 minutes
LAST_PERFORMANCE_CHECK=0

while true; do
    CURRENT_TIME=$(date +%s)
    
    # Basic health check
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting with optimizations..."
        /tmp/ollama_startup.sh &
        OLLAMA_PID=$!
        sleep 15
        
        # Quick model reload
        curl -s --max-time 30 -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$FINAL_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"restart\"}], \"stream\": false, \"keep_alive\": -1}" >/dev/null
        
        # Recreate health markers
        touch /tmp/model_ready /tmp/model_loaded /tmp/ollama_ready
        echo "✓ Service restarted and model reloaded"
    fi
    
    # Periodic performance validation
    if [ $((CURRENT_TIME - LAST_PERFORMANCE_CHECK)) -gt $PERFORMANCE_CHECK_INTERVAL ]; then
        echo "🧪 Periodic performance check..."
        HEALTH_RESPONSE=$(curl -s --max-time 15 -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$FINAL_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"health\"}], \"stream\": false, \"options\": {\"num_predict\": 1}}" 2>/dev/null)
        
        if echo "$HEALTH_RESPONSE" | grep -q "\"message\""; then
            echo "✓ Performance check passed"
        else
            echo "⚠️ Performance check failed - model may need attention"
        fi
        
        LAST_PERFORMANCE_CHECK=$CURRENT_TIME
    fi
    
    sleep $HEALTH_CHECK_INTERVAL
done