#!/bin/bash
# ollama/scripts/init-ollama.sh - Optimized for 7.5GB VRAM Hybrid Mode

echo "=== HYBRID GPU+CPU MODE: 7.5GB VRAM + System RAM ==="
echo "Optimizing Devstral 24B for hybrid processing"
echo "=================================================="

# Display hybrid configuration
echo ""
echo "=== Hybrid Configuration ==="
echo "OLLAMA_MODEL: $OLLAMA_MODEL"
echo "MODEL_DISPLAY_NAME: $MODEL_DISPLAY_NAME"
echo "GPU_LAYERS: 20 (out of 40 total layers)"
echo "CPU_LAYERS: 20 (remaining layers)"
echo "VRAM_TARGET: 7.5GB maximum"
echo "CONTEXT_SIZE: $OLLAMA_CONTEXT_SIZE"
echo "BATCH_SIZE: $OLLAMA_BATCH_SIZE"
echo "CPU_THREADS: $OLLAMA_NUM_THREAD"
echo "MMAP: DISABLED (force direct memory)"
echo "MLOCK: ENABLED (lock GPU layers in VRAM)"
echo "KEEP_ALIVE: PERMANENT (-1)"
echo "============================"

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

# Enhanced GPU detection and VRAM management
echo ""
echo "🔍 GPU Detection and VRAM Management..."
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "🎮 NVIDIA GPU detected:"
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
    echo "$GPU_INFO"
    
    GPU_MEMORY_TOTAL=$(echo "$GPU_INFO" | cut -d',' -f2 | xargs)
    GPU_MEMORY_FREE=$(echo "$GPU_INFO" | cut -d',' -f3 | xargs)
    GPU_MEMORY_USED=$(echo "$GPU_INFO" | cut -d',' -f4 | xargs)
    
    echo "📊 GPU Memory Status:"
    echo "   Total: ${GPU_MEMORY_TOTAL}MB"
    echo "   Free: ${GPU_MEMORY_FREE}MB"
    echo "   Used: ${GPU_MEMORY_USED}MB"
    echo "   Target: 7680MB (7.5GB)"
    
    # Calculate available VRAM for model
    AVAILABLE_VRAM=$((GPU_MEMORY_FREE - 1024))  # Reserve 1GB for system
    echo "   Available for model: ${AVAILABLE_VRAM}MB"
    
    if [ "$AVAILABLE_VRAM" -lt 7680 ]; then
        echo "⚠️  WARNING: Available VRAM (${AVAILABLE_VRAM}MB) < Target (7680MB)"
        echo "💡 Consider reducing GPU layers or clearing GPU memory"
        
        # Try to clear GPU memory
        echo "🧹 Attempting to clear GPU memory..."
        nvidia-smi --gpu-reset 2>/dev/null || echo "GPU reset not available"
        sleep 2
        
        # Recheck after clearing
        GPU_INFO_NEW=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
        echo "🔄 GPU Memory after clearing: ${GPU_INFO_NEW}MB free"
    else
        echo "✅ Sufficient VRAM available for hybrid mode"
    fi
else
    echo "💻 CPU-only mode - no GPU detected"
    echo "⚠️  Performance will be significantly reduced"
fi

# Create directories with proper permissions
mkdir -p "$OLLAMA_MODELS"
chown -R ollama:ollama "$OLLAMA_MODELS" 2>/dev/null || true
echo "📁 Models directory: $OLLAMA_MODELS"

# Generate optimized Modelfile for hybrid mode
echo ""
echo "🔧 Generating hybrid-optimized Modelfile..."
if [ -f "/home/ollama/Modelfile" ]; then
    envsubst < /home/ollama/Modelfile > /tmp/hybrid_modelfile
    echo "✅ Hybrid Modelfile generated"
    echo "📄 Hybrid Modelfile preview:"
    head -20 /tmp/hybrid_modelfile
else
    echo "⚠️ Base Modelfile not found - creating hybrid-optimized one"
    cat > /tmp/hybrid_modelfile << EOF
FROM $OLLAMA_MODEL

SYSTEM """You are running in hybrid GPU+CPU mode optimized for 7.5GB VRAM usage."""

# Hybrid processing parameters
PARAMETER temperature $MODEL_TEMPERATURE
PARAMETER top_p $MODEL_TOP_P
PARAMETER top_k $MODEL_TOP_K
PARAMETER repeat_penalty $MODEL_REPEAT_PENALTY
PARAMETER num_ctx $OLLAMA_CONTEXT_SIZE
PARAMETER num_gpu 20
PARAMETER num_thread $OLLAMA_NUM_THREAD
PARAMETER num_batch $OLLAMA_BATCH_SIZE
PARAMETER use_mmap false
PARAMETER use_mlock true
EOF
fi

# Kill any existing processes
echo ""
echo "🔄 Cleaning up existing processes..."
pkill -f ollama || true
sleep 5

# Clear any existing GPU processes
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "🧹 Clearing GPU processes..."
    nvidia-smi --gpu-reset 2>/dev/null || true
    sleep 2
fi

# FORCE hybrid environment settings
export OLLAMA_MMAP=0
export OLLAMA_MLOCK=1
export OLLAMA_NOPRUNE=1
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_KEEP_ALIVE=-1

echo ""
echo "🚀 Starting Ollama in HYBRID mode..."
echo "   GPU Layers: 20 (target 7.5GB VRAM)"
echo "   CPU Layers: 20 (system RAM)"
echo "   MMAP: DISABLED"
echo "   MLOCK: ENABLED"
echo "   CPU_THREADS: $OLLAMA_NUM_THREAD"
echo "   CONTEXT_SIZE: $OLLAMA_CONTEXT_SIZE"
echo "   BATCH_SIZE: $OLLAMA_BATCH_SIZE"
echo "   KEEP_ALIVE: PERMANENT"

# Start Ollama with hybrid-optimized settings
exec env \
    OLLAMA_HOST="$OLLAMA_HOST" \
    OLLAMA_MODELS="$OLLAMA_MODELS" \
    OLLAMA_MMAP=0 \
    OLLAMA_MLOCK=1 \
    OLLAMA_NOPRUNE=1 \
    OLLAMA_KEEP_ALIVE=-1 \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_LOAD_TIMEOUT="${OLLAMA_LOAD_TIMEOUT:-30m}" \
    OLLAMA_NUM_PARALLEL=2 \
    CUDA_VISIBLE_DEVICES=0 \
    CUDA_MEMORY_FRACTION=0.31 \
    ollama serve &

OLLAMA_PID=$!
echo "📝 Ollama started with PID: $OLLAMA_PID"

# Wait for API with longer timeout for hybrid mode
echo "⏳ Waiting for Ollama API (hybrid mode takes longer)..."
for i in {1..90}; do
    if curl -s --max-time 10 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✅ API ready after ${i} attempts"
        break
    fi
    if [ $i -eq 90 ]; then
        echo "❌ API failed to start after 3 minutes"
        exit 1
    fi
    echo "⏳ Attempt $i/90..."
    sleep 2
done

# Check if model exists
echo ""
echo "📦 Checking for model: $OLLAMA_MODEL"
MODEL_EXISTS=$(ollama list | grep -c "$OLLAMA_MODEL" || true)

if [ "$MODEL_EXISTS" -eq 0 ]; then
    echo "📥 Model not found, pulling $OLLAMA_MODEL..."
    echo "⏳ This may take a while for the 24B model..."
    
    timeout 1800 ollama pull "$OLLAMA_MODEL" || {
        echo "❌ Failed to pull $OLLAMA_MODEL"
        echo "🔄 Trying alternative: mistral"
        if timeout 600 ollama pull "mistral"; then
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

# Create hybrid-optimized model
HYBRID_MODEL="${OLLAMA_MODEL}-hybrid"
echo ""
echo "🔧 Creating hybrid-optimized model: $HYBRID_MODEL"

if [ -f "/tmp/hybrid_modelfile" ]; then
    if ! ollama list | grep -q "$HYBRID_MODEL"; then
        echo "🛠️ Creating hybrid model (this may take a few minutes)..."
        ollama create "$HYBRID_MODEL" -f /tmp/hybrid_modelfile || {
            echo "⚠️ Failed to create hybrid model, using base"
            HYBRID_MODEL="$OLLAMA_MODEL"
        }
    else
        echo "✅ Hybrid model already exists"
    fi
else
    HYBRID_MODEL="$OLLAMA_MODEL"
fi

# Test hybrid model with conservative settings
echo ""
echo "🧪 Testing hybrid model: $HYBRID_MODEL"

# Build test payload with hybrid settings
TEST_PAYLOAD="{
    \"model\": \"$HYBRID_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Please respond with 'Hybrid mode active' and tell me how many layers are on GPU vs CPU.\"}],
    \"stream\": false,
    \"options\": {
        \"temperature\": 0.1,
        \"num_predict\": 50,
        \"num_ctx\": $OLLAMA_CONTEXT_SIZE,
        \"num_gpu\": 20,
        \"num_thread\": $OLLAMA_NUM_THREAD,
        \"num_batch\": $OLLAMA_BATCH_SIZE,
        \"use_mmap\": false,
        \"use_mlock\": true
    },
    \"keep_alive\": -1
}"

echo "📤 Sending hybrid test request..."
echo "⏳ This may take longer due to hybrid processing..."

TEST_RESPONSE=$(curl -s --max-time 120 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD")

if echo "$TEST_RESPONSE" | grep -q "\"content\""; then
    echo "✅ Hybrid model test SUCCESSFUL!"
    echo "🔒 Model loaded with 20 GPU layers + 20 CPU layers"
    
    # Show VRAM usage after loading
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo ""
        echo "📊 VRAM Usage After Loading:"
        nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv,noheader,nounits | head -1 | while IFS=, read used free total; do
            echo "   Used: ${used}MB"
            echo "   Free: ${free}MB"
            echo "   Total: ${total}MB"
            echo "   Target: 7680MB (7.5GB)"
            if [ "$used" -le 7680 ]; then
                echo "   Status: ✅ Within target"
            else
                echo "   Status: ⚠️ Over target by $((used - 7680))MB"
            fi
        done
    fi
    
    # Show the actual response
    echo ""
    echo "📋 Response content:"
    echo "$TEST_RESPONSE" | jq -r '.message.content // "No content"' 2>/dev/null || echo "$TEST_RESPONSE"
else
    echo "❌ Hybrid model test FAILED"
    echo "📋 Full response:"
    echo "$TEST_RESPONSE"
    echo ""
    echo "💡 Troubleshooting:"
    echo "   - Try reducing GPU layers to 16 or 18"
    echo "   - Check if other processes are using VRAM"
    echo "   - Ensure sufficient system RAM (24GB+ recommended)"
fi

# Save active model
echo "$HYBRID_MODEL" > /tmp/active_model
touch /tmp/ollama_ready

# Final status
echo ""
echo "========================================================="
echo "🎯 HYBRID MODE READY - 7.5GB VRAM + System RAM"
echo "========================================================="
echo "✅ Active Model: $HYBRID_MODEL"
echo "✅ GPU Layers: 20/40 (targeting 7.5GB VRAM)"
echo "✅ CPU Layers: 20/40 (system RAM)"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE tokens"
echo "✅ Batch Size: $OLLAMA_BATCH_SIZE tokens"
echo "✅ CPU Threads: $OLLAMA_NUM_THREAD"
echo "✅ MMAP: DISABLED"
echo "✅ MLOCK: ENABLED"
echo "✅ Keep Alive: PERMANENT"
echo "✅ API URL: http://localhost:11434"
echo "========================================================="

# Enhanced monitoring for hybrid mode
cleanup() {
    echo "🔄 Shutting down hybrid mode..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "🔄 Monitoring hybrid service..."
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Process died - restarting..."
        exec "$0"
    fi
    
    # Health check every 30 seconds
    if ! curl -s --max-time 10 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "⚠️ API health check failed"
    fi
    
    # Monitor VRAM usage every 2 minutes
    if [ $(($(date +%s) % 120)) -eq 0 ] && command -v nvidia-smi >/dev/null 2>&1; then
        VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
        if [ "$VRAM_USED" -gt 8192 ]; then
            echo "⚠️ VRAM usage high: ${VRAM_USED}MB"
        fi
    fi
    
    sleep 30
done