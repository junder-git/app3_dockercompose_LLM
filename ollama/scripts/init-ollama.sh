#!/bin/bash
# ollama/scripts/init-ollama.sh - Optimized service initialization

set -euo pipefail

log() { echo "$(date '+%H:%M:%S') $1"; }
error() { echo "❌ $1" >&2; exit 1; }
warning() { echo "⚠️  $1" >&2; }

# Validate environment
[[ -z "${OLLAMA_MODEL:-}" ]] && error "OLLAMA_MODEL not set"
[[ -z "${MODEL_DISPLAY_NAME:-}" ]] && error "MODEL_DISPLAY_NAME not set"

log "🚀 Starting hybrid GPU+CPU mode for $MODEL_DISPLAY_NAME"

# GPU detection
if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_info=$(nvidia-smi --query-gpu=memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [[ -n "$gpu_info" ]]; then
        total=$(echo "$gpu_info" | cut -d',' -f1)
        free=$(echo "$gpu_info" | cut -d',' -f2)
        log "🎮 GPU: ${total}MB total, ${free}MB free"
        [[ $free -lt 2048 ]] && warning "Low VRAM - consider reducing GPU layers"
    fi
else
    log "💻 CPU-only mode"
fi

# Cleanup and prepare
log "🔄 Cleaning up..."
pkill -f ollama || true
sleep 3
nvidia-smi --gpu-reset 2>/dev/null || true

# Create models directory
mkdir -p "${OLLAMA_MODELS:-/home/ollama/.ollama/models}"

# Start Ollama service with proper environment variables
log "🔧 Starting Ollama service with keep-alive=${OLLAMA_KEEP_ALIVE:-24h}..."
env OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}" \
    OLLAMA_MODELS="${OLLAMA_MODELS:-/home/ollama/.ollama/models}" \
    OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-24h}" \
    OLLAMA_NOPRUNE="${OLLAMA_NOPRUNE:-0}" \
    OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}" \
    OLLAMA_MMAP="${OLLAMA_MMAP:-0}" \
    OLLAMA_MLOCK="${OLLAMA_MLOCK:-1}" \
    OLLAMA_GPU_LAYERS="${OLLAMA_GPU_LAYERS:-12}" \
    OLLAMA_NUM_THREAD="${OLLAMA_NUM_THREAD:-4}" \
    OLLAMA_CONTEXT_SIZE="${OLLAMA_CONTEXT_SIZE:-4096}" \
    OLLAMA_BATCH_SIZE="${OLLAMA_BATCH_SIZE:-128}" \
    CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}" \
    ollama serve &

ollama_pid=$!
echo $ollama_pid > /tmp/ollama_pid

# Wait for API with better error handling
log "⏳ Waiting for API..."
for i in {1..60}; do
    if curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
        log "✅ API ready after ${i}s"
        break
    fi
    if [[ $i -eq 60 ]]; then
        error "API timeout after 60 seconds"
    fi
    sleep 1
done

# Check if model exists, if not try to pull it
log "📦 Checking for model: $OLLAMA_MODEL"
if ollama list 2>/dev/null | grep -q "^$OLLAMA_MODEL"; then
    log "✅ Model already exists: $OLLAMA_MODEL"
else
    log "📥 Model not found, attempting to pull $OLLAMA_MODEL..."
    
    if ollama pull "$OLLAMA_MODEL" 2>/dev/null; then
        log "✅ Successfully pulled $OLLAMA_MODEL"
    else
        warning "Failed to pull $OLLAMA_MODEL - checking available models..."
        
        available_models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | head -5)
        if [[ -n "$available_models" ]]; then
            log "Available models:"
            echo "$available_models" | while read -r model; do
                log "  - $model"
            done
            
            fallback_model=$(echo "$available_models" | head -1)
            warning "Using fallback model: $fallback_model"
            OLLAMA_MODEL="$fallback_model"
        else
            log "📥 No models found, pulling tinyllama as fallback..."
            if ollama pull tinyllama 2>/dev/null; then
                log "✅ Successfully pulled tinyllama as fallback"
                OLLAMA_MODEL="tinyllama"
            else
                error "Cannot pull any model. Check internet connection and model availability."
            fi
        fi
    fi
fi

# Generate Modelfile using the actual template
log "📝 Generating Modelfile from template..."
if [[ -f "/home/ollama/Modelfile" ]]; then
    envsubst < /home/ollama/Modelfile > /tmp/modelfile
    log "✅ Modelfile generated successfully"
else
    error "Modelfile template not found at /home/ollama/Modelfile"
fi

# Validate the generated Modelfile
if [[ ! -s "/tmp/modelfile" ]]; then
    error "Generated Modelfile is empty"
fi

# Show first few lines for debugging
log "📋 Modelfile preview:"
head -5 /tmp/modelfile | while read -r line; do
    log "  $line"
done

# Create hybrid model with better error handling
hybrid_model="${OLLAMA_MODEL}-hybrid"
log "🔧 Creating hybrid model: $hybrid_model"

if ollama list 2>/dev/null | grep -q "^$hybrid_model"; then
    log "✅ Hybrid model already exists: $hybrid_model"
else
    log "📝 Creating new hybrid model from Modelfile..."
    
    if ollama create "$hybrid_model" -f /tmp/modelfile 2>&1; then
        log "✅ Hybrid model created successfully: $hybrid_model"
        
        if ollama list 2>/dev/null | grep -q "^$hybrid_model"; then
            log "✅ Hybrid model verified in model list"
        else
            warning "Hybrid model creation reported success but model not found"
            hybrid_model="$OLLAMA_MODEL"
        fi
    else
        warning "Failed to create hybrid model, using base model"
        hybrid_model="$OLLAMA_MODEL"
        
        if ! ollama list 2>/dev/null | grep -q "^$OLLAMA_MODEL"; then
            error "Base model $OLLAMA_MODEL not found and hybrid creation failed"
        fi
    fi
fi

# Test model with current valid parameters
log "🧪 Testing model: $hybrid_model"

test_payload=$(cat << EOF
{
    "model": "$hybrid_model",
    "messages": [{"role": "user", "content": "Hello! Respond briefly that you are ready."}],
    "stream": false,
    "keep_alive": "${OLLAMA_KEEP_ALIVE}",
    "options": {
        "temperature": ${MODEL_TEMPERATURE},
        "num_predict": ${MODEL_NUM_PREDICT},
        "num_ctx": ${MODEL_NUM_CTX},
        "top_p": ${MODEL_TOP_P},
        "top_k": ${MODEL_TOP_K},
        "repeat_penalty": ${MODEL_REPEAT_PENALTY},
        "seed": ${MODEL_SEED}
    }
}
EOF
)

log "📡 Sending test request with extended timeout..."
test_response=$(timeout 300 curl -s -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$test_payload" 2>&1) || {
    warning "Test request timed out or failed (continuing anyway)"
    test_response='{"error": "test_timeout"}'
}

# Parse and validate response
if echo "$test_response" | jq -e '.message.content' >/dev/null 2>&1; then
    content=$(echo "$test_response" | jq -r '.message.content' 2>/dev/null)
    log "✅ Model test passed successfully"
    log "📝 Response: $content"
elif echo "$test_response" | jq -e '.error' >/dev/null 2>&1; then
    error_msg=$(echo "$test_response" | jq -r '.error' 2>/dev/null)
    warning "Model test failed with error: $error_msg"
    log "🔄 Service will continue running (test failures are non-fatal)"
else
    warning "Model test response unclear - service continuing anyway"
    log "🔍 Raw response: $test_response"
fi

log "✅ Service is running regardless of test results"

# Final status and monitoring
echo "$hybrid_model" > /tmp/active_model
touch /tmp/ollama_ready

log "🎯 HYBRID MODE READY"
log "✅ Model: $hybrid_model"
log "🎮 GPU Layers: ${OLLAMA_GPU_LAYERS:-12}"
log "🧠 Context: ${MODEL_NUM_CTX:-4096} tokens"
log "🌐 API: http://localhost:11434"
log "⏱️  Keep Alive: ${OLLAMA_KEEP_ALIVE:-24h}"

# Enhanced monitoring with health checks
cleanup() {
    log "🔄 Shutting down gracefully..."
    kill $ollama_pid 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

log "🔄 Starting monitoring loop..."
health_check_interval=60
consecutive_failures=0
max_failures=3

while true; do
    # Check if main process is still running
    if ! kill -0 $ollama_pid 2>/dev/null; then
        log "❌ Main process died - restarting..."
        exec "$0"
    fi
    
    # API health check
    if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        if [[ $consecutive_failures -gt 0 ]]; then
            log "✅ API health recovered after $consecutive_failures failures"
            consecutive_failures=0
        fi
    else
        consecutive_failures=$((consecutive_failures + 1))
        log "⚠️  API health check failed ($consecutive_failures/$max_failures)"
        
        if [[ $consecutive_failures -ge $max_failures ]]; then
            log "❌ Too many consecutive failures - restarting..."
            exec "$0"
        fi
    fi
    
    sleep $health_check_interval
done