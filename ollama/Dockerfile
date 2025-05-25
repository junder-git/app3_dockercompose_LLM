FROM ollama/ollama:latest

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Copy initialization script
COPY scripts/init-ollama.sh /scripts/init-ollama.sh
RUN chmod +x /scripts/init-ollama.sh

# Set working directory
WORKDIR /root

# Expose Ollama port
EXPOSE 11434

# Set entrypoint to initialization script
ENTRYPOINT ["/scripts/init-ollama.sh"]