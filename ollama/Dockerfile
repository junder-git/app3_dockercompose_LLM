# File: Dockerfile
# Directory: /deepseek-coder-setup/ollama/

FROM ollama/ollama:latest

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create a startup script that checks if model exists and pulls if needed
RUN echo '#!/bin/sh \n\
# Start Ollama in the background \n\
ollama serve & \n\
OLLAMA_PID=$! \n\
\n\
# Wait for Ollama to start \n\
echo "Waiting for Ollama to start..." \n\
sleep 10 \n\
\n\
# Check if model is already pulled \n\
if ! ollama list | grep -q "deepseek-coder:6.7b-instruct-q5_K_M"; then \n\
    echo "DeepSeek model not found, pulling now..." \n\
    ollama pull deepseek-coder:6.7b-instruct-q5_K_M \n\
    echo "Model pulled successfully!" \n\
else \n\
    echo "DeepSeek model already available" \n\
fi \n\
\n\
# Kill the background Ollama process \n\
kill $OLLAMA_PID \n\
\n\
# Start Ollama in the foreground \n\
echo "Starting Ollama server..." \n\
exec ollama serve \n\
' > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

# Set the startup script as the entrypoint
ENTRYPOINT ["/usr/local/bin/start.sh"]