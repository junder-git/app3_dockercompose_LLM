#!/bin/bash

# Start Ollama service in the background
ollama serve &

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
while ! curl -s http://localhost:11434/api/tags > /dev/null; do
    sleep 1
done

echo "Ollama is ready. Checking for deepseek-v3:671b model..."

# Check if the model exists
if ! ollama list | grep -q "deepseek-v3:671b"; then
    echo "deepseek-v3:671b model not found. Pulling model..."
    ollama pull deepseek-v3:671b
    
    if [ $? -eq 0 ]; then
        echo "Successfully pulled deepseek-v3:671b model"
    else
        echo "Failed to pull deepseek-v3:671b model"
        exit 1
    fi
else
    echo "deepseek-v3:671b model already exists"
fi

# List all available models
echo "Available models:"
ollama list

# Keep the container running
wait