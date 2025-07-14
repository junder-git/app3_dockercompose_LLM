#!/bin/bash
# ollama/scripts/init-ollama.sh - Clean and efficient version

set -euo pipefail

# Memory debugging
export MALLOC_CHECK_=2 MALLOC_PERTURB_=165

log() { echo "$(date '+%H:%M:%S') $1"; }
error() { echo "❌ $1" >&2; exit 1; }

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
        [[ $free -lt 2048 ]] && log "⚠️  Low VRAM - consider reducing GPU layers"
    fi
else
    log "💻 CPU-only mode"
fi

# Cleanup and prepare
log "🔄 Cleaning up..."
pkill -f ollama || true
sleep 2
nvidia-smi --gpu-reset 2>/dev/null || true

# Create models directory
mkdir -p "${OLLAMA_MODELS:-/home/ollama/.ollama/models}"

# Generate Modelfile
log "📝 Generating Modelfile..."
if [[ -f "/home/ollama/Modelfile" ]]; then
    envsubst < /home/ollama/Modelfile > /tmp/modelfile
else
    error "Modelfile not found at /home/ollama/Modelfile"
fi

# Start Ollama
log "🔧 Starting Ollama service..."
env OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}" \
    OLLAMA_MODELS="${OLLAMA_MODELS:-/home/ollama/.ollama/models}" \
    OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-5m}" \
    CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}" \
    ollama serve &

ollama_pid=$!
echo $ollama_pid > /tmp/ollama_pid

# Wait for API
log "⏳ Waiting for API..."
for i in {1..30}; do
    if curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
        log "✅ API ready"
        break
    fi
    [[ $i -eq 30 ]] && error "API timeout"
    sleep 1
done

# Ensure model exists
log "📦 Checking model: $OLLAMA_MODEL"
if ! ollama list 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
    log "📥 Pulling $OLLAMA_MODEL..."
    if ! timeout 1200 ollama pull "$OLLAMA_MODEL"; then
        log "🔄 Fallback to mistral..."
        ollama pull "mistral" || error "Failed to pull any model"
        export OLLAMA_MODEL="mistral"
    fi
fi

# Create hybrid model
hybrid_model="${OLLAMA_MODEL}-hybrid"
log "🔧 Creating hybrid model: $hybrid_model"

if ! ollama list 2>/dev/null | grep -q "$hybrid_model"; then
    if ollama create "$hybrid_model" -f /tmp/modelfile; then
        log "✅ Hybrid model created"
    else
        log "⚠️  Using base model"
        hybrid_model="$OLLAMA_MODEL"
    fi
fi

# Test model
log "🧪 Testing model..."
test_payload="{
    \"model\": \"$hybrid_model\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello! Respond briefly that you are ready.\"}],
    \"stream\": false,
    \"options\": {
        \"temperature\": ${MODEL_TEMPERATURE:-0.7},
        \"num_predict\": 50,
        \"num_ctx\": ${OLLAMA_CONTEXT_SIZE:-4096},
        \"num_gpu\": ${OLLAMA_GPU_LAYERS:-32}
    }
}"

test_response=$(curl -s --max-time 60 -X POST http://localhost:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$test_payload" 2>/dev/null || echo '{"error": "test_failed"}')

if echo "$test_response" | grep -q "\"content\""; then
    log "✅ Model test passed"
elif echo "$test_response" | grep -q "error"; then
    log "⚠️  Model test had errors but service is running"
    log "Response: $(echo "$test_response" | jq -r '.error // "Unknown error"' 2>/dev/null || echo "Parse error")"
else
    log "⚠️  Model test unclear but API responding - service running"
fi

# Always continue - don't exit on test failure

# Final status
echo "$hybrid_model" > /tmp/active_model
touch /tmp/ollama_ready

log "🎯 HYBRID MODE READY"
log "Model: $hybrid_model"
log "GPU Layers: ${OLLAMA_GPU_LAYERS:-32}"
log "Context: ${OLLAMA_CONTEXT_SIZE:-4096} tokens"
log "API: http://localhost:11434"

# Monitor (simplified) - ALWAYS run regardless of test results
cleanup() {
    log "🔄 Shutting down..."
    kill $ollama_pid 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

log "🔄 Monitoring service..."
while true; do
    if ! kill -0 $ollama_pid 2>/dev/null; then
        log "❌ Process died - restarting..."
        exec "$0"
    fi
    
    # Simple health check every 60 seconds
    if curl -s --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        # Service is healthy, continue quietly
        :
    else
        log "⚠️  API health check failed"
    fi
    
    sleep 60
done