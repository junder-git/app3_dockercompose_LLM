# Multi-stage build for better caching
FROM ubuntu:22.04 AS downloader

# Install minimal dependencies for downloading
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Download Ollama (this layer will be cached unless the install script changes)
RUN curl -fsSL https://ollama.com/install.sh -o /tmp/install.sh && \
    chmod +x /tmp/install.sh

# Main stage
FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies (this layer will be cached)
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

# Create ollama user and directories (this layer will be cached)
RUN useradd -m -s /bin/bash ollama && \
    mkdir -p /home/ollama/.ollama && \
    chown -R ollama:ollama /home/ollama

# Copy and run the install script (more predictable than direct curl)
COPY --from=downloader /tmp/install.sh /tmp/install.sh
RUN /tmp/install.sh && rm /tmp/install.sh

# Copy scripts and configs with proper permissions (cached unless files change)
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
COPY Modelfile /home/ollama/Modelfile

# Set permissions (cached unless files change)
RUN chmod +x /scripts/init-ollama.sh && \
    chown ollama:ollama /home/ollama/Modelfile && \
    chmod 644 /home/ollama/Modelfile

# Set Ollama data directory
ENV OLLAMA_MODELS=/home/ollama/.ollama/models

# Expose port
EXPOSE 11434

# Switch to ollama user for running the service
USER root
WORKDIR /home/ollama

# Use the initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]