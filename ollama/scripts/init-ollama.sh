#!/bin/bash

# Start Ollama service in the background
ollama serve &

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
while ! curl -s http://localhost:11434/api/tags > /dev/null; do
    sleep 1
done

echo "Ollama is ready. Checking for deepseek-r1:32b model..."

# Check if the model exists
if ! ollama list | grep -q "deepseek-r1:32b"; then
    echo "deepseek-r1:32b model not found. Pulling model..."
    ollama pull deepseek-r1:32b
    
    if [ $? -eq 0 ]; then
        echo "Successfully pulled deepseek-r1:32b model"
    else
        echo "Failed to pull deepseek-r1:32b model"
        exit 1
    fi
else
    echo "deepseek-r1:32b model already exists"
fi

# List all available models
echo "Available models:"
ollama list

# Keep the container running
wait