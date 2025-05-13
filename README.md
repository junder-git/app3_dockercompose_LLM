# app3_LLM
runs on arch linux 32Gb ram and nvidia 3060ti in docker with posgres backend
# File: README.md
# Directory: /deepseek-coder-setup/

# DeepSeek-Coder Docker Setup

A comprehensive Docker-based solution for running DeepSeek-Coder with NVIDIA GPU support, including a web UI, PostgreSQL-based authentication and persistence, and security features.

## Architecture

This system uses multiple Docker containers to provide a modular and maintainable architecture:

1. **PostgreSQL Container**: Handles authentication, chat history, and artifact storage
2. **Ollama Container**: Runs the DeepSeek-Coder model with GPU acceleration
3. **Quart Web UI Container**: Provides the user interface with chat persistence
4. **NGINX Container**: Manages authentication, rate limiting, and GZIP compression

## Features

- **GPU Acceleration**: Leverages NVIDIA GPUs through Docker's GPU passthrough
- **PostgreSQL Authentication**: User accounts and session management
- **Chat Persistence**: All conversations are saved in PostgreSQL
- **Multiple Models**: Support for selecting different DeepSeek-Coder models
- **Artifact Storage**: Generated code snippets are saved in the database
- **Rate Limiting**: Protection against excessive requests
- **Failed Login Protection**: Account locking after failed attempts
- **GZIP Compression**: Optimized bandwidth usage
- **Secure Sessions**: Session management with database persistence
- **User Management**: Admin interface for managing users
- **Archive/Restore**: Chat archiving and restoration
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

## File Structure

```
deepseek-coder-setup/
├── docker-compose.yml    # Main configuration file
├── .env                  # Environment variables
├── nginx/                # NGINX configuration
│   ├── Dockerfile
│   ├── nginx.conf
│   └── gzip.conf
├── web-ui/               # Web UI application
│   ├── Dockerfile
│   ├── app.py
│   ├── requirements.txt
│   ├── static/
│   │   └── css/
│   │       └── styles.css
│   └── templates/
│       ├── base.html
│       ├── login.html
│       └── chat.html
└── db/                   # Database initialization
    ├── Dockerfile
    ├── init.sql
    └── create_tables.sql
```