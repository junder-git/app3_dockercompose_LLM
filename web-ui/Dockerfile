# File: Dockerfile
# Directory: /deepseek-coder-setup/web-ui/

FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create directories for static files and templates
RUN mkdir -p /app/static/css /app/static/js /app/static/temp /app/templates

# Set permissions
RUN chmod -R 755 /app

# Expose port for Quart
EXPOSE 8000

# Command to run the application with Hypercorn
CMD ["hypercorn", "app:app", "--bind", "0.0.0.0:8000", "--workers", "1"]