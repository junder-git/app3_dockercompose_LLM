# LLM HARDWARE INIT / PRE-REQUISITES 
  
NOTE: You must run `pacman-key --init` before first using pacman; the local
keyring can then be populated with the keys of all official Arch Linux
packagers with `pacman-key --populate archlinux`.  

``` curl -L https://raw.githubusercontent.com/junder-git/app3_LLM/refs/heads/main/arch-uk-auto-installer.sh -o installer.sh && chmod +x installer.sh && ./installer.sh ``` -- server setup from arch usb to the actual server hardware. Consider vmware vcenter or something further down the line for lvm management.

After the installation completes and reboot:

Login with the credentials:

Username: docker
Password: docker

# The LLM DeepSeek-Coder Docker App Setup

A comprehensive Docker-based solution for running DeepSeek-Coder with NVIDIA GPU support, including a web UI, PostgreSQL-based authentication and persistence, and security features.

## Architecture

This system uses multiple Docker containers to provide a modular and maintainable architecture:

1. **PostgreSQL Container**: Handles authentication, chat history, and artifact storage
2. **Ollama Container**: Runs the DeepSeek-Coder model with GPU acceleration
3. **Quart Web UI Container**: Provides the user interface with chat persistence
4. **NGINX Container**: Manages authentication, rate limiting, GZIP compression, and IP whitelisting

## Key Features

- **GPU Acceleration**: Leverages NVIDIA GPUs through Docker's GPU passthrough
- **PostgreSQL Authentication**: User accounts and session management
- **Chat Persistence**: All conversations are saved in PostgreSQL
- **Multiple Models**: Support for selecting different DeepSeek-Coder models
- **Artifact Storage**: Generated code snippets are saved in the database
- **Rate Limiting**: Protection against excessive requests
- **Failed Login Protection**: Account locking after failed attempts
- **GZIP Compression**: Optimized bandwidth usage
- **IP Whitelisting**: NGINX-level control of allowed IP addresses
- **Secure Sessions**: Session management with database persistence
- **User Management**: Admin interface for managing users
- **Archive/Restore**: Chat archiving and restoration
- **Dark Theme**: Sleek, dark interface optimized for code display
- **Responsive Design**: Works on desktop and mobile devices

## Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with appropriate drivers
- NVIDIA Container Toolkit (nvidia-docker)
- At least 8GB of RAM (16GB recommended)
- At least 10GB of free disk space

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/deepseek-coder-docker.git
   cd deepseek-coder-docker
   ```

2. Configure environment variables in `.env` file:
   ```bash
   # Copy the example environment file
   cp .env.example .env
   
   # Edit the file with your preferred settings
   nano .env
   ```

3. Start the containers:
   ```bash
   docker-compose up -d
   ```

4. Wait for all services to initialize. The first startup may take some time as it needs to download the DeepSeek-Coder model.

5. Access the web UI:
   ```
   http://localhost:8080
   ```
   
   Default login credentials:
   - Username: admin
   - Password: admin

## Changing the DeepSeek-Coder Model

You can switch between different model sizes through the UI:

- **DeepSeek-Coder 1.3B**: Fastest response, smaller GPU memory requirement
- **DeepSeek-Coder 6.7B**: Balanced model, good performance (default)
- **DeepSeek-Coder 33B**: Largest model, best quality, requires more GPU memory

## IP Whitelisting

The system includes IP whitelisting at the NGINX level. By default, all IPs are allowed, but you can easily restrict access:

1. Edit the NGINX configuration in `nginx/nginx.conf`
2. Change `default 1` to `default 0` in the `geo $whitelist` block
3. Uncomment and modify the IP ranges you want to allow
4. Restart the NGINX container: `docker-compose restart nginx`

You can use both CIDR notation (`192.168.1.0/24`) and range notation (`192.168.1.10-192.168.1.255`) for IP specifications.

## Security Considerations

1. **Change Default Passwords**: Always change the default admin password after installation
2. **Environment Variables**: Keep the `.env` file secure and don't commit it to version control
3. **IP Restrictions**: Consider enabling IP whitelisting in production environments
4. **HTTPS**: For production use, configure HTTPS with proper certificates

## User Management

The system provides an admin interface for user management:

1. Login as an admin user
2. Navigate to the user management page
3. Create new users with optional admin privileges
4. Manage existing users (delete, etc.)

Admin users can create new accounts, while regular users can only use the system.

## Persistence

All data is stored in PostgreSQL, including:

- User accounts and authentication
- Chat history with timestamps
- Code artifacts generated during conversations
- Session information

This ensures your conversations and generated code are preserved across container restarts.

## Customizing the Theme

The system uses a dark theme optimized for code display. If you want to customize it:

1. Edit the CSS file in `web-ui/static/css/styles.css`
2. Restart the web-ui container: `docker-compose restart web-ui`

## Troubleshooting

### Common Issues

1. **GPU not detected**: Make sure the NVIDIA Container Toolkit is properly installed and your GPU drivers are up-to-date

2. **Out of memory**: Reduce the model size if your GPU doesn't have enough VRAM

3. **PostgreSQL connection error**: Check your PostgreSQL environment variables and ensure the container is running

4. **Web UI not loading**: Check NGINX logs for any errors related to the web UI container

### Viewing Logs

To view logs from a specific container:

```bash
docker logs deepseek-postgres    # PostgreSQL logs
docker logs deepseek-ollama      # Ollama logs
docker logs deepseek-web-ui      # Web UI logs
docker logs deepseek-nginx       # NGINX logs
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [DeepSeek-Coder](https://github.com/deepseek-ai/DeepSeek-Coder) for the model
- [Ollama](https://ollama.ai/) for the model server
- [Quart](https://pgjones.gitlab.io/quart/) for the async web framework
