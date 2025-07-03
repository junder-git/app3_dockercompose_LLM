#!/bin/bash
# docker-compose-startup.sh - Privileged mode for mlock support

set -e

echo "🚀 Starting Devstral AI Chat with Privileged Mode"
echo "================================================="
echo "⚠️  WARNING: Using privileged mode for memory locking"
echo "⚠️  This gives the Ollama container full access to host resources"
echo "⚠️  Only use this in trusted environments"
echo "================================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose > /dev/null 2>&1; then
    echo "❌ docker-compose not found. Please install docker-compose."
    exit 1
fi

# Check if NVIDIA Docker runtime is available
if ! docker info 2>/dev/null | grep -q nvidia; then
    echo "⚠️  NVIDIA Docker runtime not detected. GPU acceleration may not work."
    echo "   Install nvidia-container-toolkit if you have an NVIDIA GPU"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create required directories
echo "📁 Creating required directories..."
mkdir -p volumes/ollama_models
mkdir -p volumes/redis_data

# Set proper permissions
sudo chown -R $USER:$USER volumes/

# Copy environment file if it doesn't exist
if [ ! -f .env ]; then
    echo "📄 Creating .env file..."
    if [ -f .env.example ]; then
        cp .env.example .env
    else
        echo "❌ No .env or .env.example file found. Please create one."
        exit 1
    fi
fi

# Show current configuration
echo "🔧 Current configuration:"
echo "   Model: $(grep OLLAMA_MODEL .env | cut -d'=' -f2)"
echo "   GPU Layers: $(grep OLLAMA_GPU_LAYERS .env | cut -d'=' -f2)"
echo "   Memory Lock: $(grep OLLAMA_MLOCK .env | cut -d'=' -f2)"
echo "   Memory Map: $(grep OLLAMA_MMAP .env | cut -d'=' -f2)"

# Ask for confirmation
echo ""
echo "🔒 SECURITY NOTICE:"
echo "   This will run the Ollama container in privileged mode"
echo "   Privileged mode gives the container full access to host resources"
echo "   This is required for memory locking (mlock) to work properly"
echo ""
read -p "Do you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborted by user"
    exit 1
fi

# Start services
echo "🚀 Starting services with privileged mode..."
echo "   This may take 10-15 minutes for initial model loading..."

# Pull latest images
echo "📦 Pulling latest images..."
docker-compose pull

# Build and start services
echo "🏗️  Building and starting services..."
docker-compose up -d --build

# Show status
echo ""
echo "✅ Services started successfully!"
echo ""
echo "📊 Service Status:"
docker-compose ps

echo ""
echo "🔍 Monitoring startup progress..."
echo "   Use 'docker-compose logs -f ollama' to monitor model loading"
echo "   Use 'docker-compose logs -f' to monitor all services"
echo ""
echo "🌐 Access points:"
echo "   Web Interface: http://localhost"
echo "   Admin Panel: http://localhost/admin"
echo "   Health Check: http://localhost/health"
echo ""
echo "👤 Default credentials:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "⚠️  Remember to change default credentials in production!"

# Optional: Follow logs
read -p "Follow startup logs? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📋 Following logs... (Press Ctrl+C to stop)"
    docker-compose logs -f
fi