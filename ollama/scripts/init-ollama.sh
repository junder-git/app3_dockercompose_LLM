#!/bin/bash
# ollama/scripts/init-ollama.sh - Environment-Driven Configuration

echo "=== Environment-Driven Ollama Initialization ==="
echo "Base: Ubuntu 22.04 + Ollama Install Script"
echo "All parameters controlled by .env file"
echo "================================================"

# Display current configuration from environment
echo ""
echo "=== Current Configuration ==="
echo "Model: $OLLAMA_MODEL"
echo "Display Name: $MODEL_DISPLAY_NAME"
echo "Description: $MODEL_DESCRIPTION"
echo "GPU Layers: $OLLAMA_GPU_LAYERS"
echo "Context Size: $OLLAMA_CONTEXT_SIZE"
echo "Batch Size: $OLLAMA_BATCH_SIZE"
echo "Max Tokens: $MODEL_MAX_TOKENS"
echo "Timeout: $MODEL_TIMEOUT"
echo "Chat History: $CHAT_HISTORY_LIMIT"
echo "MMAP: $OLLAMA_MMAP"
echo "MLOCK: $OLLAMA_MLOCK"
echo "Temperature: $MODEL_TEMPERATURE"
echo "Top P: $MODEL_TOP_P"
echo "============================"

# Check Ollama installation
echo ""
echo "🔍 Checking Ollama installation..."
if command -v ollama >/dev/null 2>&1; then
    echo "✅ Ollama is installed at: $(which ollama)"
    echo "📦 Version: $(ollama --version 2>/dev/null || echo 'Unknown')"
else
    echo "❌ Ollama not found, attempting installation..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# GPU detection
echo ""
echo "🔍 GPU Detection..."
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "  🎮 NVIDIA GPU detected:"
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null | while IFS=',' read -r name memory_total memory_free; do
        name=$(echo "$name" | xargs)
        memory_total=$(echo "$memory_total" | xargs)
        memory_free=$(echo "$memory_free" | xargs)
        echo "    📱 GPU: $name"
        echo "    💾 Total VRAM: $memory_total"
        echo "    🆓 Free VRAM: $memory_free"
    done
    echo "  🎯 GPU Layers: $OLLAMA_GPU_LAYERS"
else
    echo "  💻 No GPU detected - using CPU mode"
fi

# Ensure models directory exists
mkdir -p "$OLLAMA_MODELS"
echo "📁 Models directory: $OLLAMA_MODELS"

# Pre-start validation
echo ""
echo "🔧 Configuration validation..."
echo "  • Model: $OLLAMA_MODEL"
echo "  • MMAP disabled: $([ "$OLLAMA_MMAP" = "false" ] && echo "✅ YES" || echo "❌ NO")"
echo "  • MLOCK enabled: $([ "$OLLAMA_MLOCK" = "true" ] && echo "✅ YES" || echo "❌ NO")"
echo "  • No pruning: $([ "$OLLAMA_NOPRUNE" = "true" ] && echo "✅ YES" || echo "❌ NO")"
echo "  • GPU layers: $OLLAMA_GPU_LAYERS"
echo "  • Context size: $OLLAMA_CONTEXT_SIZE"

# Generate expanded Modelfile with environment variables
echo ""
echo "🔧 Generating Modelfile with environment variables..."
envsubst < /root/Modelfile > /tmp/expanded_modelfile

echo "✅ Modelfile expanded with current environment variables"

# Start Ollama service
echo ""
echo "🚀 Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!
echo "  📝 Ollama PID: $OLLAMA_PID"

# Wait for API
echo "⏳ Waiting for Ollama API..."
API_READY=false
for i in {1..60}; do
    if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✓ Ollama API is ready after ${i} attempts!"
        API_READY=true
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo "  ⏰ Still waiting... (${i}s)"
        if ! kill -0 $OLLAMA_PID 2>/dev/null; then
            echo "  ❌ Ollama process died during startup!"
            exit 1
        fi
    fi
    sleep 2
done

if [ "$API_READY" = false ]; then
    echo "❌ Ollama API failed to start"
    exit 1
fi

# Check and download base model
echo ""
echo "📦 Checking base model: $OLLAMA_MODEL"
if ollama list 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
    echo "✅ Base model $OLLAMA_MODEL already exists"
else
    echo "📥 Downloading base model: $OLLAMA_MODEL"
    
    # Estimate download time based on model
    if [[ "$OLLAMA_MODEL" == *"1.5b"* ]]; then
        echo "⏳ Estimated download time: 2-5 minutes (~1.5GB)"
    elif [[ "$OLLAMA_MODEL" == *"24b"* ]]; then
        echo "⏳ Estimated download time: 20-45 minutes (~14GB)"
    else
        echo "⏳ Downloading model..."
    fi
    
    if ! ollama pull "$OLLAMA_MODEL"; then
        echo "❌ Failed to download $OLLAMA_MODEL"
        exit 1
    fi
    echo "✅ Successfully downloaded $OLLAMA_MODEL"
fi

# Create optimized model from environment-driven Modelfile
OPTIMIZED_MODEL_NAME="${OLLAMA_MODEL}-env-optimized"
echo ""
echo "🔧 Creating environment-optimized model: $OPTIMIZED_MODEL_NAME"

if ollama list 2>/dev/null | grep -q "$OPTIMIZED_MODEL_NAME"; then
    echo "✅ Environment-optimized model already exists: $OPTIMIZED_MODEL_NAME"
else
    echo "📄 Creating optimized model from environment-driven Modelfile..."
    if ollama create "$OPTIMIZED_MODEL_NAME" -f /tmp/expanded_modelfile; then
        echo "✅ Created environment-optimized model: $OPTIMIZED_MODEL_NAME"
    else
        echo "⚠️ Failed to create optimized model, using base model"
        OPTIMIZED_MODEL_NAME="$OLLAMA_MODEL"
    fi
fi

# Preload model for instant responses
echo ""
echo "🎯 Preloading model for instant responses: $OPTIMIZED_MODEL_NAME"
curl -s --max-time 10 -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$OPTIMIZED_MODEL_NAME\",
        \"prompt\": \"System preload\",
        \"stream\": false,
        \"options\": {\"num_predict\": 1}
    }" >/dev/null 2>&1

# Test model with environment-driven parameters
echo ""
echo "🧪 Testing environment-optimized model: $OPTIMIZED_MODEL_NAME"
TEST_RESPONSE=$(curl -s --max-time 30 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$OPTIMIZED_MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Confirm your configuration: $MODEL_DISPLAY_NAME\"}],
        \"stream\": false,
        \"options\": {
            \"temperature\": $MODEL_TEMPERATURE,
            \"top_p\": $MODEL_TOP_P,
            \"num_predict\": 20
        }
    }")

if echo "$TEST_RESPONSE" | grep -q "\"message\""; then
    echo "✅ Environment-optimized model test successful"
    RESPONSE_TEXT=$(echo "$TEST_RESPONSE" | grep -o '"content":"[^"]*"' | cut -d'"' -f4 | head -1)
    echo "📝 Response: $RESPONSE_TEXT"
else
    echo "❌ Model test failed"
    echo "🔍 Response: $TEST_RESPONSE"
fi

# Create health markers
echo ""
echo "📋 Creating health markers..."
touch /tmp/model_ready
touch /tmp/model_loaded
touch /tmp/ollama_ready
echo "$OPTIMIZED_MODEL_NAME" > /tmp/active_model

# Health check script
cat > /tmp/health_check.sh << 'EOF'
#!/bin/bash
if [ -f /tmp/ollama_ready ] && curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "healthy"
    exit 0
else
    echo "unhealthy"
    exit 1
fi
EOF
chmod +x /tmp/health_check.sh

# Final status
echo ""
echo "================================================="
echo "🎯 ENVIRONMENT-DRIVEN OLLAMA READY"
echo "================================================="
echo "✅ Base Model: $OLLAMA_MODEL"
echo "✅ Optimized Model: $OPTIMIZED_MODEL_NAME"
echo "✅ Display Name: $MODEL_DISPLAY_NAME"
echo "✅ API: http://localhost:11434"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE"
echo "✅ Batch Size: $OLLAMA_BATCH_SIZE"
echo "✅ MMAP: $([ "$OLLAMA_MMAP" = "false" ] && echo "DISABLED" || echo "ENABLED")"
echo "✅ MLOCK: $([ "$OLLAMA_MLOCK" = "true" ] && echo "ENABLED" || echo "DISABLED")"
echo "✅ Temperature: $MODEL_TEMPERATURE"
echo "✅ Top P: $MODEL_TOP_P"
echo "🚀 All parameters controlled by .env file"
echo "================================================="

# Cleanup function
cleanup() {
    echo ""
    echo "🔄 Shutting down gracefully..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    echo "✅ Shutdown complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Keep container running
echo "🔄 Monitoring Ollama service..."
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        ollama serve &
        OLLAMA_PID=$!
        sleep 10
        echo "✅ Service restarted"
    fi
    
    if ! /tmp/health_check.sh >/dev/null 2>&1; then
        echo "⚠️ Health check failed"
    fi
    
    sleep 30
done