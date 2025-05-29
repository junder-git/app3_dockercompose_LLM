FROM ollama/ollama:0.7.0

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    jq \
    && rm -rf /var/lib/apt/lists/*

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