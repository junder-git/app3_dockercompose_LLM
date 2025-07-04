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

# Set Ollama data directory
ENV OLLAMA_MODELS=/home/ollama/.ollama/models

# Expose port
EXPOSE 11434

# Switch to ollama user for running the service
USER ollama
WORKDIR /home/ollama

# Use the initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]