#!/bin/bash

set -e

# Configuration from environment variables
MODEL_NAME="${MODEL_NAME}"
MODELFILE_PATH="${MODELFILE_PATH}"
OLLAMA_MAX_RETRIES="${OLLAMA_MAX_RETRIES}"
OLLAMA_RETRY_INTERVAL="${OLLAMA_RETRY_INTERVAL}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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
    
    log "Processing Modelfile with environment variables..."
    envsubst < "$modelfile_path" > "${modelfile_path}.processed"
    
    log "Creating model '$model_name' from processed Modelfile..."
    if ollama create "$model_name" -f "${modelfile_path}.processed"; then
        log "Model '$model_name' created successfully!"
        
        # Clean up processed file
        rm -f "${modelfile_path}.processed"
        return 0
    else
        log "ERROR: Failed to create model '$model_name'"
        return 1
    fi
}

main() {
    log "=== Ollama Model Initialization Script ==="
    log "Starting Ollama server..."
    
    # Start Ollama server in background
    ollama serve &
    OLLAMA_PID=$!
    
    # Give the server a moment to start
    log "Waiting for Ollama server to start..."
    sleep 5
    
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