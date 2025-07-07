// nginx/njs/init.js - Server-side application initialization using redis2 module

import utils from './utils.js';

// Configuration from environment
const config = {
    ADMIN_USERNAME: 'admin',
    ADMIN_PASSWORD: 'admin', 
    ADMIN_USER_ID: 'admin',
    USER_ID_COUNTER_START: 1000
};

// Redis operations using nginx subrequests to redis2 module
async function sendRedisCommand(command) {
    try {
        const [cmd, ...args] = command;
        const cmdUpper = cmd.toUpperCase();
        
        let url;
        switch (cmdUpper) {
            case 'PING':
                url = '/redis-internal/ping';
                break;
                
            case 'GET':
                if (args.length !== 1) throw new Error('GET requires 1 argument');
                url = `/redis-internal/get/${encodeURIComponent(args[0])}`;
                break;
                
            case 'SET':
                if (args.length !== 2) throw new Error('SET requires 2 arguments');
                url = `/redis-internal/set/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}`;
                break;
                
            case 'HSET':
                if (args.length !== 3) throw new Error('HSET requires 3 arguments');
                url = `/redis-internal/hset/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}/${encodeURIComponent(args[2])}`;
                break;
                
            case 'SADD':
                if (args.length !== 2) throw new Error('SADD requires 2 arguments');
                url = `/redis-internal/sadd/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}`;
                break;
                
            case 'INCR':
                if (args.length !== 1) throw new Error('INCR requires 1 argument');
                url = `/redis-internal/incr/${encodeURIComponent(args[0])}`;
                break;
                
            case 'EXISTS':
                if (args.length !== 1) throw new Error('EXISTS requires 1 argument');
                url = `/redis-internal/exists/${encodeURIComponent(args[0])}`;
                break;
                
            case 'FLUSHDB':
                url = '/redis-internal/flushdb';
                break;
                
            default:
                throw new Error(`Unsupported command: ${cmdUpper}`);
        }

        // Use nginx subrequest to call redis2 module
        const response = await ngx.fetch(url, {
            method: 'GET'
        });

        if (!response.ok) {
            throw new Error(`Redis request failed: ${response.status}`);
        }

        const text = await response.text();
        return parseRedisResponse(text, cmdUpper);
        
    } catch (error) {
        throw new Error(`Redis operation failed: ${error.message}`);
    }
}

function parseRedisResponse(text, command) {
    if (!text || text.length === 0) {
        return null;
    }
    
    const firstChar = text[0];
    const content = text.slice(1);
    
    switch (firstChar) {
        case '+': // Simple string
            return content.trim();
            
        case '-': // Error
            throw new Error(content.trim());
            
        case ':': // Integer
            return parseInt(content.trim(), 10);
            
        case '$': // Bulk string
            const lines = text.split('\r\n');
            const len = parseInt(lines[0].slice(1), 10);
            if (len === -1) return null;
            return lines[1] || '';
            
        default:
            return text.trim();
    }
}

// Multiple HSET operations for creating admin user
async function createAdminUserData(userId, userData) {
    try {
        // Set each field individually using HSET
        for (const [field, value] of Object.entries(userData)) {
            await sendRedisCommand(['HSET', `user:${userId}`, field, value]);
        }
        
        // Add to username index
        await sendRedisCommand(['SET', `username:${userData.username}`, userId]);
        
        // Add to users set
        await sendRedisCommand(['SADD', 'users', userId]);
        
        return true;
    } catch (error) {
        throw new Error(`Failed to create admin user: ${error.message}`);
    }
}

// Initialize the system
async function initializeSystem() {
    try {
        console.log('🚀 Initializing Devstral system with redis2...');
        
        // Test Redis connection
        await testRedisConnection();
        
        // Initialize user ID counter
        await initializeUserIdCounter();
        
        // Create admin user
        await createAdminUser();
        
        // Set migration marker
        await setMigrationComplete();
        
        console.log('✅ System initialization complete');
        return { success: true, message: 'System initialized successfully' };
        
    } catch (error) {
        console.error('❌ System initialization failed:', error);
        throw error;
    }
}

async function testRedisConnection() {
    try {
        const result = await sendRedisCommand(['PING']);
        if (result !== 'PONG') {
            throw new Error('Redis ping failed');
        }
        console.log('✅ Redis connection established via redis2 module');
    } catch (error) {
        console.error('❌ Redis connection failed:', error);
        throw error;
    }
}

async function initializeUserIdCounter() {
    try {
        const exists = await sendRedisCommand(['EXISTS', 'user_id_counter']);
        
        if (exists === 0) {
            console.log('🔢 Initializing user ID counter...');
            await sendRedisCommand(['SET', 'user_id_counter', config.USER_ID_COUNTER_START]);
            console.log(`✅ User ID counter set to ${config.USER_ID_COUNTER_START}`);
        } else {
            const currentValue = await sendRedisCommand(['GET', 'user_id_counter']);
            console.log(`✅ User ID counter exists: ${currentValue}`);
        }
    } catch (error) {
        console.error('❌ Error initializing user ID counter:', error);
        throw error;
    }
}

async function createAdminUser() {
    try {
        console.log('👤 Checking admin user...');
        
        // Check if admin user exists
        const adminExists = await sendRedisCommand(['EXISTS', `user:${config.ADMIN_USER_ID}`]);
        
        if (adminExists === 0) {
            console.log('🔧 Creating admin user...');
            
            // Hash admin password
            const passwordHash = utils.sha256(config.ADMIN_PASSWORD + 'devstral_salt_2024');
            
            // Create admin user data
            const adminData = {
                id: config.ADMIN_USER_ID,
                username: config.ADMIN_USERNAME,
                password_hash: passwordHash,
                is_admin: 'true',
                is_approved: 'true',
                created_at: new Date().toISOString()
            };
            
            // Save admin user using multiple HSET operations
            await createAdminUserData(config.ADMIN_USER_ID, adminData);
            
            console.log('✅ Admin user created successfully');
            console.log(`📝 Username: ${config.ADMIN_USERNAME}`);
            console.log(`📝 Password: ${config.ADMIN_PASSWORD}`);
            console.log('⚠️ CHANGE THE ADMIN PASSWORD AFTER FIRST LOGIN!');
            
        } else {
            console.log('✅ Admin user already exists');
            
            // Ensure admin has correct privileges
            await sendRedisCommand(['HSET', `user:${config.ADMIN_USER_ID}`, 'is_admin', 'true']);
            await sendRedisCommand(['HSET', `user:${config.ADMIN_USER_ID}`, 'is_approved', 'true']);
        }
        
    } catch (error) {
        console.error('❌ Error creating admin user:', error);
        throw error;
    }
}

async function setMigrationComplete() {
    try {
        await sendRedisCommand(['SET', 'migration:v1_complete', 'true']);
        console.log('✅ Migration marker set');
    } catch (error) {
        console.error('❌ Error setting migration marker:', error);
        throw error;
    }
}

// System health check
async function performHealthCheck() {
    try {
        const health = {
            status: 'healthy',
            timestamp: new Date().toISOString(),
            checks: {
                redis: false,
                admin_user: false,
                user_counter: false
            },
            details: {}
        };
        
        // Check Redis
        try {
            await sendRedisCommand(['PING']);
            health.checks.redis = true;
        } catch (error) {
            health.checks.redis = false;
            health.details.redis_error = error.message;
            health.status = 'unhealthy';
        }
        
        // Check admin user
        try {
            const adminExists = await sendRedisCommand(['EXISTS', `user:${config.ADMIN_USER_ID}`]);
            health.checks.admin_user = adminExists === 1;
            if (!health.checks.admin_user) {
                health.status = 'degraded';
                health.details.admin_user_error = 'Admin user not found';
            }
        } catch (error) {
            health.checks.admin_user = false;
            health.details.admin_user_error = error.message;
            health.status = 'unhealthy';
        }
        
        // Check user counter
        try {
            const counterExists = await sendRedisCommand(['EXISTS', 'user_id_counter']);
            health.checks.user_counter = counterExists === 1;
            if (!health.checks.user_counter) {
                health.status = 'degraded';
                health.details.user_counter_error = 'User ID counter not initialized';
            }
        } catch (error) {
            health.checks.user_counter = false;
            health.details.user_counter_error = error.message;
            health.status = 'unhealthy';
        }
        
        return health;
    } catch (error) {
        return {
            status: 'error',
            timestamp: new Date().toISOString(),
            error: error.message
        };
    }
}

// Reset system (dangerous!)
async function resetSystem(confirmationText) {
    if (confirmationText !== 'RESET_ALL_DATA') {
        throw new Error('Invalid confirmation text');
    }
    
    try {
        console.log('🔥 RESETTING ENTIRE SYSTEM...');
        
        // Clear all data
        await sendRedisCommand(['FLUSHDB']);
        
        // Re-initialize
        await initializeSystem();
        
        console.log('✅ System reset complete');
        
        return {
            success: true,
            message: 'System has been completely reset',
            timestamp: new Date().toISOString()
        };
        
    } catch (error) {
        console.error('❌ System reset failed:', error);
        throw error;
    }
}

// Get system information
async function getSystemInfo() {
    try {
        const health = await performHealthCheck();
        const userCounter = await sendRedisCommand(['GET', 'user_id_counter']);
        
        return {
            health: health,
            user_counter: userCounter,
            redis_module: 'redis2',
            timestamp: new Date().toISOString()
        };
    } catch (error) {
        return {
            error: error.message,
            timestamp: new Date().toISOString()
        };
    }
}

// Handle initialization endpoint
async function handleInitEndpoint(r) {
    try {
        if (r.method === 'POST') {
            // Initialize system
            const result = await initializeSystem();
            return utils.sendSuccess(r, result);
            
        } else if (r.method === 'GET') {
            // Health check
            const health = await performHealthCheck();
            return utils.sendSuccess(r, health);
            
        } else {
            return utils.sendError(r, 405, 'Method not allowed');
        }
        
    } catch (error) {
        console.error('Init endpoint error:', error);
        return utils.sendError(r, 500, error.message);
    }
}

export default {
    initializeSystem,
    performHealthCheck,
    resetSystem,
    getSystemInfo,
    handleInitEndpoint,
    sendRedisCommand,
    testRedisConnection,
    createAdminUser
};