FROM ollama/ollama:latest

# Set environment variables
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_KEEP_ALIVE=-1
ENV OLLAMA_MAX_LOADED_MODELS=1
ENV OLLAMA_MODELS=/root/.ollama/models

# Create necessary directories
RUN mkdir -p /root/.ollama/models /tmp/ollama_cache

# Install curl if not present (for healthchecks)
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy startup script
RUN mkdir -p /app
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Expose the default port
EXPOSE 11434

# Override the ENTRYPOINT and use our custom script
ENTRYPOINT []
CMD ["/app/start.sh"]