// nginx/njs/init.js - Server-side application initialization for njs

import utils from './utils.js';

// Configuration from environment
const config = {
    ADMIN_USERNAME: 'admin',
    ADMIN_PASSWORD: 'admin', 
    ADMIN_USER_ID: 'admin',
    USER_ID_COUNTER_START: 1000
};

// Redis HTTP wrapper
const REDIS_HTTP_URL = 'http://redis:8001';

async function sendRedisCommand(command) {
    try {
        const response = await ngx.fetch(REDIS_HTTP_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ command: command })
        });

        if (!response.ok) {
            throw new Error(`Redis request failed: ${response.status}`);
        }

        return await response.json();
    } catch (error) {
        throw new Error(`Redis operation failed: ${error.message}`);
    }
}

// Initialize the system
async function initializeSystem() {
    try {
        console.log('🚀 Initializing Devstral system...');
        
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
        console.log('✅ Redis connection established');
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
            
            // Save admin user
            const args = ['HSET', `user:${config.ADMIN_USER_ID}`];
            for (const [field, value] of Object.entries(adminData)) {
                args.push(field, value);
            }
            await sendRedisCommand(args);
            
            // Add to username index
            await sendRedisCommand(['SET', `username:${config.ADMIN_USERNAME}`, config.ADMIN_USER_ID]);
            
            // Add to users set
            await sendRedisCommand(['SADD', 'users', config.ADMIN_USER_ID]);
            
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
    handleInitEndpoint,
    sendRedisCommand
};