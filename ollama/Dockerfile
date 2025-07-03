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
    && rm -rf /var/lib/apt/lists/*

# Install Ollama (CACHED - very expensive operation)
RUN curl -fsSL https://ollama.com/install.sh | sh

# Set working directory (CACHED)
WORKDIR /root

# Build argument to force rebuild ONLY for file copies
ARG CACHEBUST=1

# CRITICAL: Copy files that change frequently AFTER the cache bust
# This ensures Docker will rebuild these layers when files change
# but keeps all the expensive install operations cached

# Copy initialization script first
COPY scripts/init-ollama.sh /scripts/init-ollama.sh

# Copy Modelfile 
COPY Modelfile /root/Modelfile

# Set permissions (this will also be invalidated when files change)
RUN chmod +x /scripts/init-ollama.sh

# Expose Ollama port
EXPOSE 11434

# Set entrypoint to initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]