// nginx/server/app.js - Server-side JavaScript API
const express = require('express');
const redis = require('redis');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');

class DevstralBackend {
    constructor() {
        this.app = express();
        this.port = process.env.PORT || 3000;
        this.redis = null;
        this.jwtSecret = process.env.JWT_SECRET || 'your-secret-key-change-this';
        
        // Import your existing models and utilities
        this.User = require('./models/User');
        this.ChatSession = require('./models/ChatSession');
        this.Database = require('./database/Database');
        this.Auth = require('./auth/Auth');
    }

    async init() {
        // Setup middleware
        this.app.use(helmet());
        this.app.use(express.json({ limit: '10mb' }));
        this.app.use(express.urlencoded({ extended: true }));
        
        // Setup Redis connection
        this.redis = redis.createClient({
            url: process.env.REDIS_URL || 'redis://redis:6379'
        });
        await this.redis.connect();
        
        // Initialize database with Redis client
        this.database = new this.Database(this.redis);
        await this.database.init();
        
        // Initialize auth with database
        this.auth = new this.Auth(this.database, this.jwtSecret);
        
        // Setup rate limiting
        this.setupRateLimiting();
        
        // Setup routes
        this.setupRoutes();
        
        // Start server
        this.app.listen(this.port, () => {
            console.log(`🚀 Devstral Backend running on port ${this.port}`);
        });
    }

    setupRateLimiting() {
        // Auth endpoints rate limiting
        const authLimiter = rateLimit({
            windowMs: 15 * 60 * 1000, // 15 minutes
            max: 5, // 5 attempts per window
            message: { error: 'Too many authentication attempts' },
            standardHeaders: true,
            legacyHeaders: false,
        });

        // API endpoints rate limiting
        const apiLimiter = rateLimit({
            windowMs: 1 * 60 * 1000, // 1 minute
            max: 100, // 100 requests per minute
            message: { error: 'Rate limit exceeded' },
            standardHeaders: true,
            legacyHeaders: false,
        });

        this.app.use('/api/auth', authLimiter);
        this.app.use('/api', apiLimiter);
    }

    setupRoutes() {
        // Health check
        this.app.get('/health', (req, res) => {
            res.json({ status: 'healthy', timestamp: new Date().toISOString() });
        });

        // =====================================================
        // AUTHENTICATION ROUTES
        // =====================================================
        
        this.app.post('/api/auth/login', async (req, res) => {
            try {
                const { username, password } = req.body;
                
                // Server-side validation
                if (!username || !password) {
                    return res.status(400).json({ error: 'Username and password required' });
                }

                if (username.length < 3 || username.length > 50) {
                    return res.status(400).json({ error: 'Invalid username length' });
                }

                // Get user from database
                const user = await this.database.getUserByUsername(username);
                if (!user) {
                    return res.status(401).json({ error: 'Invalid credentials' });
                }

                // Verify password
                const isValid = await bcrypt.compare(password, user.password_hash);
                if (!isValid) {
                    return res.status(401).json({ error: 'Invalid credentials' });
                }

                // Check if user is approved
                if (!user.is_admin && !user.is_approved) {
                    return res.status(403).json({ error: 'Account pending approval' });
                }

                // Generate JWT token
                const token = jwt.sign(
                    { 
                        userId: user.id, 
                        username: user.username,
                        isAdmin: user.is_admin,
                        isApproved: user.is_approved
                    },
                    this.jwtSecret,
                    { expiresIn: '24h' }
                );

                res.json({
                    success: true,
                    token,
                    user: {
                        id: user.id,
                        username: user.username,
                        is_admin: user.is_admin,
                        is_approved: user.is_approved
                    }
                });

            } catch (error) {
                console.error('Login error:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        this.app.post('/api/auth/register', async (req, res) => {
            try {
                const { username, password } = req.body;
                
                // Server-side validation
                if (!username || !password) {
                    return res.status(400).json({ error: 'Username and password required' });
                }

                if (username.length < 3 || username.length > 50) {
                    return res.status(400).json({ error: 'Username must be 3-50 characters' });
                }

                if (!/^[a-zA-Z0-9_-]+$/.test(username)) {
                    return res.status(400).json({ error: 'Username contains invalid characters' });
                }

                if (password.length < 6) {
                    return res.status(400).json({ error: 'Password must be at least 6 characters' });
                }

                // Check pending user limit (SERVER-SIDE ENFORCEMENT)
                const pendingCount = await this.database.getPendingUsersCount();
                const MAX_PENDING = parseInt(process.env.MAX_PENDING_USERS) || 2;
                
                if (pendingCount >= MAX_PENDING) {
                    return res.status(429).json({ error: 'Registration temporarily closed' });
                }

                // Check if username exists
                const existingUser = await this.database.getUserByUsername(username);
                if (existingUser) {
                    return res.status(409).json({ error: 'Username already exists' });
                }

                // Hash password
                const saltRounds = 12;
                const password_hash = await bcrypt.hash(password, saltRounds);

                // Create user
                const newUser = new this.User(
                    null, // ID will be auto-generated
                    username,
                    password_hash,
                    false, // is_admin
                    false  // is_approved
                );

                await this.database.saveUser(newUser);

                res.json({ 
                    success: true, 
                    message: 'Registration successful, pending approval' 
                });

            } catch (error) {
                console.error('Registration error:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Token verification endpoint for Nginx auth_request
        this.app.get('/api/auth/verify', async (req, res) => {
            try {
                const authHeader = req.headers.authorization;
                if (!authHeader || !authHeader.startsWith('Bearer ')) {
                    return res.status(401).json({ error: 'No token provided' });
                }

                const token = authHeader.substring(7);
                const decoded = jwt.verify(token, this.jwtSecret);

                // Set headers for Nginx
                res.set('X-User-ID', decoded.userId);
                res.set('X-Username', decoded.username);
                res.set('X-Is-Admin', decoded.isAdmin.toString());
                res.set('X-Is-Approved', decoded.isApproved.toString());

                res.status(200).json({ valid: true });

            } catch (error) {
                res.status(401).json({ error: 'Invalid token' });
            }
        });

        // =====================================================
        // PROTECTED ROUTES (Require authentication)
        // =====================================================
        
        // Middleware to verify JWT token
        const authenticateToken = (req, res, next) => {
            const authHeader = req.headers.authorization;
            const token = authHeader && authHeader.split(' ')[1];

            if (!token) {
                return res.status(401).json({ error: 'Access token required' });
            }

            jwt.verify(token, this.jwtSecret, (err, user) => {
                if (err) {
                    return res.status(403).json({ error: 'Invalid token' });
                }
                req.user = user;
                next();
            });
        };

        // Middleware to require admin privileges
        const requireAdmin = (req, res, next) => {
            if (!req.user.isAdmin) {
                return res.status(403).json({ error: 'Admin privileges required' });
            }
            next();
        };

        // Chat endpoints
        this.app.post('/api/chat/send', authenticateToken, async (req, res) => {
            try {
                const { message, sessionId } = req.body;
                
                // Server-side rate limiting per user
                const rateLimitOk = await this.database.checkRateLimit(
                    req.user.userId, 
                    parseInt(process.env.RATE_LIMIT_MESSAGES_PER_MINUTE) || 100
                );
                
                if (!rateLimitOk) {
                    return res.status(429).json({ error: 'Rate limit exceeded' });
                }

                // Validate message
                if (!message || message.length > 5000) {
                    return res.status(400).json({ error: 'Invalid message' });
                }

                // Process chat message...
                // Your existing chat logic here
                
                res.json({ success: true, message: 'Message processed' });

            } catch (error) {
                console.error('Chat error:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // Admin routes
        this.app.get('/api/admin/users', authenticateToken, requireAdmin, async (req, res) => {
            try {
                const users = await this.database.getAllUsers();
                res.json(users);
            } catch (error) {
                console.error('Admin users error:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        this.app.post('/api/admin/approve/:userId', authenticateToken, requireAdmin, async (req, res) => {
            try {
                const { userId } = req.params;
                const result = await this.database.approveUser(userId);
                res.json(result);
            } catch (error) {
                console.error('Admin approve error:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });

        // =====================================================
        // REDIS PROXY (Authenticated)
        // =====================================================
        
        this.app.post('/api/redis', authenticateToken, async (req, res) => {
            try {
                const { command } = req.body;
                
                // Whitelist allowed Redis commands for security
                const allowedCommands = [
                    'GET', 'SET', 'DEL', 'EXISTS',
                    'HGET', 'HSET', 'HGETALL',
                    'SADD', 'SREM', 'SMEMBERS',
                    'ZADD', 'ZRANGE', 'ZREVRANGE', 'ZREM', 'ZCARD',
                    'INCR', 'EXPIRE', 'KEYS'
                ];
                
                if (!allowedCommands.includes(command[0].toUpperCase())) {
                    return res.status(403).json({ error: 'Command not allowed' });
                }

                // Add user context to Redis operations
                const userPrefixedCommand = this.addUserContext(command, req.user.userId);
                const result = await this.executeRedisCommand(userPrefixedCommand);
                
                res.json(result);

            } catch (error) {
                console.error('Redis proxy error:', error);
                res.status(500).json({ error: 'Internal server error' });
            }
        });
    }

    addUserContext(command, userId) {
        // Add user ID prefix to keys to isolate user data
        const [cmd, key, ...args] = command;
        if (key && !key.startsWith('user:') && !key.startsWith('global:')) {
            return [cmd, `user:${userId}:${key}`, ...args];
        }
        return command;
    }

    async executeRedisCommand(command) {
        const [cmd, ...args] = command;
        
        switch (cmd.toLowerCase()) {
            case 'get':
                return await this.redis.get(args[0]);
            case 'set':
                return await this.redis.set(args[0], args[1]);
            case 'hgetall':
                return await this.redis.hGetAll(args[0]);
            // Add other Redis commands as needed
            default:
                throw new Error('Unsupported command');
        }
    }
}

// Start the backend
if (require.main === module) {
    const backend = new DevstralBackend();
    backend.init().catch(error => {
        console.error('Failed to start backend:', error);
        process.exit(1);
    });
}

module.exports = DevstralBackend;