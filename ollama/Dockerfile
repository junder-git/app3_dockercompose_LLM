# Linux-based Ollama Dockerfile with install script
FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Create ollama user and directories
RUN useradd -m -s /bin/bash ollama && \
    mkdir -p /home/ollama/.ollama && \
    chown -R ollama:ollama /home/ollama

# Install Ollama using official install script
RUN curl -fsSL https://ollama.com/install.sh | sh

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

# Set Ollama data directory
ENV OLLAMA_MODELS=/home/ollama/.ollama/models

# Expose port
EXPOSE 11434

# Switch to ollama user for running the service
USER ollama
WORKDIR /home/ollama

# Use the initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]