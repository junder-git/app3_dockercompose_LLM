# File: Dockerfile.ollama
# Directory: /deepseek-coder-setup/

FROM ollama/ollama:latest

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create a non-root user to run Ollama
RUN groupadd -r ollama && useradd -r -g ollama ollama

# Create directory for Ollama data and set permissions
RUN mkdir -p /root/.ollama && chown -R ollama:ollama /root/.ollama

# Start Ollama server, pull the DeepSeek model, then stop the server
RUN ollama serve & \
    sleep 10 && \
    ollama pull deepseek-coder:6.7b-instruct-q5_K_M && \
    pkill ollama

# Default command to run when container starts
CMD ["ollama", "serve"]