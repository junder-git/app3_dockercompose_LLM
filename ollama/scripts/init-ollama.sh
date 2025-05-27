#!/bin/bash

# Get model name from environment variable
MODEL_NAME=${OLLAMA_MODEL:-"deepseek-coder-v2:16b"}

# Start Ollama service in the background
echo "Starting Ollama service..."
ollama serve &

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
while ! curl -s http://localhost:11434/api/tags > /dev/null; do
    echo "Ollama not ready yet, waiting..."
    sleep 2
done

echo "Ollama is ready. Current status:"
curl -s http://localhost:11434/api/tags | jq '.' || echo "No jq available, raw output:"
curl -s http://localhost:11434/api/tags

# Check if the specified model exists
echo "Checking for $MODEL_NAME model..."
if ollama list | grep -q "$MODEL_NAME"; then
    echo "✓ $MODEL_NAME model already exists"
else
    echo "❌ $MODEL_NAME model not found. Available models:"
    ollama list
    
    echo "Attempting to pull $MODEL_NAME model..."
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully pulled $MODEL_NAME model"
    else
        echo "❌ Failed to pull $MODEL_NAME model"
        echo "Trying alternative model names..."
        
        # Try different model names based on the requested model
        if [[ "$MODEL_NAME" == *"deepseek-coder-v2"* ]]; then
            alt_models=("deepseek-coder-v2" "deepseek-coder-v2:latest" "deepseek-coder:latest" "deepseek-coder")
        elif [[ "$MODEL_NAME" == *"deepseek-coder"* ]]; then
            alt_models=("deepseek-coder" "deepseek-coder:latest" "deepseek-coder:33b" "deepseek-coder:7b")
        else
            alt_models=("deepseek-coder-v2:16b" "deepseek-coder:latest" "llama2")
        fi
        
        for model in "${alt_models[@]}"; do
            echo "Trying to pull $model..."
            if ollama pull "$model"; then
                echo "✓ Successfully pulled $model"
                export OLLAMA_MODEL="$model"
                echo "Updated model to: $model"
                break
            else
                echo "❌ Failed to pull $model"
            fi
        done
    fi
fi

# List all available models
echo "Final model list:"
ollama list

# Test the API endpoint with the configured model
echo "Testing API endpoint with model: $MODEL_NAME"
curl -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL_NAME\",
        \"prompt\": \"Hello, please respond with 'API test successful'\",
        \"stream\": false
    }" | head -5 || echo "API test failed - this might be normal if model is still loading"

# Keep the container running
echo "Ollama initialization complete. Model: $MODEL_NAME"
echo "Keeping service running..."
wait