FROM ubuntu:20.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV OLLAMA_HOST=0.0.0.0

# Install dependencies first
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    bash \
    ca-certificates \
    gpg \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Copy initialization script and Modelfile  
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
COPY Modelfile /root/Modelfile
RUN chmod +x /scripts/init-ollama.sh

# Set working directory
WORKDIR /root

# Expose Ollama port
EXPOSE 11434

# Set entrypoint to initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]