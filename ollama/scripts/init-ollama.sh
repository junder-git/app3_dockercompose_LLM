#!/bin/bash

set -e

# Configuration from environment variables
MODEL_NAME="${MODEL_NAME}"
MODELFILE_PATH="${MODELFILE_PATH}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

generate_modelfile() {
    local modelfile_path="$1"
    
    log "Generating dynamic Modelfile at: $modelfile_path"
    log "Environment variables being used:"
    log "  MODEL_GGUF_PATH: '${MODEL_GGUF_PATH}'"
    log "  MODEL_TEMPERATURE: '${MODEL_TEMPERATURE}'"
    log "  MODEL_TOP_P: '${MODEL_TOP_P}'"
    log "  MODEL_TOP_K: '${MODEL_TOP_K}'"
    log "  MODEL_MIN_P: '${MODEL_MIN_P}'"
    log "  MODEL_REPEAT_PENALTY: '${MODEL_REPEAT_PENALTY}'"
    log "  MODEL_REPEAT_LAST_N: '${MODEL_REPEAT_LAST_N}'"
    log "  MODEL_NUM_CTX: '${MODEL_NUM_CTX}'"
    log "  MODEL_NUM_PREDICT: '${MODEL_NUM_PREDICT}'"
    log "  MODEL_SEED: '${MODEL_SEED}'"
    log "  OLLAMA_GPU_LAYERS: '${OLLAMA_GPU_LAYERS}'"
    log "  OLLAMA_NUM_THREAD: '${OLLAMA_NUM_THREAD}'"
    
    # Validate required variables
    if [ -z "${MODEL_GGUF_PATH}" ]; then
        log "ERROR: MODEL_GGUF_PATH is empty!"
        return 1
    fi
    
    # Check if GGUF file exists
    if [ ! -f "${MODEL_GGUF_PATH}" ]; then
        log "ERROR: GGUF file not found at: ${MODEL_GGUF_PATH}"
        log "Contents of /root/.ollama/models/:"
        ls -la /root/.ollama/models/ || log "Directory does not exist"
        return 1
    fi
    
    # Set defaults for empty numeric values with validation
    local temp="${MODEL_TEMPERATURE}"
    local top_p="${MODEL_TOP_P}"
    local top_k="${MODEL_TOP_K}"
    local min_p="${MODEL_MIN_P}"
    local repeat_penalty="${MODEL_REPEAT_PENALTY}"
    local repeat_last_n="${MODEL_REPEAT_LAST_N}"
    local num_ctx="${MODEL_NUM_CTX}"
    local num_predict="${MODEL_NUM_PREDICT}"
    local seed="${MODEL_SEED}"
    local gpu_layers="${OLLAMA_GPU_LAYERS}"
    local num_thread="${OLLAMA_NUM_THREAD}"
    
    # Apply defaults for empty values
    [ -z "$temp" ] && temp="0.7"
    [ -z "$top_p" ] && top_p="0.9"
    [ -z "$top_k" ] && top_k="40"
    [ -z "$min_p" ] && min_p="0.05"
    [ -z "$repeat_penalty" ] && repeat_penalty="1.1"
    [ -z "$repeat_last_n" ] && repeat_last_n="64"
    [ -z "$num_ctx" ] && num_ctx="2048"
    [ -z "$num_predict" ] && num_predict="512"
    [ -z "$seed" ] && seed="0"
    [ -z "$gpu_layers" ] && gpu_layers="20"
    [ -z "$num_thread" ] && num_thread="6"
    
    log "Final values being used:"
    log "  temperature: $temp, top_p: $top_p, top_k: $top_k, min_p: $min_p"
    log "  repeat_penalty: $repeat_penalty, repeat_last_n: $repeat_last_n"
    log "  num_ctx: $num_ctx, num_predict: $num_predict, seed: $seed"
    log "  gpu_layers: $gpu_layers, num_thread: $num_thread"
    
    cat > "$modelfile_path" << EOF
FROM ${MODEL_GGUF_PATH}

# Template for chat completion
TEMPLATE """{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant
"""

# Model parameters - ONLY VALID MODELFILE PARAMETERS
PARAMETER temperature ${temp}
PARAMETER top_p ${top_p}
PARAMETER top_k ${top_k}
PARAMETER min_p ${min_p}
PARAMETER repeat_penalty ${repeat_penalty}
PARAMETER repeat_last_n ${repeat_last_n}
PARAMETER num_ctx ${num_ctx}
PARAMETER num_predict ${num_predict}
PARAMETER seed ${seed}

# System message
SYSTEM """You are Devstral, a helpful AI assistant specialized in software development and coding tasks."""
EOF

    log "Modelfile generated successfully"
    log "=== GENERATED MODELFILE CONTENTS ==="
    cat "$modelfile_path"
    log "=== END MODELFILE CONTENTS ==="
}

check_model_exists() {
    local model_name="$1"
    log "Checking if model '$model_name' already exists..."
    
    if ollama list | grep -q "^$model_name"; then
        log "Model '$model_name' already exists, skipping creation"
        return 0
    else
        log "Model '$model_name' does not exist, will create it"
        return 1
    fi
}

create_model() {
    local model_name="$1"
    local modelfile_path="$2"
    
    log "Creating model '$model_name' from Modelfile: $modelfile_path"
    if ollama create "$model_name" -f "$modelfile_path"; then
        log "Model '$model_name' created successfully!"
        return 0
    else
        log "ERROR: Failed to create model '$model_name'"
        return 1
    fi
}

main() {
    log "=== Ollama Model Initialization Script ==="
    log "Model: $MODEL_NAME"
    log "Modelfile: $MODELFILE_PATH"
    
    # Check if GGUF file exists BEFORE starting server
    log "Checking if GGUF file exists at: $MODEL_GGUF_PATH"
    if [ ! -f "$MODEL_GGUF_PATH" ]; then
        log "ERROR: GGUF file not found at $MODEL_GGUF_PATH"
        log "Available files in /root/.ollama/models/:"
        ls -la /root/.ollama/models/ || log "Directory does not exist"
        log "CRITICAL: Cannot create model without GGUF file. Exiting..."
        exit 1
    else
        log "✅ GGUF file found: $MODEL_GGUF_PATH"
        log "File size: $(du -h "$MODEL_GGUF_PATH" | cut -f1)"
    fi
    
    log "Starting Ollama server..."
    
    # Start Ollama server in background
    ollama serve &
    OLLAMA_PID=$!
    
    # Wait for server to be ready with retries
    log "Waiting for Ollama server to start..."
    for i in $(seq 1 30); do
        if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
            log "✅ Ollama server is ready after $i attempts"
            break
        fi
        if [ $i -eq 30 ]; then
            log "ERROR: Ollama server failed to start after 30 attempts"
            kill $OLLAMA_PID 2>/dev/null || true
            exit 1
        fi
        log "Attempt $i: Waiting for Ollama server..."
        sleep 2
    done
    
    # Generate the Modelfile with environment variables
    if ! generate_modelfile "$MODELFILE_PATH"; then
        log "ERROR: Failed to generate Modelfile"
        kill $OLLAMA_PID 2>/dev/null || true
        exit 1
    fi
    
    # Check if model already exists
    if check_model_exists "$MODEL_NAME"; then
        log "Model initialization complete - using existing model"
    else
        # Create the model with better error handling
        log "Creating model '$MODEL_NAME'..."
        if create_model "$MODEL_NAME" "$MODELFILE_PATH"; then
            log "✅ Model '$MODEL_NAME' created successfully!"
            
            # Verify the model was created
            log "Verifying model creation..."
            if ollama list | grep -q "^$MODEL_NAME"; then
                log "✅ Model '$MODEL_NAME' verified in ollama list"
            else
                log "WARNING: Model not found in ollama list after creation"
            fi
        else
            log "ERROR: Model creation failed, but keeping server running"
            log "This might be due to missing GGUF file or invalid parameters"
        fi
    fi
    
    log "=== Model initialization complete, keeping Ollama server running ==="
    
    # Wait for the Ollama process
    wait $OLLAMA_PID
}

# Handle shutdown gracefully
trap 'log "Received shutdown signal, stopping Ollama server..."; kill $OLLAMA_PID 2>/dev/null || true; exit 0' TERM INT

# Run main function
main "$@"