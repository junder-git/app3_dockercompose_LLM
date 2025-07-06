// redis/redis-http-wrapper.js - Simple HTTP wrapper for Redis commands
// This provides a REST API for Redis operations that JavaScript can call

const http = require('http');
const redis = require('redis');
const url = require('url');

class RedisHTTPWrapper {
    constructor() {
        this.client = null;
        this.server = null;
        this.port = process.env.HTTP_PORT || 8001;
        this.redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
    }

    async init() {
        // Create Redis client
        this.client = redis.createClient({
            url: this.redisUrl,
            retry_strategy: (times) => Math.min(times * 50, 2000)
        });

        // Handle Redis connection events
        this.client.on('error', (err) => {
            console.error('Redis Client Error:', err);
        });

        this.client.on('connect', () => {
            console.log('✅ Redis client connected');
        });

        this.client.on('ready', () => {
            console.log('✅ Redis client ready');
        });

        // Connect to Redis
        await this.client.connect();

        // Create HTTP server
        this.server = http.createServer((req, res) => {
            this.handleRequest(req, res);
        });

        // Start server
        this.server.listen(this.port, () => {
            console.log(`🌐 Redis HTTP wrapper listening on port ${this.port}`);
        });

        // Handle graceful shutdown
        process.on('SIGTERM', () => this.shutdown());
        process.on('SIGINT', () => this.shutdown());
    }

    async handleRequest(req, res) {
        // Set CORS headers
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');

        // Handle preflight requests
        if (req.method === 'OPTIONS') {
            res.writeHead(200);
            res.end();
            return;
        }

        try {
            const parsedUrl = url.parse(req.url, true);
            const method = req.method;
            const path = parsedUrl.pathname;

            // Parse request body for POST requests
            let body = '';
            if (method === 'POST') {
                req.on('data', chunk => {
                    body += chunk.toString();
                });

                req.on('end', async () => {
                    await this.processRequest(method, path, body, res);
                });
            } else {
                await this.processRequest(method, path, '', res);
            }

        } catch (error) {
            console.error('Request handling error:', error);
            this.sendError(res, 500, 'Internal server error');
        }
    }

    async processRequest(method, path, body, res) {
        try {
            if (method === 'POST' && path === '/') {
                // Handle Redis command execution
                const data = JSON.parse(body);
                const command = data.command;

                if (!Array.isArray(command)) {
                    this.sendError(res, 400, 'Command must be an array');
                    return;
                }

                const result = await this.executeCommand(command);
                this.sendSuccess(res, result);

            } else if (method === 'GET' && path === '/ping') {
                // Health check endpoint
                const result = await this.client.ping();
                this.sendSuccess(res, result);

            } else if (method === 'GET' && path === '/info') {
                // Redis info endpoint
                const info = await this.client.info();
                this.sendSuccess(res, { info });

            } else {
                this.sendError(res, 404, 'Endpoint not found');
            }

        } catch (error) {
            console.error('Command execution error:', error);
            this.sendError(res, 500, error.message);
        }
    }

    async executeCommand(command) {
        const [cmd, ...args] = command;
        const cmdLower = cmd.toLowerCase();

        try {
            // Map common Redis commands to client methods
            switch (cmdLower) {
                case 'ping':
                    return await this.client.ping();

                case 'get':
                    return await this.client.get(args[0]);

                case 'set':
                    if (args.length === 2) {
                        return await this.client.set(args[0], args[1]);
                    } else if (args.length === 3) {
                        // SET key value EX seconds
                        return await this.client.setEx(args[0], parseInt(args[2]), args[1]);
                    }
                    break;

                case 'setex':
                    return await this.client.setEx(args[0], parseInt(args[1]), args[2]);

                case 'del':
                    return await this.client.del(args);

                case 'exists':
                    return await this.client.exists(args[0]);

                case 'hset':
                    if (args.length === 3) {
                        return await this.client.hSet(args[0], args[1], args[2]);
                    } else {
                        // Multiple field-value pairs
                        const obj = {};
                        for (let i = 1; i < args.length; i += 2) {
                            obj[args[i]] = args[i + 1];
                        }
                        return await this.client.hSet(args[0], obj);
                    }

                case 'hget':
                    return await this.client.hGet(args[0], args[1]);

                case 'hgetall':
                    return await this.client.hGetAll(args[0]);

                case 'sadd':
                    return await this.client.sAdd(args[0], args[1]);

                case 'srem':
                    return await this.client.sRem(args[0], args[1]);

                case 'smembers':
                    return await this.client.sMembers(args[0]);

                case 'zadd':
                    return await this.client.zAdd(args[0], { score: parseFloat(args[1]), value: args[2] });

                case 'zrange':
                    return await this.client.zRange(args[0], parseInt(args[1]), parseInt(args[2]));

                case 'zrevrange':
                    return await this.client.zRevRange(args[0], parseInt(args[1]), parseInt(args[2]));

                case 'zrem':
                    return await this.client.zRem(args[0], args[1]);

                case 'zcard':
                    return await this.client.zCard(args[0]);

                case 'incr':
                    return await this.client.incr(args[0]);

                case 'expire':
                    return await this.client.expire(args[0], parseInt(args[1]));

                case 'keys':
                    return await this.client.keys(args[0]);

                case 'flushdb':
                    return await this.client.flushDb();

                default:
                    // For commands not explicitly mapped, try to execute directly
                    return await this.client.sendCommand(command);
            }

        } catch (error) {
            console.error(`Error executing command ${cmd}:`, error);
            throw error;
        }
    }

    sendSuccess(res, data) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
    }

    sendError(res, statusCode, message) {
        res.writeHead(statusCode, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: message }));
    }

    async shutdown() {
        console.log('🔄 Shutting down Redis HTTP wrapper...');
        
        if (this.server) {
            this.server.close();
        }
        
        if (this.client) {
            await this.client.quit();
        }
        
        process.exit(0);
    }
}

// Start the wrapper if this file is run directly
if (require.main === module) {
    const wrapper = new RedisHTTPWrapper();
    wrapper.init().catch(error => {
        console.error('Failed to start Redis HTTP wrapper:', error);
        process.exit(1);
    });
}

module.exports = RedisHTTPWrapper;