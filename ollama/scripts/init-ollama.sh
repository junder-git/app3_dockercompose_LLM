#!/bin/bash

# Get model name from environment variable
MODEL_NAME=${OLLAMA_MODEL:-"deepseek-coder-v2:16b"}

echo "=== Ollama Initialization ==="
echo "Target model: $MODEL_NAME"
echo "Starting Ollama service..."

# Start Ollama service in the background with specific configurations
OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=5m ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready with better error handling
echo "Waiting for Ollama to start..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✓ Ollama service is ready!"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - Ollama not ready yet, waiting..."
    sleep 2
    
    # Check if Ollama process is still running
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=5m ollama serve &
        OLLAMA_PID=$!
    fi
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "❌ Failed to start Ollama after $MAX_ATTEMPTS attempts"
    exit 1
fi

# Display current status
echo "Current Ollama status:"
curl -s http://localhost:11434/api/tags || echo "Could not fetch tags"

# Function to test model with better error handling
test_model() {
    local model_name="$1"
    echo "Testing model: $model_name"
    
    # Simple test to check if model responds correctly
    local test_response=$(curl -s -X POST http://localhost:11434/api/chat \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model_name\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}],
            \"stream\": false,
            \"options\": {
                \"num_predict\": 10,
                \"temperature\": 0.1,
                \"stop\": [\"<|im_end|>\", \"<|endoftext|>\"]
            }
        }" 2>/dev/null)
    
    if echo "$test_response" | grep -q "\"message\"" && ! echo "$test_response" | grep -q "error"; then
        echo "✓ Model $model_name is working correctly"
        return 0
    else
        echo "❌ Model $model_name test failed"
        echo "Response: $test_response"
        return 1
    fi
}

# Check if the specified model exists
echo "Checking for $MODEL_NAME model..."

# Try to create a custom model from Modelfile if it exists
if [ -f "/root/Modelfile" ]; then
    echo "Found Modelfile, creating custom model..."
    CUSTOM_MODEL_NAME="${MODEL_NAME}-custom"
    
    if ollama create "$CUSTOM_MODEL_NAME" -f /root/Modelfile 2>/dev/null; then
        echo "✓ Created custom model: $CUSTOM_MODEL_NAME"
        # Test the custom model
        if test_model "$CUSTOM_MODEL_NAME"; then
            echo "✓ Custom model is working, using it instead"
            export OLLAMA_MODEL="$CUSTOM_MODEL_NAME"
            MODEL_NAME="$CUSTOM_MODEL_NAME"
        else
            echo "⚠️ Custom model failed test, falling back to original"
        fi
    else
        echo "⚠️ Failed to create custom model, using original"
    fi
fi

if ollama list | grep -q "$MODEL_NAME"; then
    echo "✓ $MODEL_NAME model already exists"
    if test_model "$MODEL_NAME"; then
        echo "✓ Model is working correctly"
    else
        echo "⚠️ Model exists but may have issues, continuing anyway..."
    fi
else
    echo "❌ $MODEL_NAME model not found. Available models:"
    ollama list
    
    echo "Attempting to pull $MODEL_NAME model..."
    if ollama pull "$MODEL_NAME"; then
        echo "✓ Successfully pulled $MODEL_NAME model"
        
        # Test the newly pulled model
        echo "Testing newly pulled model..."
        sleep 5  # Give model time to load
        if test_model "$MODEL_NAME"; then
            echo "✓ New model is working correctly"
        else
            echo "⚠️ New model may have issues but continuing..."
        fi
    else
        echo "❌ Failed to pull $MODEL_NAME model"
        echo "Trying alternative model names..."
        
        # Try different model names based on the requested model
        if [[ "$MODEL_NAME" == *"deepseek-coder-v2"* ]]; then
            alt_models=("deepseek-coder-v2" "deepseek-coder-v2:latest" "deepseek-coder:latest" "deepseek-coder")
        elif [[ "$MODEL_NAME" == *"deepseek-coder"* ]]; then
            alt_models=("deepseek-coder" "deepseek-coder:latest" "deepseek-coder:33b" "deepseek-coder:7b")
        else
            alt_models=("deepseek-coder-v2:16b" "deepseek-coder:latest" "llama3.2" "phi3")
        fi
        
        MODEL_FOUND=false
        for model in "${alt_models[@]}"; do
            echo "Trying to pull $model..."
            if ollama pull "$model"; then
                echo "✓ Successfully pulled $model"
                
                # Test the alternative model
                sleep 5
                if test_model "$model"; then
                    export OLLAMA_MODEL="$model"
                    MODEL_NAME="$model"
                    echo "✓ Updated model to: $model"
                    MODEL_FOUND=true
                    break
                else
                    echo "⚠️ Model $model pulled but has issues, trying next..."
                fi
            else
                echo "❌ Failed to pull $model"
            fi
        done
        
        if [ "$MODEL_FOUND" = false ]; then
            echo "❌ Could not find a working model. Listing available models:"
            ollama list
            echo "The service will continue but may not work properly."
        fi
    fi
fi

# List all available models
echo "Final model list:"
ollama list

# Set up signal handlers for graceful shutdown
cleanup() {
    echo "Shutting down Ollama..."
    kill $OLLAMA_PID 2>/dev/null
    wait $OLLAMA_PID 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT

# Final status check
echo "=== Ollama Initialization Complete ==="
echo "Active model: $MODEL_NAME"
echo "Service PID: $OLLAMA_PID"
echo "API endpoint: http://localhost:11434"
echo "Keeping service running..."

# Keep the container running and monitor the process
while true; do
    if ! kill -0 $OLLAMA_PID 2>/dev/null; then
        echo "❌ Ollama process died, restarting..."
        OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=5m ollama serve &
        OLLAMA_PID=$!
        sleep 5
    fi
    sleep 30
done