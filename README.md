# Open WebUI + Ollama with DeepSeek-Coder Setup

A production-ready setup for Open WebUI with Ollama and DeepSeek-Coder-v2:16b model, featuring NGINX reverse proxy with HTTPS and IP whitelisting.

## 🏗️ Project Structure

```
├── docker-compose.yml
├── .env
├── README.md
├── nginx/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── error-pages/
│       ├── wrong-subdomain.html
│       └── rate-limited.html
└── open-webui/
    ├── Dockerfile
    ├── entrypoint.sh
    └── init-models.sh
```

## 🚀 Quick Start

1. **Clone and navigate to the project directory**

2. **Configure environment variables**
   ```bash
   # Edit .env file
   nano .env
   ```

3. **Build and start the services**
   ```bash
   docker-compose up --build
   ```

4. **Access the application**
   - Production: https://ai.junder.uk
   - Other subdomains: Show error page with redirect

## 🔧 Configuration

### Environment Variables (.env)

- `SECRET_KEY`: Secret key for Open WebUI sessions
- `OLLAMA_MEMORY_LIMIT`: Maximum memory for the container (default: 20G)
- `NVIDIA_VISIBLE_DEVICES`: GPU access (default: all)
- `ALLOWED_IPS`: IP whitelist (default: 0.0.0.0/0 - allow all)

### IP Whitelisting

To restrict access to specific IPs, modify the `geo $allowed_ip` block in `nginx/nginx.conf`:

```nginx
# Change from:
geo $allowed_ip {
    default 1;  # Allow all IPs
}

# To:
geo $allowed_ip {
    default 0;                      # Deny all by default
    127.0.0.1/32 1;               # Allow localhost
    192.168.0.0/16 1;             # Allow private network 192.168.x.x
    YOUR_PUBLIC_IP/32 1;          # Replace with your specific public IP
    YOUR_OFFICE_SUBNET/24 1;      # Replace with your office subnet
}
```

### SSL/HTTPS Configuration

SSL is terminated by **Cloudflare**. The NGINX container:
- Listens on both ports 80 and 443
- Uses dummy SSL certificates for direct access
- Properly handles Cloudflare's real IP headers (`CF-Connecting-IP`)
- Trusts Cloudflare IP ranges for accurate client IP detection

### Domain Configuration

The NGINX configuration is set up for **ai.junder.uk** with rate limiting:

- **Correct domain**: `ai.junder.uk` - serves the AI chat application
- **Other junder.uk subdomains**: 
  - Shows styled error page for 30 seconds
  - Rate limited to 1 request per 30 seconds per IP
  - Auto-redirects to ai.junder.uk after 30 seconds
  - Additional requests show rate limit error page
- **Invalid domains**: Connection closed (return 444)

**Rate Limiting Behavior:**
- First request: Shows wrong subdomain page with 30-second countdown
- Subsequent requests within 30 seconds: Shows rate limited error page
- After 30 seconds: IP can make one new request

## 📊 Backend Information

**Open WebUI uses:**
- **Database**: SQLite (built-in, stored in `/app/backend/data`)
- **File Storage**: Local filesystem
- **Session Management**: Built-in Python session handling
- **User Authentication**: Built-in user management system
- **Model Management**: Direct integration with Ollama API

No external database (Redis, PostgreSQL, etc.) is required.

## 🎯 Features

- ✅ **Smart domain routing** - Only serves ai.junder.uk with 30-second rate limited error pages
- ✅ **Rate limiting protection** - Prevents subdomain spam (1 request per 30 seconds)
- ✅ **Cloudflare SSL termination** with proper real IP handling
- ✅ **IP whitelisting** hardcoded in nginx.conf
- ✅ **Auto-downloads DeepSeek-Coder-v2:16b** model
- ✅ **GPU acceleration** with NVIDIA runtime
- ✅ **Rate limiting** and security headers
- ✅ **WebSocket support** for real-time chat
- ✅ **File upload support** up to 1GB
- ✅ **Health monitoring** with automatic restarts

## 🔍 Monitoring

### View logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f open-webui
docker-compose logs -f nginx
```

### Check model status
```bash
docker exec ai-open-webui-ollama ollama list
```

### Health checks
### Check application access
- Production: https://ai.junder.uk/health
- Container health: `docker ps` (shows health status)

## 🛠️ Management Commands

### Start services
```bash
docker-compose up -d
```

### Stop services
```bash
docker-compose down
```

### Rebuild and restart
```bash
docker-compose up --build -d
```

### Update Open WebUI
```bash
docker-compose pull
docker-compose up -d
```

### Access container shell
```bash
# Open WebUI container
docker exec -it ai-open-webui-ollama bash

# NGINX container
docker exec -it ai-nginx sh
```

## 📁 Data Persistence

- **Ollama models**: Stored in `ollama_data` volume
- **Open WebUI data**: Stored in `open_webui_data` volume (includes users, chats, settings)

## 🔐 Security Features

1. **Cloudflare SSL termination** - SSL handled at the edge
2. **IP whitelisting** - Hardcoded in nginx.conf for security
3. **Rate limiting** - Prevents abuse with different limits per endpoint
4. **Security headers** - XSS protection, content type sniffing prevention
5. **No direct container access** - Only accessible through NGINX
6. **Real IP detection** - Proper handling of Cloudflare IPs

## 🐛 Troubleshooting

### Common Issues

1. **GPU not detected**
   ```bash
   # Check NVIDIA runtime
   docker info | grep nvidia
   ```

2. **Model download fails**
   ```bash
   # Check container logs
   docker-compose logs open-webui
   
   # Manually download model
   docker exec ai-open-webui-ollama ollama pull deepseek-coder-v2:16b
   ```

3. **SSL certificate warnings**
   - Only relevant for direct access (bypassing Cloudflare)
   - Production should use Cloudflare for SSL termination

4. **Out of memory**
   - Increase `OLLAMA_MEMORY_LIMIT` in `.env`
   - Ensure sufficient system RAM (32GB+ recommended)

5. **Permission denied errors**
   ```bash
   # Fix permissions
   sudo chown -R $USER:$USER nginx/ssl/
   ```

## 📈 Resource Requirements

- **RAM**: 16GB minimum, 32GB recommended
- **Storage**: 25GB+ for DeepSeek model
- **GPU**: NVIDIA GPU with 8GB+ VRAM recommended
- **CPU**: 4+ cores recommended

## 🔄 Updates

The setup uses specific image tags for stability. To update:

1. Check for new releases on [Open WebUI GitHub](https://github.com/open-webui/open-webui