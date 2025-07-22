FROM ollama/ollama:latest

# Install curl for health checks and envsubst for template processing
RUN apt-get update && \
    apt-get install -y curl gettext-base && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /root/.ollama/models

# Copy the GGUF model file
COPY models/Devstral-Small-2507-Q4_K_M.gguf /root/.ollama/models/Devstral-Small-2507-Q4_K_M.gguf

# Copy the initialization script and make it executable
COPY init-ollama.sh /root/.ollama/init-ollama.sh
RUN chmod +x /root/.ollama/init-ollama.sh

# Copy the Modelfile template
COPY Modelfile /root/.ollama/Modelfile

# Set the entrypoint to our initialization script
ENTRYPOINT ["/root/.ollama/init-ollama.sh"]