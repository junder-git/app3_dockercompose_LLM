#!/bin/bash
# ollama/scripts/init-ollama.sh - FIXED with proper duration handling and VRAM management

echo "=== FIXED Ollama Initialization ==="
echo "Handling actual model: Devstral"
echo "================================================"

# Display environment configuration
echo ""
echo "=== Environment Configuration ==="
echo "OLLAMA_MODEL: $OLLAMA_MODEL"
echo "MODEL_DISPLAY_NAME: $MODEL_DISPLAY_NAME"
echo "MODEL_DESCRIPTION: $MODEL_DESCRIPTION"
echo "OLLAMA_GPU_LAYERS: $OLLAMA_GPU_LAYERS"
echo "OLLAMA_CONTEXT_SIZE: $OLLAMA_CONTEXT_SIZE"
echo "OLLAMA_BATCH_SIZE: $OLLAMA_BATCH_SIZE"
echo "OLLAMA_LOAD_TIMEOUT: $OLLAMA_LOAD_TIMEOUT"
echo "OLLAMA_KEEP_ALIVE: $OLLAMA_KEEP_ALIVE"
echo "================================"

# Verify required environment variables
if [ -z "$OLLAMA_MODEL" ] || [ -z "$MODEL_DISPLAY_NAME" ]; then
    echo "❌ Required environment variables not set!"
    echo "Please check your .env file"
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
echo "🔍 GPU Detection and Memory Management..."
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "🎮 NVIDIA GPU detected:"
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
    echo "$GPU_INFO"
    
    # Extract memory info
    GPU_MEMORY_TOTAL=$(echo "$GPU_INFO" | cut -d',' -f2 | xargs)
    GPU_MEMORY_FREE=$(echo "$GPU_INFO" | cut -d',' -f3 | xargs)
    
    echo "🎯 GPU Layers configured: $OLLAMA_GPU_LAYERS"
    echo "💾 GPU Memory: ${GPU_MEMORY_FREE}MB free / ${GPU_MEMORY_TOTAL}MB total"
    
    # Clear GPU memory if needed
    echo "🧹 Clearing GPU memory..."
    nvidia-smi --gpu-reset 2>/dev/null || echo "GPU reset not available"
    
    # Warn if GPU memory might be insufficient
    if [ "$GPU_MEMORY_FREE" -lt 12000 ]; then
        echo "⚠️  WARNING: GPU memory might be insufficient for full model"
        echo "💡 Consider reducing OLLAMA_GPU_LAYERS to 25 or less"
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
    echo "✅ Modelfile generated from environment"
    echo "📄 Generated Modelfile preview:"
    head -15 /tmp/expanded_modelfile
else
    echo "⚠️ Base Modelfile not found"
fi

# FIXED: Handle keep_alive properly with valid duration format
KEEP_ALIVE_SETTING=""
if [ "$OLLAMA_KEEP_ALIVE" = "-1" ]; then
    KEEP_ALIVE_SETTING="30m"  # Use 30 minutes instead of -1
    echo "🔧 Keep Alive: 30m (converted from -1)"
elif [ -n "$OLLAMA_KEEP_ALIVE" ]; then
    KEEP_ALIVE_SETTING="$OLLAMA_KEEP_ALIVE"
    echo "🔧 Keep Alive: $OLLAMA_KEEP_ALIVE"
else
    KEEP_ALIVE_SETTING="10m"  # Default to 10 minutes
    echo "🔧 Keep Alive: 10m (default)"
fi

# Kill any existing Ollama processes
echo ""
echo "🔄 Cleaning up existing processes..."
pkill -f ollama || true
sleep 3

# Start Ollama with conservative settings
echo ""
echo "🚀 Starting Ollama with conservative settings..."
exec env \
    OLLAMA_HOST="$OLLAMA_HOST" \
    OLLAMA_MODELS="$OLLAMA_MODELS" \
    OLLAMA_MMAP="$OLLAMA_MMAP" \
    OLLAMA_MLOCK="$OLLAMA_MLOCK" \
    OLLAMA_NOPRUNE="$OLLAMA_NOPRUNE" \
    OLLAMA_KEEP_ALIVE="$KEEP_ALIVE_SETTING" \
    OLLAMA_MAX_LOADED_MODELS="$OLLAMA_MAX_LOADED_MODELS" \
    OLLAMA_GPU_LAYERS="$OLLAMA_GPU_LAYERS" \
    OLLAMA_NUM_THREAD="$OLLAMA_NUM_THREAD" \
    OLLAMA_CONTEXT_SIZE="$OLLAMA_CONTEXT_SIZE" \
    OLLAMA_BATCH_SIZE="$OLLAMA_BATCH_SIZE" \
    OLLAMA_LOAD_TIMEOUT="${OLLAMA_LOAD_TIMEOUT:-15m}" \
    CUDA_VISIBLE_DEVICES=0 \
    ollama serve &

OLLAMA_PID=$!
echo "📝 Ollama started with PID: $OLLAMA_PID"

# Wait for API with extended timeout
echo "⏳ Waiting for Ollama API (extended timeout)..."
for i in {1..180}; do  # Increased to 6 minutes
    if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✅ API ready after ${i} attempts"
        break
    fi
    if [ $i -eq 180 ]; then
        echo "❌ API failed to start after 6 minutes"
        echo "📋 Checking process status..."
        ps aux | grep ollama || true
        exit 1
    fi
    echo "⏳ Attempt $i/180..."
    sleep 2
done

# Check if model already exists
echo ""
echo "📦 Checking for existing model: $OLLAMA_MODEL"
MODEL_EXISTS=$(ollama list | grep -c "$OLLAMA_MODEL" || true)

if [ "$MODEL_EXISTS" -eq 0 ]; then
    echo "📥 Model not found, checking available models..."
    ollama list
    echo ""
    echo "💡 Available models to pull:"
    echo "   - devstral (if available)"
    echo "   - codestral"
    echo "   - mistral"
    echo ""
    echo "🔄 Attempting to pull model: $OLLAMA_MODEL"
    
    # Try to pull the model with extended timeout
    timeout 900 ollama pull "$OLLAMA_MODEL" || {
        echo "❌ Failed to pull $OLLAMA_MODEL"
        echo "💡 Trying alternative model names..."
        
        # Try alternative names
        for alt_model in "devstral:latest" "codestral" "mistral"; do
            echo "🔄 Trying: $alt_model"
            if timeout 600 ollama pull "$alt_model"; then
                echo "✅ Successfully pulled $alt_model"
                export OLLAMA_MODEL="$alt_model"
                break
            fi
        done
    }
else
    echo "✅ Model $OLLAMA_MODEL already exists"
fi

# Create optimized model if Modelfile exists
OPTIMIZED_MODEL="${OLLAMA_MODEL}-optimized"
echo ""
echo "🔧 Creating optimized model: $OPTIMIZED_MODEL"
if [ -f "/tmp/expanded_modelfile" ]; then
    if ! ollama list | grep -q "$OPTIMIZED_MODEL"; then
        echo "🛠️ Creating optimized model from Modelfile..."
        ollama create "$OPTIMIZED_MODEL" -f /tmp/expanded_modelfile || {
            echo "⚠️ Failed to create optimized model, using base"
            OPTIMIZED_MODEL="$OLLAMA_MODEL"
        }
    else
        echo "✅ Optimized model already exists"
    fi
else
    echo "⚠️ No Modelfile found, using base model"
    OPTIMIZED_MODEL="$OLLAMA_MODEL"
fi

# Test the model with proper timeout and error handling
echo ""
echo "🧪 Testing model: $OPTIMIZED_MODEL"

# Build test payload with conservative settings
TEST_PAYLOAD="{
    \"model\": \"$OPTIMIZED_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello, respond with just 'OK'\"}],
    \"stream\": false,
    \"options\": {
        \"temperature\": 0.1,
        \"num_predict\": 5,
        \"use_mmap\": ${MODEL_USE_MMAP:-false},
        \"num_ctx\": 2048,
        \"num_gpu\": ${OLLAMA_GPU_LAYERS}
    },
    \"keep_alive\": \"$KEEP_ALIVE_SETTING\"
}"

echo "📤 Sending test request..."
echo "🔧 Test payload: $TEST_PAYLOAD"

TEST_RESPONSE=$(curl -s --max-time 120 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD")

if echo "$TEST_RESPONSE" | grep -q "\"content\""; then
    echo "✅ Model test successful"
    echo "🔒 Model loaded in memory for $KEEP_ALIVE_SETTING"
    
    # Show response for verification
    echo "📋 Test response:"
    echo "$TEST_RESPONSE" | jq -r '.message.content // "No content found"' 2>/dev/null || echo "$TEST_RESPONSE"
else
    echo "❌ Model test failed"
    echo "📋 Response: $TEST_RESPONSE"
    echo ""
    echo "💡 Troubleshooting suggestions:"
    echo "   1. Reduce OLLAMA_GPU_LAYERS to 25 or less"
    echo "   2. Restart Docker containers: docker-compose down && docker-compose up"
    echo "   3. Check GPU memory with: nvidia-smi"
    echo "   4. Try a smaller model like 'mistral' first"
fi

# Save active model and mark ready
echo "$OPTIMIZED_MODEL" > /tmp/active_model
touch /tmp/ollama_ready

# Final status
echo ""
echo "================================================="
echo "🎯 OLLAMA READY - Configuration Summary"
echo "================================================="
echo "✅ Active Model: $OPTIMIZED_MODEL"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE"
echo "✅ Batch Size: $OLLAMA_BATCH_SIZE"
echo "✅ Load Timeout: ${OLLAMA_LOAD_TIMEOUT:-15m}"
echo "✅ Keep Alive: $KEEP_ALIVE_SETTING"
echo "✅ Temperature: $MODEL_TEMPERATURE"
echo "✅ Max Tokens: $MODEL_MAX_TOKENS"
echo "================================================="

# Keep running and monitor with better error handling
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
        echo "❌ Process died, checking logs..."
        # Show last few log entries
        tail -20 /var/log/ollama.log 2>/dev/null || echo "No log file found"
        echo "🔄 Restarting..."
        exec "$0"
    fi
    
    # Check API health every 30 seconds
    if ! curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "⚠️ API health check failed, but process is running"
    fi
    
    sleep 30
done