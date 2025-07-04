#!/bin/bash
# ollama/scripts/init-ollama.sh - FIXED: Proper model persistence handling

MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Hybrid Ollama Initialization ==="
echo "Base: Official Ollama Image"
echo "Enhancements: Advanced Memory Optimization + Model Persistence"
echo "Target model: $MODEL_NAME"
echo "============================================="

# CRITICAL: Ensure proper ownership of .ollama directory
echo "🔧 Setting up Ollama directory permissions..."
mkdir -p /home/ollama/.ollama
chown -R ollama:ollama /home/ollama/.ollama
chmod -R 755 /home/ollama/.ollama

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
echo "=== Environment Settings ==="
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
echo "=============================="

# GPU detection and validation
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
        
        export OLLAMA_GPU_LAYERS=$OPTIMAL_GPU_LAYERS
    else
        echo "⚠️ nvidia-smi available but no GPU info returned"
        echo "  Falling back to CPU mode"
    fi
else
    echo "💻 No NVIDIA GPU detected - using CPU mode"
    export OLLAMA_GPU_LAYERS=0
fi

# Create a startup wrapper that ensures all env vars are properly set
echo ""
echo "🚀 Starting Ollama service with optimizations..."

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

# CRITICAL: Switch to ollama user and start service
exec su-exec ollama ollama serve
EOF

chmod +x /tmp/ollama_startup.sh

# Start the optimized Ollama service
/tmp/ollama_startup.sh &
OLLAMA_PID=$!

echo "✓ Ollama service started (PID: $OLLAMA_PID)"

# Enhanced readiness check with timeout and retries
echo ""
echo "⏳ Waiting for Ollama API readiness..."
MAX_ATTEMPTS=90
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

# FIXED: Proper model persistence checking
echo ""
echo "📦 Model Persistence Check..."

# Check volume mount and permissions
echo "🔍 Checking volume mount..."
if [ -d "/home/ollama/.ollama" ]; then
    echo "✓ Model directory exists: /home/ollama/.ollama"
    ls -la /home/ollama/.ollama/ || echo "Directory is empty (first run)"
else
    echo "❌ Model directory not found!"
    exit 1
fi

# Check if model files exist in the persistent volume
MODEL_EXISTS=false
MODEL_FILES_EXIST=false

# Check if model is registered with Ollama
if ollama list 2>/dev/null | grep -q "$MODEL_NAME"; then
    echo "✓ Model $MODEL_NAME is registered with Ollama"
    MODEL_EXISTS=true
else
    echo "ℹ️ Model $MODEL_NAME not found in Ollama registry"
fi

# Check if model files physically exist
if [ -d "/home/ollama/.ollama/models" ] && [ "$(ls -A /home/ollama/.ollama/models 2>/dev/null)" ]; then
    echo "✓ Model files found in persistent storage"
    MODEL_FILES_EXIST=true
    
    # List what's in the models directory
    echo "📂 Contents of model directory:"
    find /home/ollama/.ollama/models -type f -name "*.bin" -o -name "*.gguf" -o -name "*.safetensors" 2>/dev/null | head -5
else
    echo "ℹ️ No model files found in persistent storage (first run)"
fi

# Download model only if it doesn't exist
if [ "$MODEL_EXISTS" = false ] && [ "$MODEL_FILES_EXIST" = false ]; then
    echo ""
    echo "📥 Downloading model: $MODEL_NAME"
    echo "⏳ This may take 10-30 minutes depending on your connection..."
    echo "💾 Model will be saved to persistent volume for future runs"
    
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully downloaded $MODEL_NAME"
        MODEL_EXISTS=true
        
        # Verify the model was actually saved
        if [ -d "/home/ollama/.ollama/models" ] && [ "$(ls -A /home/ollama/.ollama/models 2>/dev/null)" ]; then
            echo "✓ Model files confirmed in persistent storage"
        else
            echo "⚠️ Model downloaded but files not found in expected location"
        fi
    else
        echo "❌ Failed to download $MODEL_NAME"
        exit 1
    fi
elif [ "$MODEL_EXISTS" = false ] && [ "$MODEL_FILES_EXIST" = true ]; then
    echo "🔄 Model files exist but not registered. Attempting to register..."
    # Try to force Ollama to recognize existing files
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully registered existing model"
        MODEL_EXISTS=true
    else
        echo "⚠️ Could not register existing model files"
    fi
else
    echo "✅ Model $MODEL_NAME already available (using persistent storage)"
fi

# Create optimized model with custom Modelfile
FINAL_MODEL_NAME="$MODEL_NAME"
if [ -f "/root/Modelfile" ] && [ "$MODEL_EXISTS" = true ]; then
    echo ""
    echo "🔧 Creating optimized model variant..."
    
    CUSTOM_MODEL_NAME="${MODEL_NAME}-hybrid-optimized"
    
    # Check if optimized model already exists
    if ollama list 2>/dev/null | grep -q "$CUSTOM_MODEL_NAME"; then
        echo "✓ Optimized model already exists: $CUSTOM_MODEL_NAME"
        FINAL_MODEL_NAME="$CUSTOM_MODEL_NAME"
    else
        if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
            echo "✓ Created optimized model: $CUSTOM_MODEL_NAME"
            FINAL_MODEL_NAME="$CUSTOM_MODEL_NAME"
        else
            echo "⚠️ Failed to create optimized model, using base model"
        fi
    fi
else
    echo "ℹ️ Using base model (no Modelfile or model doesn't exist)"
fi

# Test the final model
echo ""
echo "🧪 Testing final model..."
TEST_RESPONSE=$(curl -s --max-time 30 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$FINAL_MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Are you ready?\"}],
        \"stream\": false,
        \"options\": {\"num_predict\": 25}
    }")

if echo "$TEST_RESPONSE" | grep -q "\"message\""; then
    echo "✓ Model test successful"
else
    echo "❌ Model test failed"
    echo "Response: $TEST_RESPONSE"
    exit 1
fi

# Create health markers
echo ""
echo "📋 Creating health markers..."
touch /tmp/model_ready
touch /tmp/model_loaded
touch /tmp/ollama_ready
echo "$FINAL_MODEL_NAME" > /tmp/active_model
echo "$(date -Iseconds)" > /tmp/load_complete_time
echo "hybrid-official-image" > /tmp/setup_type

# Final status report
echo ""
echo "=========================================="
echo "🎯 DEVSTRAL HYBRID READY FOR PRODUCTION"
echo "=========================================="
echo "✅ Base: Official Ollama Image"
echo "✅ Enhancements: Advanced Memory Optimization"
echo "✅ Model: $FINAL_MODEL_NAME"
echo "✅ Persistent Storage: /home/ollama/.ollama"
echo "✅ Memory Lock: $OLLAMA_MLOCK"
echo "✅ Memory Map: $OLLAMA_MMAP"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS"
echo "✅ Keep Alive: Permanent"
echo "✅ Model Files: $(find /home/ollama/.ollama/models -type f 2>/dev/null | wc -l) files"

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
            fi
        done
    fi
fi

free -h 2>/dev/null | grep "Mem:" | awk '{print "  🧠 RAM: "$3" / "$2" used"}' || echo "  🧠 RAM: Status unknown"

echo ""
echo "🚀 READY FOR PRODUCTION WORKLOADS"
echo "🚀 Model persisted and ready for instant responses"
echo "=========================================="

# Keep the container running with proper signal handling
trap 'echo "Shutting down..."; kill $OLLAMA_PID 2>/dev/null; wait $OLLAMA_PID 2>/dev/null; exit 0' SIGTERM SIGINT

echo "🔄 Starting monitoring loop..."
while true; do
    # Basic health check
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        /tmp/ollama_startup.sh &
        OLLAMA_PID=$!
        sleep 15
        
        # Quick model verification
        curl -s --max-time 15 -X POST http://localhost:11434/api/chat \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$FINAL_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"ping\"}], \"stream\": false, \"options\": {\"num_predict\": 1}}" >/dev/null
        
        echo "✓ Service restarted"
    fi
    
    sleep 60
done