FROM ollama/ollama:latest

# Only install essential packages if needed
# curl and bash should already be available in the base image
RUN apt-get update && \
    apt-get install -y --fix-broken --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* || true

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