#!/bin/bash
# ollama/scripts/init-ollama.sh - Simplified for official image compatibility

MODEL_NAME=${OLLAMA_MODEL:-"devstral:24b"}

echo "=== Devstral Ollama Initialization ==="
echo "Base: Official Ollama Image"
echo "Target model: $MODEL_NAME"
echo "====================================="

# Display environment
echo ""
echo "=== Environment Settings ==="
echo "OLLAMA_HOST: $OLLAMA_HOST"
echo "OLLAMA_MLOCK: $OLLAMA_MLOCK"
echo "OLLAMA_MMAP: $OLLAMA_MMAP"
echo "OLLAMA_KEEP_ALIVE: $OLLAMA_KEEP_ALIVE"
echo "OLLAMA_GPU_LAYERS: $OLLAMA_GPU_LAYERS"
echo "OLLAMA_NUM_THREAD: $OLLAMA_NUM_THREAD"
echo "============================"

# GPU detection
echo ""
echo "🔍 GPU Detection..."
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | while IFS=',' read -r name memory; do
        name=$(echo "$name" | xargs)
        memory=$(echo "$memory" | xargs)
        echo "  📱 GPU: $name"
        echo "  💾 VRAM: ${memory}MB"
    done
else
    echo "  💻 No GPU detected - using CPU mode"
fi

# Start Ollama service in background
echo ""
echo "🚀 Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!

# Wait for API to be ready
echo "⏳ Waiting for Ollama API..."
for i in {1..60}; do
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✓ Ollama API is ready!"
        break
    fi
    sleep 2
done

# Check if model exists
echo ""
echo "📦 Checking model: $MODEL_NAME"
if ollama list 2>/dev/null | grep -q "$MODEL_NAME"; then
    echo "✅ Model $MODEL_NAME already exists (using persistent storage)"
else
    echo "📥 Downloading model: $MODEL_NAME"
    echo "⏳ This will take 10-30 minutes..."
    if ollama pull "$MODEL_NAME"; then
        echo "✅ Successfully downloaded $MODEL_NAME"
    else
        echo "❌ Failed to download $MODEL_NAME"
        exit 1
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
        if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile; then
            echo "✅ Created optimized model: $CUSTOM_MODEL_NAME"
            FINAL_MODEL_NAME="$CUSTOM_MODEL_NAME"
        else
            echo "⚠️ Failed to create optimized model, using base model"
        fi
    fi
fi

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
else
    echo "❌ Model test failed"
    exit 1
fi

# Create health markers
echo ""
echo "📋 Creating health markers..."
touch /tmp/model_ready
touch /tmp/model_loaded
touch /tmp/ollama_ready
echo "$FINAL_MODEL_NAME" > /tmp/active_model

# Final status
echo ""
echo "=========================================="
echo "🎯 DEVSTRAL OLLAMA READY"
echo "=========================================="
echo "✅ Model: $FINAL_MODEL_NAME"
echo "✅ API: http://localhost:11434"
echo "✅ Persistent Storage: /home/ollama/.ollama"
echo "✅ Memory Optimization: Enabled"
echo "🚀 Ready for production workloads"
echo "=========================================="

# Keep container running
trap 'echo "Shutting down..."; kill $OLLAMA_PID 2>/dev/null; wait $OLLAMA_PID 2>/dev/null; exit 0' SIGTERM SIGINT

echo "🔄 Monitoring Ollama service..."
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        ollama serve &
        OLLAMA_PID=$!
        sleep 10
        echo "✅ Service restarted"
    fi
    sleep 30
done