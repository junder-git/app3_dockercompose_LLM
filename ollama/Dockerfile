FROM ollama/ollama:latest

# Install curl for health checks and envsubst for template processing
RUN apt-get update && \
    apt-get install -y gettext-base && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /root/.ollama/models
RUN mkdir -p /root/.ollama/scripts

# Copy the initialization script and make it executable
COPY scripts/init-ollama.sh /root/.ollama/scripts/init-ollama.sh
RUN chmod +x /root/.ollama/scripts/init-ollama.sh

# Copy the Modelfile template
COPY scripts/Modelfile /root/.ollama/scripts/Modelfile

# Set the entrypoint to our initialization script
ENTRYPOINT ["/root/.ollama/scripts/init-ollama.sh"]