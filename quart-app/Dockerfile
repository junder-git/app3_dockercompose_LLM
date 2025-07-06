FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Set environment variables for proper logging
ENV PYTHONUNBUFFERED=1
ENV PYTHONIOENCODING=utf-8

# Expose port
EXPOSE 8000

# Run with Hypercorn - REDUCED workers for stability
CMD ["hypercorn", "app:app", "--bind", "0.0.0.0:8000", "--workers", "1", "--worker-class", "asyncio", "--access-logfile", "-", "--error-logfile", "-"]