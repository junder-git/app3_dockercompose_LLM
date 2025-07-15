# Multi-stage build with volume-based caching
FROM ubuntu:22.04 AS base

# Define build argument for Ollama version
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

# Copy install script and startup script
COPY scripts/install.sh /scripts/install-ollama.sh
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
COPY scripts/check-install.sh /scripts/check-install.sh

# Make scripts executable
RUN chmod +x /scripts/install-ollama.sh && \
    chmod +x /scripts/init-ollama.sh && \
    chmod +x /scripts/check-install.sh

# Copy application files
COPY Modelfile /home/ollama/Modelfile
RUN chown ollama:ollama /home/ollama/Modelfile && \
    chmod 644 /home/ollama/Modelfile

# Set environment variables
ENV OLLAMA_MODELS=/home/ollama/.ollama/models
ENV OLLAMA_BINARY_CACHE=/ollama-cache

# Create cache directory
RUN mkdir -p /ollama-cache && chown ollama:ollama /ollama-cache

# Expose port
EXPOSE 11434

# Runtime configuration
USER root
WORKDIR /home/ollama

# Use the check-install script as entrypoint
ENTRYPOINT ["/scripts/check-install.sh"]