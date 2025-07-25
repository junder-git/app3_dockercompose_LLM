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
    
    cat > "$modelfile_path" << EOF
FROM ${MODEL_GGUF_PATH}

# Template for chat completion
TEMPLATE """{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
{{ end }}<|im_start|>assistant
"""

# Model parameters from environment variables
PARAMETER temperature ${MODEL_TEMPERATURE}
PARAMETER top_p ${MODEL_TOP_P}
PARAMETER top_k ${MODEL_TOP_K}
PARAMETER min_p ${MODEL_MIN_P}
PARAMETER repeat_penalty ${MODEL_REPEAT_PENALTY}
PARAMETER repeat_last_n ${MODEL_REPEAT_LAST_N}
PARAMETER num_ctx ${MODEL_NUM_CTX}
PARAMETER num_predict ${MODEL_NUM_PREDICT}
PARAMETER seed ${MODEL_SEED}
PARAMETER num_gpu ${OLLAMA_GPU_LAYERS}
PARAMETER num_thread ${OLLAMA_NUM_THREAD}

# System message
SYSTEM """You are Devstral, a helpful AI assistant specialized in software development and coding tasks."""
EOF

    log "Modelfile generated successfully"
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
    log "Starting Ollama server..."
    
    # Start Ollama server in background
    ollama serve &
    OLLAMA_PID=$!
    
    # Give the server a moment to start
    log "Waiting for Ollama server to start..."
    sleep 5
    
    # Generate the Modelfile with current environment variables
    generate_modelfile "$MODELFILE_PATH"
    
    # Check if model already exists
    if check_model_exists "$MODEL_NAME"; then
        log "Model initialization complete - using existing model"
    else
        # Create the model
        if create_model "$MODEL_NAME" "$MODELFILE_PATH"; then
            log "Model creation successful"
        else
            log "WARNING: Model creation failed, but keeping server running"
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