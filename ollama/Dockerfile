# Multi-stage build with maximum caching
FROM ubuntu:22.04 AS base

# Define build argument for Ollama version (gets value from docker-compose)
ARG OLLAMA_VERSION

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies (cached unless dependencies change)
RUN apt-get update && \
    apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    gettext-base \
    bc \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create ollama user and directories (cached unless user setup changes)
RUN useradd -m -s /bin/bash ollama && \
    mkdir -p /home/ollama/.ollama && \
    chown -R ollama:ollama /home/ollama

# Install Ollama - Direct binary download (MOST RELIABLE CACHING)
RUN curl -fsSL "https://github.com/ollama/ollama/releases/download/v${VERSION_TAG}/ollama-linux-amd64" -o /usr/local/bin/ollama && \
    chmod +x /usr/local/bin/ollama

# Copy application files (cached unless these specific files change)
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
COPY Modelfile /home/ollama/Modelfile

# Set permissions (cached unless files change)
RUN chmod +x /scripts/init-ollama.sh && \
    chown ollama:ollama /home/ollama/Modelfile && \
    chmod 644 /home/ollama/Modelfile

# Set environment variables
ENV OLLAMA_MODELS=/home/ollama/.ollama/models

# Expose port
EXPOSE 11434

# Runtime configuration
USER root
WORKDIR /home/ollama

# Use the initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]