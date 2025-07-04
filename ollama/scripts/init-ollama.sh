#!/bin/bash
# ollama/scripts/init-ollama.sh - Complete fixed version with proper mmap handling

MODEL_NAME=$OLLAMA_MODEL

echo "=== Devstral Ollama Initialization ==="
echo "Base: Ubuntu 22.04 + Ollama Install Script"
echo "Target model: $MODEL_NAME"
echo "====================================="

# Display environment with actual values from .env
echo ""
echo "=== Environment Settings ==="
echo "OLLAMA_HOST: $OLLAMA_HOST"
echo "OLLAMA_MLOCK: $OLLAMA_MLOCK"
echo "OLLAMA_MMAP: $OLLAMA_MMAP"
echo "OLLAMA_KEEP_ALIVE: $OLLAMA_KEEP_ALIVE"
echo "OLLAMA_GPU_LAYERS: $OLLAMA_GPU_LAYERS"
echo "OLLAMA_NUM_THREAD: $OLLAMA_NUM_THREAD"
echo "OLLAMA_MODELS: $OLLAMA_MODELS"
echo "OLLAMA_NOPRUNE: $OLLAMA_NOPRUNE"
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

# GPU detection with enhanced output
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

# Pre-start environment check
echo ""
echo "🔧 Pre-start environment verification..."
echo "  • MMAP disabled: $([ "$OLLAMA_MMAP" = "false" ] && echo "✅ YES" || echo "❌ NO - WARNING!")"
echo "  • MLOCK enabled: $([ "$OLLAMA_MLOCK" = "true" ] && echo "✅ YES" || echo "❌ NO - WARNING!")"
echo "  • No pruning: $([ "$OLLAMA_NOPRUNE" = "true" ] && echo "✅ YES" || echo "❌ NO - WARNING!")"

# Start Ollama service with .env settings
echo ""
echo "🚀 Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!
echo "  📝 Ollama PID: $OLLAMA_PID"

# Enhanced API readiness check
echo "⏳ Waiting for Ollama API..."
API_READY=false
for i in {1..60}; do
    if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✓ Ollama API is ready after ${i} attempts!"
        API_READY=true
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo "  ⏰ Still waiting... (${i}s) - Checking process..."
        if ! kill -0 $OLLAMA_PID 2>/dev/null; then
            echo "  ❌ Ollama process died during startup!"
            exit 1
        fi
    fi
    sleep 2
done

if [ "$API_READY" = false ]; then
    echo "❌ Ollama API failed to start within 120 seconds"
    echo "🔍 Checking process status..."
    if kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "  Process is still running, might be slow startup"
        # Try a few more times
        for i in {1..30}; do
            if curl -s --max-time 10 http://localhost:11434/api/tags >/dev/null 2>&1; then
                echo "✓ API finally ready after extended wait!"
                API_READY=true
                break
            fi
            sleep 5
        done
    else
        echo "  Process died, exiting"
        exit 1
    fi
fi

if [ "$API_READY" = false ]; then
    echo "❌ API still not ready, but continuing..."
fi

# Enhanced model management
echo ""
echo "📦 Checking model: $MODEL_NAME"
if ollama list 2>/dev/null | grep -q "$MODEL_NAME"; then
    echo "✅ Model $MODEL_NAME already exists"
    
    # Verify model is working
    echo "🧪 Quick model verification..."
    TEST_OUTPUT=$(timeout 30 ollama run "$MODEL_NAME" "hi" 2>/dev/null || echo "timeout")
    if [[ "$TEST_OUTPUT" != "timeout" ]] && [[ -n "$TEST_OUTPUT" ]]; then
        echo "✅ Model responds correctly"
    else
        echo "⚠️ Model may need re-download or repair"
    fi
else
    echo "📥 Downloading model: $MODEL_NAME"
    echo "⏳ This will take 1-10 minutes depending on your connection..."
    
    # Download with progress monitoring
    if ollama pull "$MODEL_NAME"; then
        echo "✅ Successfully downloaded $MODEL_NAME"
    else
        echo "❌ Failed to download $MODEL_NAME"
        echo "🔧 Trying alternative download method..."
        
        # Alternative: try downloading with explicit registry
        if ollama pull "registry.ollama.ai/$MODEL_NAME"; then
            echo "✅ Successfully downloaded $MODEL_NAME via registry"
        else
            echo "❌ All download methods failed"
            exit 1
        fi
    fi
fi

# Create optimized model if Modelfile exists
FINAL_MODEL_NAME="$MODEL_NAME"
if [ -f "/root/Modelfile" ]; then
    echo ""
    echo "🔧 Creating optimized model..."
    CUSTOM_MODEL_NAME="${MODEL_NAME}-optimized"
    
    if ollama list 2>/dev/null | grep -q "$CUSTOM_MODEL_NAME"; then
        echo "✅ Optimized model already exists: $CUSTOM_MODEL_NAME"
        FINAL_MODEL_NAME="$CUSTOM_MODEL_NAME"
    else
        echo "📄 Creating custom model from Modelfile..."
        if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
            echo "✅ Created optimized model: $CUSTOM_MODEL_NAME"
            FINAL_MODEL_NAME="$CUSTOM_MODEL_NAME"
        else
            echo "⚠️ Failed to create optimized model, using base model"
        fi
    fi
fi

# Preload model for faster first response
echo ""
echo "🎯 Preloading model: $FINAL_MODEL_NAME"
curl -s --max-time 10 -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$FINAL_MODEL_NAME\",
        \"prompt\": \"preload\",
        \"stream\": false,
        \"options\": {\"num_predict\": 1}
    }" >/dev/null 2>&1

# Test the model
echo ""
echo "🧪 Testing model: $FINAL_MODEL_NAME"
TEST_RESPONSE=$(curl -s --max-time 30 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$FINAL_MODEL_NAME\",
        \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Are you ready?\"}],
        \"stream\": false,
        \"options\": {\"num_predict\": 10}
    }")

if echo "$TEST_RESPONSE" | grep -q "\"message\""; then
    echo "✅ Model test successful"
    # Extract and display response
    RESPONSE_TEXT=$(echo "$TEST_RESPONSE" | grep -o '"content":"[^"]*"' | cut -d'"' -f4 | head -1)
    echo "📝 Response: $RESPONSE_TEXT"
else
    echo "❌ Model test failed"
    echo "🔍 Response: $TEST_RESPONSE"
    exit 1
fi

# Create health markers
echo ""
echo "📋 Creating health markers..."
touch /tmp/model_ready
touch /tmp/model_loaded
touch /tmp/ollama_ready
echo "$FINAL_MODEL_NAME" > /tmp/active_model

# Setup health check endpoint
echo ""
echo "🏥 Setting up health check..."
cat > /tmp/health_check.sh << 'EOF'
#!/bin/bash
# Health check script
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
echo "=========================================="
echo "🎯 DEVSTRAL OLLAMA READY"
echo "=========================================="
echo "✅ Model: $FINAL_MODEL_NAME"
echo "✅ API: http://localhost:11434"
echo "✅ Models Dir: $OLLAMA_MODELS"
echo "✅ Health Check: /tmp/health_check.sh"
echo "✅ Memory Optimization: $([ "$OLLAMA_MMAP" = "false" ] && echo "MMAP Disabled" || echo "MMAP Enabled")"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS"
echo "🚀 Ready for production workloads"
echo "=========================================="

# Cleanup function
cleanup() {
    echo ""
    echo "🔄 Shutting down gracefully..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    echo "✅ Shutdown complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Keep container running with health monitoring
echo "🔄 Monitoring Ollama service..."
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        ollama serve &
        OLLAMA_PID=$!
        sleep 10
        echo "✅ Service restarted"
    fi
    
    # Health check every 30 seconds
    if ! /tmp/health_check.sh >/dev/null 2>&1; then
        echo "⚠️ Health check failed, service may be unhealthy"
    fi
    
    sleep 30
done