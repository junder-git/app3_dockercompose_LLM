#!/bin/bash

# Start Ollama service in the background
ollama serve &

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
while ! curl -s http://localhost:11434/api/tags > /dev/null; do
    sleep 1
done

echo "Ollama is ready. Checking for deepseek-coder-v2:16b model..."

# Check if the model exists
if ! ollama list | grep -q "deepseek-coder-v2:16b"; then
    echo "deepseek-coder-v2:16b model not found. Pulling model..."
    ollama pull deepseek-coder-v2:16b
    
    if [ $? -eq 0 ]; then
        echo "Successfully pulled deepseek-coder-v2:16b model"
    else
        echo "Failed to pull deepseek-coder-v2:16b model"
        exit 1
    fi
else
    echo "deepseek-coder-v2:16b model already exists"
fi

# List all available models
echo "Available models:"
ollama list

# Keep the container running
wait