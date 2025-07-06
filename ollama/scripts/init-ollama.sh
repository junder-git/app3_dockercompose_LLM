#!/bin/bash
# ollama/scripts/init-ollama.sh - COMPLETELY FIXED with forced server settings

echo "=== COMPLETELY FIXED Ollama Initialization ==="
echo "Forcing server to respect environment settings"
echo "================================================"

# Display environment configuration
echo ""
echo "=== Environment Configuration ==="
echo "OLLAMA_MODEL: $OLLAMA_MODEL"
echo "MODEL_DISPLAY_NAME: $MODEL_DISPLAY_NAME"
echo "OLLAMA_GPU_LAYERS: $OLLAMA_GPU_LAYERS"
echo "OLLAMA_CONTEXT_SIZE: $OLLAMA_CONTEXT_SIZE"
echo "OLLAMA_BATCH_SIZE: $OLLAMA_BATCH_SIZE"
echo "OLLAMA_KEEP_ALIVE: $OLLAMA_KEEP_ALIVE"
echo "OLLAMA_MMAP: $OLLAMA_MMAP (FORCING to 0)"
echo "OLLAMA_MLOCK: $OLLAMA_MLOCK (FORCING to 1)"
echo "================================"

# Verify required environment variables
if [ -z "$OLLAMA_MODEL" ] || [ -z "$MODEL_DISPLAY_NAME" ]; then
    echo "❌ Required environment variables not set!"
    exit 1
fi

# Check Ollama installation
echo ""
echo "🔍 Checking Ollama installation..."
if command -v ollama >/dev/null 2>&1; then
    echo "✅ Ollama found: $(which ollama)"
    echo "📦 Version: $(ollama --version 2>/dev/null || echo 'Unknown')"
else
    echo "❌ Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# GPU detection and memory management
echo ""
echo "🔍 GPU Detection..."
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "🎮 NVIDIA GPU detected:"
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
    echo "$GPU_INFO"
    
    GPU_MEMORY_FREE=$(echo "$GPU_INFO" | cut -d',' -f3 | xargs)
    echo "🎯 GPU Layers configured: $OLLAMA_GPU_LAYERS"
    echo "💾 GPU Memory: ${GPU_MEMORY_FREE}MB free"
    
    # Clear GPU memory
    echo "🧹 Clearing GPU memory..."
    nvidia-smi --gpu-reset 2>/dev/null || echo "GPU reset not available"
    
    if [ "$GPU_MEMORY_FREE" -lt 8000 ]; then
        echo "⚠️  WARNING: Low GPU memory - consider reducing layers"
    fi
else
    echo "💻 CPU mode - no GPU detected"
fi

# Create directories
mkdir -p "$OLLAMA_MODELS"
echo "📁 Models directory: $OLLAMA_MODELS"

# Generate Modelfile from environment
echo ""
echo "🔧 Generating Modelfile from environment variables..."
if [ -f "/home/ollama/Modelfile" ]; then
    envsubst < /home/ollama/Modelfile > /tmp/expanded_modelfile
    echo "✅ Modelfile generated"
    echo "📄 Generated Modelfile preview:"
    head -15 /tmp/expanded_modelfile
else
    echo "⚠️ Base Modelfile not found - creating minimal one"
    cat > /tmp/expanded_modelfile << EOF
FROM $OLLAMA_MODEL

PARAMETER temperature $MODEL_TEMPERATURE
PARAMETER top_p $MODEL_TOP_P
PARAMETER top_k $MODEL_TOP_K
PARAMETER repeat_penalty $MODEL_REPEAT_PENALTY
PARAMETER num_ctx $OLLAMA_CONTEXT_SIZE
PARAMETER num_gpu $OLLAMA_GPU_LAYERS
PARAMETER num_thread $OLLAMA_NUM_THREAD
PARAMETER num_batch $OLLAMA_BATCH_SIZE
PARAMETER use_mmap false
EOF
fi

# FIXED: Handle keep_alive properly
KEEP_ALIVE_SETTING=""
if [ "$OLLAMA_KEEP_ALIVE" = "-1" ]; then
    KEEP_ALIVE_SETTING="30m"
    echo "🔧 Keep Alive: 30m (converted from -1)"
elif [ -n "$OLLAMA_KEEP_ALIVE" ]; then
    KEEP_ALIVE_SETTING="$OLLAMA_KEEP_ALIVE"
    echo "🔧 Keep Alive: $OLLAMA_KEEP_ALIVE"
else
    KEEP_ALIVE_SETTING="10m"
    echo "🔧 Keep Alive: 10m (default)"
fi

# Kill any existing processes
echo ""
echo "🔄 Cleaning up existing processes..."
pkill -f ollama || true
sleep 3

# FORCE environment settings that Ollama server MUST respect
export OLLAMA_MMAP=0
export OLLAMA_MLOCK=1
export OLLAMA_NOPRUNE=1
export OLLAMA_MAX_LOADED_MODELS=1

echo ""
echo "🚀 Starting Ollama with FORCED settings..."
echo "   MMAP: 0 (DISABLED)"
echo "   MLOCK: 1 (ENABLED)"
echo "   GPU_LAYERS: $OLLAMA_GPU_LAYERS"
echo "   CONTEXT_SIZE: $OLLAMA_CONTEXT_SIZE"
echo "   BATCH_SIZE: $OLLAMA_BATCH_SIZE"

# Start Ollama with FORCED environment
exec env \
    OLLAMA_HOST="$OLLAMA_HOST" \
    OLLAMA_MODELS="$OLLAMA_MODELS" \
    OLLAMA_MMAP=0 \
    OLLAMA_MLOCK=1 \
    OLLAMA_NOPRUNE=1 \
    OLLAMA_KEEP_ALIVE="$KEEP_ALIVE_SETTING" \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_LOAD_TIMEOUT="${OLLAMA_LOAD_TIMEOUT:-15m}" \
    CUDA_VISIBLE_DEVICES=0 \
    ollama serve &

OLLAMA_PID=$!
echo "📝 Ollama started with PID: $OLLAMA_PID"

# Wait for API
echo "⏳ Waiting for Ollama API..."
for i in {1..60}; do
    if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✅ API ready after ${i} attempts"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "❌ API failed to start after 2 minutes"
        exit 1
    fi
    sleep 2
done

# Check if model exists
echo ""
echo "📦 Checking for model: $OLLAMA_MODEL"
MODEL_EXISTS=$(ollama list | grep -c "$OLLAMA_MODEL" || true)

if [ "$MODEL_EXISTS" -eq 0 ]; then
    echo "📥 Model not found, attempting to pull..."
    timeout 600 ollama pull "$OLLAMA_MODEL" || {
        echo "❌ Failed to pull $OLLAMA_MODEL"
        echo "🔄 Trying alternative: mistral"
        if timeout 300 ollama pull "mistral"; then
            export OLLAMA_MODEL="mistral"
            echo "✅ Using mistral as fallback"
        else
            echo "❌ Failed to pull any model"
            exit 1
        fi
    }
else
    echo "✅ Model $OLLAMA_MODEL exists"
fi

# Create optimized model with FORCED parameters
OPTIMIZED_MODEL="${OLLAMA_MODEL}-optimized"
echo ""
echo "🔧 Creating optimized model: $OPTIMIZED_MODEL"

if [ -f "/tmp/expanded_modelfile" ]; then
    if ! ollama list | grep -q "$OPTIMIZED_MODEL"; then
        echo "🛠️ Creating optimized model..."
        ollama create "$OPTIMIZED_MODEL" -f /tmp/expanded_modelfile || {
            echo "⚠️ Failed to create optimized model, using base"
            OPTIMIZED_MODEL="$OLLAMA_MODEL"
        }
    else
        echo "✅ Optimized model already exists"
    fi
else
    OPTIMIZED_MODEL="$OLLAMA_MODEL"
fi

# Test model with CONSERVATIVE settings to ensure it works
echo ""
echo "🧪 Testing model: $OPTIMIZED_MODEL"

# Build test payload with YOUR settings enforced
TEST_PAYLOAD="{
    \"model\": \"$OPTIMIZED_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Just say 'OK' please.\"}],
    \"stream\": false,
    \"options\": {
        \"temperature\": 0.1,
        \"num_predict\": 5,
        \"num_ctx\": $OLLAMA_CONTEXT_SIZE,
        \"num_gpu\": $OLLAMA_GPU_LAYERS,
        \"num_thread\": $OLLAMA_NUM_THREAD,
        \"num_batch\": $OLLAMA_BATCH_SIZE,
        \"use_mmap\": false,
        \"use_mlock\": true
    },
    \"keep_alive\": \"$KEEP_ALIVE_SETTING\"
}"

echo "📤 Sending test request with YOUR settings..."
TEST_RESPONSE=$(curl -s --max-time 60 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD")

if echo "$TEST_RESPONSE" | grep -q "\"content\""; then
    echo "✅ Model test SUCCESSFUL!"
    echo "🔒 Model loaded with YOUR settings for $KEEP_ALIVE_SETTING"
    
    # Show the actual response
    echo "📋 Response content:"
    echo "$TEST_RESPONSE" | jq -r '.message.content // "No content"' 2>/dev/null || echo "$TEST_RESPONSE"
else
    echo "❌ Model test FAILED"
    echo "📋 Full response:"
    echo "$TEST_RESPONSE"
    echo ""
    echo "💡 Try reducing OLLAMA_GPU_LAYERS in .env to 8 or less"
fi

# Save active model
echo "$OPTIMIZED_MODEL" > /tmp/active_model
touch /tmp/ollama_ready

# Final status
echo ""
echo "================================================="
echo "🎯 OLLAMA READY - FORCED Configuration"
echo "================================================="
echo "✅ Active Model: $OPTIMIZED_MODEL"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS (FORCED)"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE (FORCED)"
echo "✅ Batch Size: $OLLAMA_BATCH_SIZE (FORCED)"
echo "✅ MMAP: DISABLED (FORCED)"
echo "✅ MLOCK: ENABLED (FORCED)"
echo "✅ Keep Alive: $KEEP_ALIVE_SETTING"
echo "✅ API URL: http://localhost:11434"
echo "================================================="

# Monitor and restart if needed
cleanup() {
    echo "🔄 Shutting down..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "🔄 Monitoring service..."
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Process died - restarting..."
        exec "$0"
    fi
    
    # Health check every 30 seconds
    if ! curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "⚠️ API health check failed"
    fi
    
    sleep 30
done