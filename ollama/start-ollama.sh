#!/bin/bash

# start-ollama.sh - Custom startup script for Ollama with automatic model download

set -e

echo "Starting Ollama server..."

# Start Ollama in the background
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "Waiting for Ollama server to start..."
until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
    echo "Waiting for Ollama server..."
    sleep 2
done

echo "Ollama server is ready!"

# Function to check if model exists
check_model() {
    local model_name="$1"
    ollama list | grep -q "^${model_name}" && return 0 || return 1
}

# Download deepseek-coder-v2:16b if not present
MODEL_NAME="devstral:24b"
echo "Checking for model: $MODEL_NAME"

if check_model "$MODEL_NAME"; then
    echo "Model $MODEL_NAME already exists, skipping download"
else
    echo "Model $MODEL_NAME not found, downloading..."
    echo "This may take a while (model is ~14GB)..."
    
    # Download with progress
    ollama pull "$MODEL_NAME"
    
    if [ $? -eq 0 ]; then
        echo "Successfully downloaded $MODEL_NAME"
    else
        echo "Failed to download $MODEL_NAME, but continuing..."
    fi
fi

# Alternative: Download deepseek-coder-v2:33b if you have more VRAM
# Uncomment the following lines if you want the larger model instead:
# MODEL_NAME_LARGE="deepseek-coder-v2:33b"
# echo "Checking for model: $MODEL_NAME_LARGE"
# if ! check_model "$MODEL_NAME_LARGE"; then
#     echo "Downloading larger model: $MODEL_NAME_LARGE (this is ~18GB)..."
#     ollama pull "$MODEL_NAME_LARGE" || echo "Failed to download $MODEL_NAME_LARGE"
# fi

# Optional: Download additional useful models
#EXTRA_MODELS=(
 #   "llama3.1:8b"
#    "codellama:13b"
#    "mistral:7b"
#)

#for model in "${EXTRA_MODELS[@]}"; do
#    if ! check_model "$model"; then
#        echo "Downloading additional model: $model"
#        ollama pull "$model" || echo "Failed to download $model"
#    fi
#done

echo "Model setup complete!"
echo "Available models:"
ollama list

# Keep the script running and forward signals to Ollama
trap 'kill $OLLAMA_PID' SIGINT SIGTERM

# Wait for Ollama process
wait $OLLAMA_PID