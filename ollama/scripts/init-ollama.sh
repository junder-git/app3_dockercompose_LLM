#!/bin/bash
# ollama/scripts/init-ollama.sh - Fixed version with proper mmap handling

MODEL_NAME=$OLLAMA_MODEL

echo "=== Devstral Ollama Initialization ==="
echo "Base: Ubuntu 22.04 + Ollama Install Script"
echo "Target model: $MODEL_NAME"
echo "====================================="

# CRITICAL: Force disable mmap properly - use .env values only
export OLLAMA_MMAP=$OLLAMA_MMAP
export OLLAMA_MLOCK=$OLLAMA_MLOCK
export OLLAMA_NOPRUNE=$OLLAMA_NOPRUNE

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
    if ollama run "$MODEL_NAME" "test" --verbose 2>/dev/null | head -1 | grep -q "test\|hello\|hi"; then
        echo "✅ Model responds correctly"
    else
        echo "