FROM ubuntu:20.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV OLLAMA_HOST=0.0.0.0

# Install dependencies first (CACHED - expensive operations)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    bash \
    ca-certificates \
    gpg \
    jq \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama (CACHED - very expensive operation)
RUN curl -fsSL https://ollama.com/install.sh | sh

# Set working directory (CACHED)
WORKDIR /root

# Build argument to force rebuild ONLY for file copies
ARG CACHEBUST=1

# Copy files and set permissions in one layer
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
COPY Modelfile /root/Modelfile
RUN chmod +x /scripts/init-ollama.sh

# CRITICAL: Set environment variables that Ollama will inherit
ENV OLLAMA_MLOCK=true
ENV OLLAMA_MMAP=false
ENV OLLAMA_KEEP_ALIVE=-1
ENV OLLAMA_NOPRUNE=true
ENV OLLAMA_MAX_LOADED_MODELS=1

# Expose Ollama port
EXPOSE 11434

# Set entrypoint to initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]