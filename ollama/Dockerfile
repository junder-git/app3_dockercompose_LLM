FROM ollama/ollama:latest

# Create necessary directories
RUN mkdir -p /root/.ollama/models

# Copy the GGUF model file
COPY models/Devstral-Small-2507-Q4_K_M.gguf /root/.ollama/models/Devstral-Small-2507-Q4_K_M.gguf

# Copy the initialization script and make it executable
COPY scripts/init-ollama.sh /root/.ollama/scripts/init-ollama.sh
RUN chmod +x /root/.ollama/scripts/init-ollama.sh

# Copy the Modelfile template
COPY scripts/Modelfile /root/.ollama/scripts/Modelfile

# Set the entrypoint to our initialization script
ENTRYPOINT ["/root/.ollama/scripts/init-ollama.sh"]