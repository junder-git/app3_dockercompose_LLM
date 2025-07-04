# Simplified Ollama Dockerfile - Official image compatibility
FROM ollama/ollama:latest

# Install curl for health checks
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Copy scripts and configs
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
COPY Modelfile /root/Modelfile

# Set permissions
RUN chmod +x /scripts/init-ollama.sh

# Environment variables for optimization
ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_MLOCK=true
ENV OLLAMA_MMAP=false
ENV OLLAMA_KEEP_ALIVE=-1
ENV OLLAMA_NOPRUNE=true
ENV OLLAMA_MAX_LOADED_MODELS=1
ENV OLLAMA_GPU_LAYERS=22
ENV OLLAMA_NUM_THREAD=4
ENV OLLAMA_CONTEXT_SIZE=16384
ENV OLLAMA_BATCH_SIZE=256

# Expose port
EXPOSE 11434

# Use the simplified initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]