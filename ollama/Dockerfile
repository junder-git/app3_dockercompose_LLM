FROM ollama/ollama:latest

# Create necessary directories
RUN mkdir -p /root/.ollama/models
RUN mkdir -p /root/.ollama/scripts

# Set the entrypoint to our initialization script
ENTRYPOINT ["/root/.ollama/scripts/init-ollama.sh"]