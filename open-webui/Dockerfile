# open-webui/Dockerfile - Custom Open WebUI with Ollama and DeepSeek model
FROM ghcr.io/open-webui/open-webui:ollama

# Set working directory
WORKDIR /app

# Copy initialization script
COPY init-models.sh /app/init-models.sh
COPY entrypoint.sh /app/entrypoint.sh

# Make scripts executable
RUN chmod +x /app/init-models.sh /app/entrypoint.sh

# Install curl for health checks (if not already present)
USER root
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
USER $UID

# Set custom entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]