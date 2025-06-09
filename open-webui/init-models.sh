#!/bin/bash
# open-webui/init-models.sh - Download and configure DeepSeek model

set -e

echo "=== DeepSeek Model Initialization ==="

# Wait for Ollama API to be ready
echo "⏳ Waiting for Ollama API to be ready..."
max_attempts=60
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama API is ready!"
        break
    fi
    
    attempt=$((attempt + 1))
    echo "Attempt $attempt/$max_attempts - waiting for Ollama..."
    sleep 5
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Ollama API failed to start after $max_attempts attempts"
    exit 1
fi

# Check available disk space
echo "💾 Checking available disk space..."
available_space=$(df /root/.ollama | awk 'NR==2 {print $4}')
required_space=20000000  # 20GB in KB

if [ "$available_space" -lt "$required_space" ]; then
    echo "⚠️  Warning: Low disk space. DeepSeek model requires ~20GB"
    echo "   Available: $(echo $available_space | awk '{printf "%.1fGB", $1/1024/1024}')"
    echo "   Required: ~20GB"
fi

# Check if DeepSeek model is already downloaded
echo "🔍 Checking for existing DeepSeek model..."
if ollama list | grep -q "deepseek-coder-v2:16b"; then
    echo "✅ DeepSeek-Coder-v2:16b model already exists"
    
    # Test the model
    echo "🧪 Testing model response..."
    test_response=$(curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{
            "model": "deepseek-coder-v2:16b",
            "prompt": "Hello",
            "stream": false,
            "options": {"num_predict": 5}
        }' | grep -o '"response":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$test_response" ]; then
        echo "✅ Model test successful: $test_response"
    else
        echo "⚠️  Model test failed, but model exists"
    fi
else
    echo "📥 Downloading DeepSeek-Coder-v2:16b model..."
    echo "⏱️  This will take 10-30 minutes depending on your internet connection"
    
    # Start the download
    if ollama pull deepseek-coder-v2:16b; then
        echo "✅ Successfully downloaded DeepSeek-Coder-v2:16b"
        
        # Test the newly downloaded model
        echo "🧪 Testing downloaded model..."
        sleep 5  # Wait a moment for model to be ready
        
        test_response=$(curl -s -X POST http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d '{
                "model": "deepseek-coder-v2:16b",
                "prompt": "Hello",
                "stream": false,
                "options": {"num_predict": 5}
            }' | grep -o '"response":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$test_response" ]; then
            echo "✅ Model download and test successful: $test_response"
        else
            echo "⚠️  Model downloaded but test failed"
        fi
    else
        echo "❌ Failed to download DeepSeek-Coder-v2:16b"
        echo "🔄 Retrying in 30 seconds..."
        sleep 30
        
        if ollama pull deepseek-coder-v2:16b; then
            echo "✅ Successfully downloaded DeepSeek-Coder-v2:16b on retry"
        else
            echo "❌ Failed to download DeepSeek-Coder-v2:16b after retry"
            echo "💡 You can manually download later with: docker exec <container> ollama pull deepseek-coder-v2:16b"
        fi
    fi
fi

# Display final status
echo ""
echo "📋 Current model status:"
ollama list

echo ""
echo "💾 Storage usage:"
du -sh /root/.ollama/models/* 2>/dev/null || echo "No models directory found"

echo ""
echo "=== Model initialization complete ==="
echo "🎉 Open WebUI should now be ready with DeepSeek-Coder-v2:16b"