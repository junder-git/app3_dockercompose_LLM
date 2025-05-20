# DeepSeek-Coder with Redis and GraphQL

This repository now includes enhanced architecture with Redis for caching and GraphQL for API access.

## Updated Architecture

The system now uses six Docker containers working together:

1. **PostgreSQL Container**: Handles authentication, chat history, and artifact storage
2. **Redis Container**: Provides caching and session management capabilities
3. **Ollama Container**: Runs the DeepSeek-Coder model with GPU acceleration
4. **Quart Web UI Container**: Provides the user interface with GraphQL API
5. **NGINX Container**: Manages authentication, rate limiting, GZIP compression, and IP whitelisting
6. **Strawberry GraphQL**: Integrated with Quart to provide a flexible API layer

This architecture follows modern design patterns with proper separation of concerns:

- **Data Storage**: PostgreSQL handles persistent storage
- **Caching Layer**: Redis provides fast access to frequently requested data
- **API Layer**: GraphQL offers flexible and efficient data access
- **Application Layer**: Quart Web UI handles business logic
- **Presentation Layer**: Web-based interface for user interaction
- **AI Processing**: Ollama for LLM inference

## New Capabilities

### Redis Caching

The Redis integration provides:

- **Query Result Caching**: Frequently accessed data is cached to reduce database load
- **Session Management**: User sessions can be managed efficiently
- **Performance Optimization**: Reduced response times for common operations

### GraphQL API

The GraphQL integration provides:

- **Flexible Data Retrieval**: Clients can request exactly the data they need
- **Strongly Typed Schema**: Self-documenting API with schema validation
- **Batched Requests**: Multiple operations in a single request
- **Developer Playground**: Interactive API explorer for documentation and testing

## Directory Structure

```
deepseek-coder-setup/
├── .env                    # Environment variables for all services
├── README.md               # Project documentation
├── docker-compose.yml      # Multi-container Docker configuration
├── db/                     # PostgreSQL database files
│   ├── Dockerfile
│   ├── init.sql
│   └── create_tables.sql
├── redis/                  # Redis cache files
│   ├── Dockerfile
│   └── redis.conf
├── nginx/                  # NGINX web server files
│   ├── Dockerfile
│   ├── nginx.conf
│   └── ...
├── ollama/                 # Ollama (DeepSeek-Coder model) files
│   └── Dockerfile
└── web-ui/                 # Web UI with GraphQL API
    ├── Dockerfile
    ├── app.py              # Main application code
    ├── schema.py           # GraphQL schema definitions
    ├── resolvers.py        # GraphQL resolver functions
    ├── github_connector.py
    ├── requirements.txt
    ├── static/
    │   ├── css/
    │   └── js/
    │       ├── main.js
    │       └── graphql-client.js   # Client-side GraphQL library
    └── templates/
        ├── base.html
        ├── login.html
        ├── graphql_playground.html # GraphQL interactive explorer
        └── ...
```

## Getting Started

1. Make sure you have Docker, Docker Compose, and NVIDIA Container Toolkit installed.

2. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/deepseek-coder-docker.git
   cd deepseek-coder-docker
   ```

3. Configure environment variables in `.env` file:
   ```bash
   # Copy the example environment file
   cp .env.example .env
   
   # Edit the file with your preferred settings
   nano .env
   ```

4. Start the containers:
   ```bash
   docker-compose up -d
   ```

5. Wait for all services to initialize. The first startup may take longer as it downloads all required components.

6. Access the web UI:
   ```
   http://localhost:8080
   ```
   
   Default login credentials:
   - Username: admin
   - Password: admin

7. Access the GraphQL Playground (admin users only):
   - Log in as an admin user
   - Click on your username in the top-right corner
   - Select "GraphQL API" from the dropdown menu

## Using the GraphQL API

The GraphQL API provides access to all the functionality of DeepSeek-Coder, including:

- User information
- Chat history
- Messages
- Code artifacts

Example queries:

```graphql
# Get all chats
query {
  chats {
    id
    title
    createdAt
  }
}

# Get a specific chat with messages and artifacts
query {
  chat(id: 1) {
    id
    title
    messages {
      id
      role
      content
    }
    artifacts {
      id
      title
      language
    }
  }
}

# Create a new chat
mutation {
  createChat(input: {title: "New GraphQL Chat"}) {
    id
    title
  }
}
```

## Using Redis Cache

Redis caching is configured automatically for GraphQL queries to improve performance. You can monitor Redis usage with:

```bash
docker exec -it deepseek-redis redis-cli -a "your_redis_password"
```

Common Redis commands:
```
INFO                    # Get Redis server information
MONITOR                 # Watch Redis activity in real-time
KEYS graphql:*          # View all GraphQL cache keys
GET graphql:get_chats   # Get cached chat data
FLUSHDB                 # Clear all cached data
```

## Performance Considerations

- Redis cache TTL (time-to-live) is configured according to data volatility:
  - 60 seconds for chat lists
  - 30 seconds for chat details
  - 5 minutes for user information

- GraphQL depth and complexity limits are in place to prevent abuse

- The GraphQL playground is only available to admin users

## Future Enhancements

- **Subscription Support**: Real-time updates via WebSockets
- **DataLoader Implementation**: Batch and cache database requests
- **Redis Rate Limiting**: More sophisticated request throttling
- **Redis Pub/Sub**: Event-driven communication between services
- **GraphQL Federation**: Split GraphQL schema across services