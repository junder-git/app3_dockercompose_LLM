FROM ollama/ollama:latest

# Set environment variables
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_KEEP_ALIVE=24h
ENV OLLAMA_MAX_LOADED_MODELS=4
ENV OLLAMA_MODELS=/root/.ollama/models

# Create necessary directories
RUN mkdir -p /root/.ollama/models /tmp/ollama_cache

# Install curl if not present (for healthchecks)
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy startup script
COPY start-ollama.sh /usr/local/bin/start-ollama.sh
RUN chmod +x /usr/local/bin/start-ollama.sh

# Expose the default port
EXPOSE 11434

# Use custom startup script
CMD ["/usr/local/bin/start-ollama.sh"]