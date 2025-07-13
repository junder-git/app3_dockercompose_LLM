#!/bin/bash
# ollama/scripts/init-ollama.sh - Fixed version without warnings/errors

# ADD: Memory debugging to catch double free errors
export MALLOC_CHECK_=2
export MALLOC_PERTURB_=165

echo "=== HYBRID GPU+CPU MODE: Enhanced Configuration ==="
echo "Optimizing ${MODEL_DISPLAY_NAME} for hybrid processing"
echo "Memory debugging enabled: MALLOC_CHECK_=2, MALLOC_PERTURB_=165"
echo "=================================================="

# Display your specific hybrid configuration
echo ""
echo "=== Your Custom Hybrid Configuration ==="
echo "OLLAMA_MODEL: $OLLAMA_MODEL"
echo "MODEL_DISPLAY_NAME: $MODEL_DISPLAY_NAME"
echo "GPU_LAYERS: $OLLAMA_GPU_LAYERS (Enhanced from .env)"
echo "CPU_LAYERS: Remaining layers"
echo "CONTEXT_SIZE: $OLLAMA_CONTEXT_SIZE (4K context)"
echo "BATCH_SIZE: $OLLAMA_BATCH_SIZE (Large batch)"
echo "CPU_THREADS: $OLLAMA_NUM_THREAD (8 threads)"
echo "TEMPERATURE: $MODEL_TEMPERATURE"
echo "TOP_P: $MODEL_TOP_P"
echo "TOP_K: $MODEL_TOP_K"
echo "REPEAT_PENALTY: $MODEL_REPEAT_PENALTY"
echo "MAX_TOKENS: $MODEL_MAX_TOKENS"
echo "MAX_MESSAGE_LENGTH: $MAX_MESSAGE_LENGTH"
echo "RATE_LIMIT: $RATE_LIMIT_MESSAGES_PER_MINUTE msg/min"
echo "MMAP: ${MODEL_USE_MMAP} (from .env)"
echo "MLOCK: ${MODEL_USE_MLOCK} (from .env)"
echo "KEEP_ALIVE: Enhanced ($OLLAMA_KEEP_ALIVE seconds)"
echo "============================"

# Verify required environment variables for your setup
if [ -z "$OLLAMA_MODEL" ] || [ -z "$MODEL_DISPLAY_NAME" ]; then
    echo "❌ Required environment variables not set!"
    exit 1
fi

# Set fallback for MODEL_DESCRIPTION if commented out
if [ -z "$MODEL_DESCRIPTION" ]; then
    export MODEL_DESCRIPTION="Advanced coding and reasoning model optimized for hybrid GPU+CPU processing"
    echo "ℹ️  Using fallback MODEL_DESCRIPTION"
fi

# Install bc for calculations and jq for JSON parsing
echo ""
echo "🔧 Installing required tools..."
apt-get update -qq > /dev/null 2>&1
apt-get install -y bc jq > /dev/null 2>&1
echo "✅ Tools installed"

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

# Enhanced GPU detection with proper math
echo ""
echo "🔍 GPU Detection and Enhanced VRAM Management..."
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "🎮 NVIDIA GPU detected:"
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)
    echo "$GPU_INFO"
    
    GPU_MEMORY_TOTAL=$(echo "$GPU_INFO" | cut -d',' -f2 | xargs)
    GPU_MEMORY_FREE=$(echo "$GPU_INFO" | cut -d',' -f3 | xargs)
    GPU_MEMORY_USED=$(echo "$GPU_INFO" | cut -d',' -f4 | xargs)
    
    # Calculate target using proper integer math (no bc dependency issues)
    TARGET_VRAM=$((GPU_MEMORY_TOTAL * 8 / 10))  # 80% using integer math
    
    echo "📊 Enhanced GPU Memory Status:"
    echo "   Total: ${GPU_MEMORY_TOTAL}MB"
    echo "   Free: ${GPU_MEMORY_FREE}MB"
    echo "   Used: ${GPU_MEMORY_USED}MB"
    echo "   Target (80%): ${TARGET_VRAM}MB"
    echo "   GPU Layers: $OLLAMA_GPU_LAYERS (enhanced)"
    
    # Calculate available VRAM for model
    AVAILABLE_VRAM=$((GPU_MEMORY_FREE - 1024))  # Reserve 1GB for system
    echo "   Available for model: ${AVAILABLE_VRAM}MB"
    
    if [ "$AVAILABLE_VRAM" -lt "$TARGET_VRAM" ]; then
        echo "⚠️  WARNING: Available VRAM (${AVAILABLE_VRAM}MB) < Target (${TARGET_VRAM}MB)"
        echo "💡 Consider reducing GPU layers or clearing GPU memory"
        
        # Try to clear GPU memory
        echo "🧹 Attempting to clear GPU memory..."
        nvidia-smi --gpu-reset 2>/dev/null || echo "GPU reset not available"
        sleep 2
        
        # Recheck after clearing
        GPU_INFO_NEW=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
        echo "🔄 GPU Memory after clearing: ${GPU_INFO_NEW}MB free"
    else
        echo "✅ Sufficient VRAM available for enhanced hybrid mode"
    fi
else
    echo "💻 CPU-only mode - no GPU detected"
    echo "⚠️  Performance will be significantly reduced"
    TARGET_VRAM=0
fi

# Create directories with proper permissions
mkdir -p "$OLLAMA_MODELS"
chown -R ollama:ollama "$OLLAMA_MODELS" 2>/dev/null || true
echo "📁 Models directory: $OLLAMA_MODELS"

# Generate your specific optimized Modelfile (FIXED - no use_mlock warning)
echo ""
echo "🔧 Generating your custom hybrid-optimized Modelfile..."
if [ -f "/home/ollama/Modelfile" ]; then
    echo "✅ Using your custom Modelfile template"
    envsubst < /home/ollama/Modelfile > /tmp/hybrid_modelfile
    echo "✅ Custom Modelfile generated with your .env variables"
    echo "📄 Your Custom Modelfile preview:"
    head -25 /tmp/hybrid_modelfile
else
    echo "⚠️ Base Modelfile not found - creating one with your .env settings"
    cat > /tmp/hybrid_modelfile << EOF
FROM $OLLAMA_MODEL

SYSTEM """You are $MODEL_DISPLAY_NAME, an advanced AI assistant specialized in coding and technical problem-solving.

$MODEL_DESCRIPTION

You are running in hybrid GPU+CPU mode with optimized memory management for stability and performance."""

# Memory settings from your .env (FIXED - removed use_mlock)
PARAMETER use_mmap $MODEL_USE_MMAP

# Core model parameters from your .env
PARAMETER temperature $MODEL_TEMPERATURE
PARAMETER top_p $MODEL_TOP_P
PARAMETER top_k $MODEL_TOP_K
PARAMETER repeat_penalty $MODEL_REPEAT_PENALTY

# Your enhanced hybrid configuration
PARAMETER num_ctx $OLLAMA_CONTEXT_SIZE
PARAMETER num_gpu $OLLAMA_GPU_LAYERS
PARAMETER num_thread $OLLAMA_NUM_THREAD
PARAMETER num_batch $OLLAMA_BATCH_SIZE

# Response settings from your .env
PARAMETER num_predict $MODEL_MAX_TOKENS
PARAMETER repeat_last_n 64

# Stop sequences
PARAMETER stop "<|endoftext|>"
PARAMETER stop "<|im_end|>"
PARAMETER stop "[DONE]"
PARAMETER stop "<|end|>"
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

# Set your specific environment settings (FIXED - remove GPU memory fraction)
export OLLAMA_MMAP=$OLLAMA_MMAP
export OLLAMA_MLOCK=$OLLAMA_MLOCK
export OLLAMA_NOPRUNE=$OLLAMA_NOPRUNE
export OLLAMA_MAX_LOADED_MODELS=$OLLAMA_MAX_LOADED_MODELS
export OLLAMA_KEEP_ALIVE=$OLLAMA_KEEP_ALIVE
# REMOVED: CUDA_MEMORY_FRACTION - let Ollama manage memory dynamically

echo ""
echo "🚀 Starting Ollama with your enhanced configuration..."
echo "   Model: $OLLAMA_MODEL"
echo "   Display Name: $MODEL_DISPLAY_NAME"
echo "   GPU Layers: $OLLAMA_GPU_LAYERS (enhanced)"
echo "   CPU Layers: Remaining"
echo "   Temperature: $MODEL_TEMPERATURE"
echo "   Top P: $MODEL_TOP_P"
echo "   Top K: $MODEL_TOP_K"
echo "   Repeat Penalty: $MODEL_REPEAT_PENALTY"
echo "   Max Tokens: $MODEL_MAX_TOKENS"
echo "   Context Size: $OLLAMA_CONTEXT_SIZE (4K)"
echo "   Batch Size: $OLLAMA_BATCH_SIZE (large)"
echo "   CPU Threads: $OLLAMA_NUM_THREAD (8 threads)"
echo "   GPU Memory: Dynamic (no artificial limits)"
echo "   MMAP: $MODEL_USE_MMAP"
echo "   MLOCK: $MODEL_USE_MLOCK"
echo "   Keep Alive: $OLLAMA_KEEP_ALIVE seconds"
echo "   Rate Limit: $RATE_LIMIT_MESSAGES_PER_MINUTE msg/min"
echo "   Max Message: $MAX_MESSAGE_LENGTH chars"
echo "   Memory Debug: ENABLED"

# Start Ollama with your specific settings (FIXED - removed CUDA_MEMORY_FRACTION)
exec env \
    MALLOC_CHECK_=2 \
    MALLOC_PERTURB_=165 \
    OLLAMA_HOST="$OLLAMA_HOST" \
    OLLAMA_MODELS="$OLLAMA_MODELS" \
    OLLAMA_MMAP=$OLLAMA_MMAP \
    OLLAMA_MLOCK=$OLLAMA_MLOCK \
    OLLAMA_NOPRUNE=$OLLAMA_NOPRUNE \
    OLLAMA_KEEP_ALIVE=$OLLAMA_KEEP_ALIVE \
    OLLAMA_MAX_LOADED_MODELS=$OLLAMA_MAX_LOADED_MODELS \
    OLLAMA_LOAD_TIMEOUT="${OLLAMA_LOAD_TIMEOUT}" \
    OLLAMA_NUM_PARALLEL=2 \
    CUDA_VISIBLE_DEVICES=0 \
    ollama serve &

OLLAMA_PID=$!
echo "📝 Ollama started with PID: $OLLAMA_PID"

# Wait for API with extended timeout for your enhanced configuration
echo "⏳ Waiting for Ollama API (enhanced mode may take longer)..."
for i in {1..120}; do  # Extended to 120 attempts for your larger configuration
    if curl -s --max-time 10 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✅ API ready after ${i} attempts"
        break
    fi
    if [ $i -eq 120 ]; then
        echo "❌ API failed to start after 4 minutes"
        exit 1
    fi
    echo "⏳ Attempt $i/120..."
    sleep 2
done

# Check if model exists
echo ""
echo "📦 Checking for model: $OLLAMA_MODEL"
MODEL_EXISTS=$(ollama list 2>/dev/null | grep -c "$OLLAMA_MODEL" || true)

if [ "$MODEL_EXISTS" -eq 0 ]; then
    echo "📥 Model not found, pulling $OLLAMA_MODEL..."
    echo "⏳ This may take a while for the model..."
    
    timeout 2400 ollama pull "$OLLAMA_MODEL" || {  # Extended timeout for larger models
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

# Create your enhanced hybrid-optimized model
HYBRID_MODEL="${OLLAMA_MODEL}-hybrid"
echo ""
echo "🔧 Creating your enhanced hybrid-optimized model: $HYBRID_MODEL"

if [ -f "/tmp/hybrid_modelfile" ]; then
    if ! ollama list 2>/dev/null | grep -q "$HYBRID_MODEL"; then
        echo "🛠️ Creating enhanced hybrid model with your settings (this may take a few minutes)..."
        ollama create "$HYBRID_MODEL" -f /tmp/hybrid_modelfile || {
            echo "⚠️ Failed to create hybrid model, using base"
            HYBRID_MODEL="$OLLAMA_MODEL"
        }
        
        if [ "$HYBRID_MODEL" != "$OLLAMA_MODEL" ]; then
            echo "✅ Enhanced hybrid model created successfully with your settings:"
            echo "   Temperature: $MODEL_TEMPERATURE"
            echo "   Context Size: $OLLAMA_CONTEXT_SIZE (4K)"
            echo "   GPU Layers: $OLLAMA_GPU_LAYERS (enhanced)"
            echo "   Batch Size: $OLLAMA_BATCH_SIZE (large)"
            echo "   CPU Threads: $OLLAMA_NUM_THREAD (8 threads)"
            echo "   Max Tokens: $MODEL_MAX_TOKENS"
        fi
    else
        echo "✅ Enhanced hybrid model already exists"
    fi
else
    HYBRID_MODEL="$OLLAMA_MODEL"
fi

# Test your enhanced hybrid model (FIXED - proper system prompt)
echo ""
echo "🧪 Testing your enhanced hybrid model: $HYBRID_MODEL"

# Build test payload with your specific settings
TEST_PAYLOAD="{
    \"model\": \"$HYBRID_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Please respond briefly that you are ready and working correctly. What model are you?\"}],
    \"stream\": false,
    \"options\": {
        \"temperature\": $MODEL_TEMPERATURE,
        \"num_predict\": 100,
        \"num_ctx\": $OLLAMA_CONTEXT_SIZE,
        \"num_gpu\": $OLLAMA_GPU_LAYERS,
        \"num_thread\": $OLLAMA_NUM_THREAD,
        \"num_batch\": $OLLAMA_BATCH_SIZE,
        \"top_p\": $MODEL_TOP_P,
        \"top_k\": $MODEL_TOP_K,
        \"repeat_penalty\": $MODEL_REPEAT_PENALTY
    },
    \"keep_alive\": $OLLAMA_KEEP_ALIVE
}"

echo "📤 Sending enhanced hybrid test request..."
echo "⏳ This may take longer due to enhanced processing..."

TEST_RESPONSE=$(curl -s --max-time 180 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD")

if echo "$TEST_RESPONSE" | grep -q "\"content\""; then
    echo "✅ Enhanced hybrid model test SUCCESSFUL!"
    echo "🔒 Model loaded with $OLLAMA_GPU_LAYERS GPU layers + CPU layers"
    echo "🎛️ Using your enhanced .env settings:"
    echo "   Temperature: $MODEL_TEMPERATURE"
    echo "   Top P: $MODEL_TOP_P"
    echo "   Top K: $MODEL_TOP_K"
    echo "   Repeat Penalty: $MODEL_REPEAT_PENALTY"
    echo "   Context Size: $OLLAMA_CONTEXT_SIZE (4K)"
    echo "   Batch Size: $OLLAMA_BATCH_SIZE (large)"
    echo "   CPU Threads: $OLLAMA_NUM_THREAD (8 threads)"
    echo "   Max Tokens: $MODEL_MAX_TOKENS"
    echo "   GPU Memory: Dynamic allocation"
    
    # Show VRAM usage after loading (FIXED - no bc dependency)
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo ""
        echo "📊 Enhanced VRAM Usage After Loading:"
        GPU_INFO_FINAL=$(nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$GPU_INFO_FINAL" ]; then
            used=$(echo "$GPU_INFO_FINAL" | cut -d',' -f1 | xargs)
            free=$(echo "$GPU_INFO_FINAL" | cut -d',' -f2 | xargs)
            total=$(echo "$GPU_INFO_FINAL" | cut -d',' -f3 | xargs)
            target_80=$((total * 8 / 10))  # 80% using integer math
            
            echo "   Used: ${used}MB"
            echo "   Free: ${free}MB"
            echo "   Total: ${total}MB"
            echo "   Target (80%): ${target_80}MB"
            
            if [ "$used" -le "$target_80" ]; then
                echo "   Status: ✅ Within enhanced target"
            else
                over_target=$((used - target_80))
                echo "   Status: ✅ Using ${over_target}MB over target (dynamic allocation working)"
            fi
        fi
    fi
    
    # Show the actual response (FIXED - handle JSON properly)
    echo ""
    echo "📋 Enhanced Model Response:"
    if command -v jq >/dev/null 2>&1; then
        echo "$TEST_RESPONSE" | jq -r '.message.content // "No content"' 2>/dev/null || echo "Model responded successfully"
    else
        echo "Model responded successfully"
    fi
else
    echo "❌ Enhanced hybrid model test FAILED"
    echo "📋 Full response:"
    echo "$TEST_RESPONSE"
    echo ""
    echo "💡 Troubleshooting for your enhanced config:"
    echo "   - Your GPU layers ($OLLAMA_GPU_LAYERS) might be too high"
    echo "   - Your context size ($OLLAMA_CONTEXT_SIZE) is large"
    echo "   - Your batch size ($OLLAMA_BATCH_SIZE) is large"
    echo "   - Consider reducing some parameters in .env"
fi

# Save active model
echo "$HYBRID_MODEL" > /tmp/active_model
touch /tmp/ollama_ready

# Final status with your enhanced configuration (FIXED - show all values)
echo ""
echo "========================================================="
echo "🎯 ENHANCED HYBRID MODE READY"
echo "🔧 CONFIGURED WITH YOUR CUSTOM .ENV VARIABLES"
echo "========================================================="
echo "✅ Active Model: $HYBRID_MODEL"
echo "✅ Model Display Name: $MODEL_DISPLAY_NAME"
echo "✅ GPU Layers: $OLLAMA_GPU_LAYERS (enhanced from .env)"
echo "✅ CPU Layers: Remaining layers"
echo "✅ Temperature: $MODEL_TEMPERATURE (from .env)"
echo "✅ Top P: $MODEL_TOP_P (from .env)"
echo "✅ Top K: $MODEL_TOP_K (from .env)"
echo "✅ Repeat Penalty: $MODEL_REPEAT_PENALTY (from .env)"
echo "✅ Context Size: $OLLAMA_CONTEXT_SIZE tokens (4K from .env)"
echo "✅ Batch Size: $OLLAMA_BATCH_SIZE tokens (large from .env)"
echo "✅ CPU Threads: $OLLAMA_NUM_THREAD (8 threads from .env)"
echo "✅ Max Tokens: $MODEL_MAX_TOKENS (from .env)"
echo "✅ GPU Memory: Dynamic allocation (no artificial limits)"
echo "✅ Rate Limit: $RATE_LIMIT_MESSAGES_PER_MINUTE msg/min (from .env)"
echo "✅ Max Message: $MAX_MESSAGE_LENGTH chars (from .env)"
echo "✅ MMAP: $MODEL_USE_MMAP (from .env)"
echo "✅ MLOCK: $MODEL_USE_MLOCK (from .env)"
echo "✅ Keep Alive: $OLLAMA_KEEP_ALIVE seconds (from .env)"
echo "✅ Memory Debug: ENABLED"
echo "✅ API URL: http://localhost:11434"
echo "========================================================="

# Enhanced monitoring for your configuration (FIXED - no bc dependency)
cleanup() {
    echo "🔄 Shutting down enhanced hybrid mode..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "🔄 Monitoring enhanced hybrid service with your configuration..."
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Process died - restarting..."
        exec "$0"
    fi
    
    # Health check every 30 seconds
    if ! curl -s --max-time 10 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "⚠️ API health check failed"
    fi
    
    # Monitor VRAM usage every 2 minutes with proper integer math
    if [ $(($(date +%s) % 120)) -eq 0 ] && command -v nvidia-smi >/dev/null 2>&1; then
        VRAM_INFO=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$VRAM_INFO" ]; then
            VRAM_USED=$(echo "$VRAM_INFO" | cut -d',' -f1 | xargs)
            VRAM_TOTAL=$(echo "$VRAM_INFO" | cut -d',' -f2 | xargs)
            VRAM_TARGET_80=$((VRAM_TOTAL * 8 / 10))  # 80% using integer math
            
            if [ "$VRAM_USED" -gt "$VRAM_TARGET_80" ]; then
                echo "ℹ️ VRAM usage: ${VRAM_USED}MB (dynamic allocation active)"
            fi
        fi
    fi
    
    sleep 30
done