# DeepSeek-Coder AI Chat Application

A complete AI chat application using DeepSeek-Coder models with Docker containerization, featuring web UI, Redis persistence, NGINX reverse proxy, and GitHub integration.

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose installed
- NVIDIA Docker runtime (optional, for GPU acceleration)
- At least 16GB RAM (32GB recommended for larger models)
- 50GB free disk space

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd deepseek-coder-setup
chmod +x docker-compose-startup.sh
./docker-compose-startup.sh
```

### 2. Manual Setup (Alternative)

```bash
# Copy environment file
cp example.env .env

# Edit configuration
nano .env

# Start services
docker-compose up -d --build
```

### 3. Access Application

- **Web Interface**: http://localhost
- **Default Login**: admin / admin123
- **API Docs**: http://localhost/api (if implemented)

## 📋 Features

### Core Features
- 🤖 **AI Chat Interface** - Clean, responsive web UI
- 💾 **Persistent Storage** - Redis-based chat history and user management
- 🔐 **User Authentication** - Secure login system with admin panel
- 📱 **Session Management** - Multiple chat sessions per user (max 5)
- ⚡ **Real-time Streaming** - WebSocket-based streaming responses
- 🎨 **Syntax Highlighting** - Code blocks with copy functionality
- 📊 **Admin Dashboard** - User management and database tools

### GitHub Integration
- 🐙 **Repository Browser** - Browse and load files from GitHub repos
- 📝 **Gist Creation** - Create GitHub gists from code blocks
- 🔑 **Token Management** - Secure server-side token storage
- 📁 **File Loading** - Load repository files directly into chat

### Technical Features
- 🌐 **NGINX Reverse Proxy** - Load balancing and rate limiting
- 🐳 **Docker Containerization** - Easy deployment and scaling
- 🚀 **GPU Acceleration** - NVIDIA GPU support for faster inference
- 💨 **Response Caching** - Redis-based response caching
- 🛡️ **Security** - CSRF protection, XSS prevention, rate limiting
- 📈 **Resource Management** - Configurable memory and CPU limits

## 🏗️ Architecture

```
├── nginx/                 # Reverse proxy and static files
│   ├── static/           # CSS, JS, and static assets
│   └── nginx.conf        # NGINX configuration
├── quart-app/            # Python web application
│   ├── blueprints/       # Modular route handlers
│   ├── templates/        # Jinja2 HTML templates
│   └── app.py           # Main application
├── ollama/               # AI model service
│   └── scripts/         # Model initialization scripts
├── redis/                # Database service
│   └── redis.conf       # Redis configuration
└── docker-compose.yml   # Service orchestration
```

## ⚙️ Configuration

### Environment Variables (.env)

```env
# Security
SECRET_KEY=your-secret-key
ADMIN_USERNAME=admin
ADMIN_PASSWORD=admin123

# AI Model
OLLAMA_MODEL=deepseek-coder-v2:16b
MODEL_TEMPERATURE=0.7
MODEL_MAX_TOKENS=2048

# Performance
OLLAMA_MEMORY_LIMIT=16G
RATE_LIMIT_MESSAGES_PER_MINUTE=10
CHAT_CACHE_TTL_SECONDS=3600
```

### Supported Models

The application supports various DeepSeek models:
- `deepseek-coder-v2:16b` (recommended)
- `deepseek-coder-v2:7b` (lighter)
- `deepseek-coder:33b` (larger)
- `deepseek-coder:latest`

## 🔧 Development

### Local Development

```bash
# Start in development mode
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# View logs
docker-compose logs -f quart-app

# Rebuild specific service
docker-compose up -d --build quart-app
```

### Database Management

Access the admin panel at `/admin` to:
- View user statistics
- Manage chat sessions
- Clean up database
- Download backups
- Monitor system health

### Adding New Features

The application uses a modular blueprint structure:
- Add new routes in `quart-app/blueprints/`
- Create templates in `quart-app/templates/`
- Add static assets in `nginx/static/`

## 📚 API Reference

### WebSocket API

Connect to `/ws` for real-time chat:

```javascript
const ws = new WebSocket('ws://localhost/ws');
ws.send(JSON.stringify({
    type: 'chat',
    message: 'Hello, AI!'
}));
```

### REST API

- `GET /api/chat/history` - Get chat history
- `POST /api/chat/sessions` - Create new session
- `GET /api/admin/users` - List users (admin only)
- `POST /api/github/settings` - Save GitHub token

## 🚀 Production Deployment

### Docker Swarm

```bash
# Initialize swarm
docker swarm init

# Deploy stack
docker stack deploy -c docker-compose.yml deepseek-stack
```

### Kubernetes

```bash
# Generate Kubernetes manifests
kompose convert

# Apply manifests
kubectl apply -f .
```

### Performance Tuning

For production environments:

```env
# Increase worker processes
APP_WORKERS=8

# Enable secure cookies
SECURE_COOKIES=true

# Optimize memory usage
OLLAMA_MEMORY_LIMIT=32G
REDIS_MEMORY_LIMIT=4G
```

## 🛠️ Troubleshooting

### Common Issues

1. **Model not downloading**
   ```bash
   docker exec -it ai-ollama ollama pull deepseek-coder-v2:16b
   ```

2. **GPU not detected**
   ```bash
   # Check NVIDIA runtime
   docker info | grep nvidia
   
   # Install nvidia-container-toolkit
   sudo apt install nvidia-container-toolkit
   ```

3. **Out of memory errors**
   ```bash
   # Reduce model size or increase memory limits
   OLLAMA_MODEL=deepseek-coder-v2:7b
   ```

4. **Redis connection issues**
   ```bash
   # Check Redis health
   docker exec ai-redis redis-cli ping
   ```

### Logs and Monitoring

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f quart-app
docker-compose logs -f ollama
docker-compose logs -f nginx

# Monitor resource usage
docker stats
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Guidelines

- Follow PEP 8 for Python code
- Use ESLint for JavaScript
- Add docstrings to functions
- Update documentation for new features

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [DeepSeek](https://deepseek.com/) for the AI models
- [Ollama](https://ollama.ai/) for model serving
- [Quart](https://quart.palletsprojects.com/) for the async web framework
- [Redis](https://redis.io/) for data persistence

## 📞 Support

- Create an issue for bug reports
- Join discussions for feature requests
- Check the wiki for additional documentation

---

**Made with ❤️ for the AI community**