#!/bin/bash
# ollama/scripts/init-ollama.sh - FIXED Keep Alive handling

echo "=== ENVIRONMENT-ONLY Ollama Initialization ==="
echo "All configuration from .env file ONLY"
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
echo "OLLAMA_MMAP: $OLLAMA_MMAP"
echo "OLLAMA_MLOCK: $OLLAMA_MLOCK"
echo "MODEL_USE_MMAP: $MODEL_USE_MMAP"
echo "MODEL_USE_MLOCK: $MODEL_USE_MLOCK"
echo "MODEL_TEMPERATURE: $MODEL_TEMPERATURE"
echo "MODEL_TOP_P: $MODEL_TOP_P"
echo "MODEL_TOP_K: $MODEL_TOP_K"
echo "MODEL_MAX_TOKENS: $MODEL_MAX_TOKENS"
echo "MODEL_TIMEOUT: $MODEL_TIMEOUT"
echo "OLLAMA_KEEP_ALIVE: $OLLAMA_KEEP_ALIVE (permanent if -1)"
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

# GPU detection
echo ""
echo "🔍 GPU Detection..."
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "🎮 NVIDIA GPU detected:"
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null | head -1
    echo "🎯 GPU Layers from ENV: $OLLAMA_GPU_LAYERS"
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

# FIXED: Handle keep_alive properly
KEEP_ALIVE_SETTING=""
if [ "$OLLAMA_KEEP_ALIVE" = "-1" ]; then
    KEEP_ALIVE_SETTING="-1"
    echo "🔧 Keep Alive: PERMANENT (model stays in memory)"
elif [ -n "$OLLAMA_KEEP_ALIVE" ]; then
    KEEP_ALIVE_SETTING="$OLLAMA_KEEP_ALIVE"
    echo "🔧 Keep Alive: $OLLAMA_KEEP_ALIVE"
else
    echo "🔧 Keep Alive: Default (not set)"
fi

# Start Ollama with environment variables
echo ""
echo "🚀 Starting Ollama with environment variables..."
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
        echo "❌ API failed to start"
        exit 1
    fi
    sleep 2
done

# Download base model
echo ""
echo "📦 Checking model: $OLLAMA_MODEL"
if ! ollama list | grep -q "$OLLAMA_MODEL"; then
    echo "📥 Downloading $OLLAMA_MODEL..."
    ollama pull "$OLLAMA_MODEL" || exit 1
fi

# Create optimized model
OPTIMIZED_MODEL="${OLLAMA_MODEL}-optimized"
echo ""
echo "🔧 Creating optimized model: $OPTIMIZED_MODEL"
if [ -f "/tmp/expanded_modelfile" ]; then
    if ! ollama list | grep -q "$OPTIMIZED_MODEL"; then
        ollama create "$OPTIMIZED_MODEL" -f /tmp/expanded_modelfile || {
            echo "⚠️ Failed to create optimized model, using base"
            OPTIMIZED_MODEL="$OLLAMA_MODEL"
        }
    fi
else
    OPTIMIZED_MODEL="$OLLAMA_MODEL"
fi

# FIXED: Test the model with proper keep_alive
echo ""
echo "🧪 Testing model: $OPTIMIZED_MODEL"

# Build test payload with proper keep_alive
TEST_PAYLOAD="{
    \"model\": \"$OPTIMIZED_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}],
    \"stream\": false,
    \"options\": {
        \"temperature\": ${MODEL_TEMPERATURE:-0.7},
        \"use_mmap\": ${MODEL_USE_MMAP:-false},
        \"use_mlock\": ${MODEL_USE_MLOCK:-true}
    }"

# Add keep_alive only if set
if [ -n "$KEEP_ALIVE_SETTING" ]; then
    TEST_PAYLOAD="${TEST_PAYLOAD},\"keep_alive\": \"$KEEP_ALIVE_SETTING\""
fi

TEST_PAYLOAD="${TEST_PAYLOAD}}"

TEST_RESPONSE=$(curl -s --max-time 30 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD")

if echo "$TEST_RESPONSE" | grep -q "\"content\""; then
    echo "✅ Model test successful"
    if [ "$OLLAMA_KEEP_ALIVE" = "-1" ]; then
        echo "🔒 Model loaded PERMANENTLY in memory"
    fi
else
    echo "❌ Model test failed"
    echo "Response: $TEST_RESPONSE"
fi

# Save active model
echo "$OPTIMIZED_MODEL" > /tmp/active_model
touch /tmp/ollama_ready

# Final status
echo ""
echo "================================================="
echo "🎯 OLLAMA READY - Environment Configuration"
echo "================================================="
echo "✅ Active Model: $OPTIMIZED_MODEL"
echo "✅ MMAP: $([ "$OLLAMA_MMAP" = "0" ] && echo "DISABLED" || echo "ENABLED")"
echo "✅ MLOCK: $([ "$OLLAMA_MLOCK" = "1" ] && echo "ENABLED" || echo "DISABLED")"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE"
echo "✅ Temperature: $MODEL_TEMPERATURE"
echo "✅ Max Tokens: $MODEL_MAX_TOKENS"
echo "✅ Keep Alive: $([ "$OLLAMA_KEEP_ALIVE" = "-1" ] && echo "PERMANENT" || echo "$OLLAMA_KEEP_ALIVE")"
echo "✅ All settings from environment variables"
echo "================================================="

# Keep running and monitor
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
        echo "❌ Process died, restarting..."
        exec "$0"
    fi
    sleep 30
done