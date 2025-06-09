# Open WebUI + Ollama with DeepSeek-Coder Setup

A production-ready setup for Open WebUI with Ollama and DeepSeek-Coder-v2:16b model, featuring NGINX reverse proxy with HTTPS and IP whitelisting.

## 🏗️ Project Structure

```
├── docker-compose.yml
├── .env
├── README.md
└── nginx/
    ├── Dockerfile
    ├── nginx.conf
    └── error-pages/
        ├── wrong-subdomain.html
        └── rate-limited.html
```

## 🚀 Quick Start

1. **Clone and navigate to the project directory**

2. **Configure environment variables**
   ```bash
   # Edit .env file - IMPORTANT: Change default admin credentials!
   nano .env
   ```

3. **Build and start the services**
   ```bash
   docker-compose up --build
   ```

4. **Access the application**
   - Production: https://ai.junder.uk
   - First login: Use credentials from .env file (admin@junder.uk / admin123 by default)
   - **Download DeepSeek model**: Settings → Models → Download `deepseek-coder-v2:16b`
   - Other subdomains: Show error page with redirect

## 🔧 Configuration

### Environment Variables (.env)

- `SECRET_KEY`: Secret key for Open WebUI sessions
- `OLLAMA_MEMORY_LIMIT`: Maximum memory for the container (default: 20G)
- `NVIDIA_VISIBLE_DEVICES`: GPU access (default: all)
- `ENABLE_SIGNUP`: Allow new user registration (default: true)
- `WEBUI_URL`: Full HTTPS URL for Open WebUI (default: https://ai.junder.uk)
- `DEFAULT_USER_EMAIL`: Admin user email (default: admin@junder.uk)
- `DEFAULT_USER_NAME`: Admin user display name (default: Admin)
- `DEFAULT_USER_PASSWORD`: Admin user password (default: admin123)

**Important**: Change the default admin credentials in production!
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

### Traffic Flow Configuration

**Complete HTTPS Chain:**
1. **Client** → HTTPS:443 → **Cloudflare Load Balancer** (SSL termination)
2. **Cloudflare** → HTTPS:443 → **Your Router**  
3. **Router** → HTTPS:443 → **NGINX Container** (receives HTTPS, no SSL certs needed)
4. **NGINX** → HTTP:8080 → **Open WebUI Container**

**NGINX Configuration:**
- Listens on port 443 for HTTPS traffic from Cloudflare
- No SSL certificates needed (Cloudflare handles SSL termination)
- Forwards decrypted HTTP traffic to Open WebUI on port 8080
- Sets `X-Forwarded-Proto: https` header so Open WebUI knows it's HTTPS

### Domain Configuration

The NGINX configuration is set up for **ai.junder.uk** with rate limiting:

- **Correct domain**: `ai.junder.uk` - serves the AI chat application
- **Other junder.uk subdomains**: 
  - Shows styled error page for 30 seconds
  - Rate limited to 1 request per minute per IP
  - Auto-redirects to ai.junder.uk after 30 seconds
  - Additional requests show rate limit error page
- **Invalid domains**: Connection closed (return 444)

**Rate Limiting Behavior:**
- First request: Shows wrong subdomain page with 30-second countdown
- Subsequent requests within 1 minute: Shows rate limited error page
- After 1 minute: IP can make one new request

## 📊 Backend Information

**Open WebUI uses:**
- **Database**: SQLite (built-in, stored in `/app/backend/data`)
- **File Storage**: Local filesystem
- **Session Management**: Built-in Python session handling
- **User Authentication**: Built-in user management system
- **Model Management**: Direct integration with Ollama API
- **Startup**: Official bundled image with automatic Ollama + Open WebUI startup

**Model Installation:**
- Models are **NOT** pre-installed in the container
- Download models after deployment via:
  1. **Web UI**: Settings → Models → Download `deepseek-coder-v2:16b`
  2. **CLI**: `docker exec ai-open-webui-ollama ollama pull deepseek-coder-v2:16b`

No external database (Redis, PostgreSQL, etc.) is required.

## 🎯 Features

- ✅ **Official Open WebUI + Ollama image** - No custom startup scripts needed
- ✅ **Configurable default admin user** - Set credentials via environment variables
- ✅ **Smart domain routing** - Only serves ai.junder.uk with rate limited error pages  
- ✅ **Rate limiting protection** - Prevents subdomain spam (1 request per minute)
- ✅ **Cloudflare integration** - Proper real IP handling and edge termination
- ✅ **IP whitelisting** hardcoded in nginx.conf
- ✅ **Auto-downloads models** on first use or manual trigger
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

### Check model download progress
```bash
# Check if model is downloaded
docker exec ai-open-webui-ollama ollama list

# Manually download DeepSeek model
docker exec ai-open-webui-ollama ollama pull deepseek-coder-v2:16b

# Check download progress
docker exec ai-open-webui-ollama ollama ps
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

1. **Cloudflare edge termination** - Traffic handled at the edge
2. **IP whitelisting** - Hardcoded in nginx.conf for security
3. **Rate limiting** - Prevents abuse with different limits per endpoint
4. **Security headers** - XSS protection, content type sniffing prevention
5. **No direct container access** - Only accessible through NGINX
6. **Real IP detection** - Proper handling of Cloudflare IPs
7. **Configurable admin credentials** - Set via environment variables

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

3. **Certificate warnings**
   - Only relevant for direct access (bypassing Cloudflare)
   - Production should use Cloudflare for edge termination

4. **Default admin credentials**
   ```bash
   # Change default credentials in .env file before first startup
   DEFAULT_USER_EMAIL=your-email@domain.com
   DEFAULT_USER_PASSWORD=your-secure-password
   ```

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