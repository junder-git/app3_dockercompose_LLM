# Hybrid Approach: Official Ollama + Custom Optimizations
FROM ollama/ollama:latest

# Switch to root for customization
USER root

# Install additional tools for our advanced initialization
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    jq \
    procps \
    htop \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /root

# Build argument to force rebuild ONLY for file copies
ARG CACHEBUST=1

# Copy our advanced initialization script and Modelfile
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
COPY Modelfile /root/Modelfile

# Set permissions and prepare directories
RUN chmod +x /scripts/init-ollama.sh && \
    mkdir -p /tmp/ollama-health && \
    chown -R ollama:ollama /home/ollama

# CRITICAL: Set environment variables that will be inherited by Ollama
# These are the KEY optimizations for memory management
ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_MLOCK=true
ENV OLLAMA_MMAP=false
ENV OLLAMA_KEEP_ALIVE=-1
ENV OLLAMA_NOPRUNE=true
ENV OLLAMA_MAX_LOADED_MODELS=1
ENV OLLAMA_NUM_PARALLEL=1
ENV OLLAMA_LOAD_TIMEOUT=15m

# GPU and performance settings
ENV OLLAMA_GPU_LAYERS=22
ENV OLLAMA_NUM_THREAD=8
ENV OLLAMA_CONTEXT_SIZE=16384
ENV OLLAMA_BATCH_SIZE=256
ENV CUDA_VISIBLE_DEVICES=0

# Advanced memory settings (if supported)
ENV OLLAMA_NUMA=false
ENV OLLAMA_MAIN_GPU=0

# Expose Ollama port
EXPOSE 11434

# Use our custom initialization script but keep ollama user context
ENTRYPOINT ["/scripts/init-ollama.sh"]