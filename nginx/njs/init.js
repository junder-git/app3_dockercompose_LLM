// nginx/njs/init.js - Server-side application initialization using redis2 module (ES5 compatible)

import utils from './utils.js';

// Configuration from environment
var config = {
    ADMIN_USERNAME: 'admin',
    ADMIN_PASSWORD: 'admin', 
    ADMIN_USER_ID: 'admin',
    USER_ID_COUNTER_START: 1000
};

// Redis operations using nginx subrequests to redis2 module
function sendRedisCommand(command) {
    try {
        var cmd = command[0];
        var args = command.slice(1);
        var cmdUpper = cmd.toUpperCase();
        
        var url;
        switch (cmdUpper) {
            case 'PING':
                url = '/redis-internal/ping';
                break;
                
            case 'GET':
                if (args.length !== 1) throw new Error('GET requires 1 argument');
                url = '/redis-internal/get/' + encodeURIComponent(args[0]);
                break;
                
            case 'SET':
                if (args.length !== 2) throw new Error('SET requires 2 arguments');
                url = '/redis-internal/set/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]);
                break;
                
            case 'HSET':
                if (args.length !== 3) throw new Error('HSET requires 3 arguments');
                url = '/redis-internal/hset/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]) + '/' + encodeURIComponent(args[2]);
                break;
                
            case 'SADD':
                if (args.length !== 2) throw new Error('SADD requires 2 arguments');
                url = '/redis-internal/sadd/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]);
                break;
                
            case 'INCR':
                if (args.length !== 1) throw new Error('INCR requires 1 argument');
                url = '/redis-internal/incr/' + encodeURIComponent(args[0]);
                break;
                
            case 'EXISTS':
                if (args.length !== 1) throw new Error('EXISTS requires 1 argument');
                url = '/redis-internal/exists/' + encodeURIComponent(args[0]);
                break;
                
            case 'FLUSHDB':
                url = '/redis-internal/flushdb';
                break;
                
            default:
                throw new Error('Unsupported command: ' + cmdUpper);
        }

        // Use nginx subrequest to call redis2 module
        return ngx.fetch(url, {
            method: 'GET'
        }).then(function(response) {
            if (!response.ok) {
                throw new Error('Redis request failed: ' + response.status);
            }

            return response.text();
        }).then(function(text) {
            return parseRedisResponse(text, cmdUpper);
        });
        
    } catch (error) {
        return Promise.reject(new Error('Redis operation failed: ' + error.message));
    }
}

function parseRedisResponse(text, command) {
    if (!text || text.length === 0) {
        return null;
    }
    
    var firstChar = text[0];
    var content = text.slice(1);
    
    switch (firstChar) {
        case '+': // Simple string
            return content.trim();
            
        case '-': // Error
            throw new Error(content.trim());
            
        case ':': // Integer
            return parseInt(content.trim(), 10);
            
        case '$': // Bulk string
            var lines = text.split('\r\n');
            var len = parseInt(lines[0].slice(1), 10);
            if (len === -1) return null;
            return lines[1] || '';
            
        default:
            return text.trim();
    }
}

// Multiple HSET operations for creating admin user
function createAdminUserData(userId, userData) {
    var promises = [];
    var fields = Object.keys(userData);
    
    // Set each field individually using HSET
    for (var i = 0; i < fields.length; i++) {
        var field = fields[i];
        var value = userData[field];
        promises.push(sendRedisCommand(['HSET', 'user:' + userId, field, value]));
    }
    
    return Promise.all(promises).then(function() {
        // Add to username index
        return sendRedisCommand(['SET', 'username:' + userData.username, userId]);
    }).then(function() {
        // Add to users set
        return sendRedisCommand(['SADD', 'users', userId]);
    }).then(function() {
        return true;
    }).catch(function(error) {
        throw new Error('Failed to create admin user: ' + error.message);
    });
}

// Initialize the system
function initializeSystem() {
    console.log('🚀 Initializing Devstral system with redis2...');
    
    return testRedisConnection().then(function() {
        // Initialize user ID counter
        return initializeUserIdCounter();
    }).then(function() {
        // Create admin user
        return createAdminUser();
    }).then(function() {
        // Set migration marker
        return setMigrationComplete();
    }).then(function() {
        console.log('✅ System initialization complete');
        return { success: true, message: 'System initialized successfully' };
    }).catch(function(error) {
        console.error('❌ System initialization failed:', error);
        throw error;
    });
}

function testRedisConnection() {
    return sendRedisCommand(['PING']).then(function(result) {
        if (result !== 'PONG') {
            throw new Error('Redis ping failed');
        }
        console.log('✅ Redis connection established via redis2 module');
    }).catch(function(error) {
        console.error('❌ Redis connection failed:', error);
        throw error;
    });
}

function initializeUserIdCounter() {
    return sendRedisCommand(['EXISTS', 'user_id_counter']).then(function(exists) {
        if (exists === 0) {
            console.log('🔢 Initializing user ID counter...');
            return sendRedisCommand(['SET', 'user_id_counter', config.USER_ID_COUNTER_START]);
        } else {
            return sendRedisCommand(['GET', 'user_id_counter']);
        }
    }).then(function(currentValue) {
        if (typeof currentValue === 'number') {
            console.log('✅ User ID counter set to ' + config.USER_ID_COUNTER_START);
        } else {
            console.log('✅ User ID counter exists: ' + currentValue);
        }
    }).catch(function(error) {
        console.error('❌ Error initializing user ID counter:', error);
        throw error;
    });
}

function createAdminUser() {
    console.log('👤 Checking admin user...');
    
    return sendRedisCommand(['EXISTS', 'user:' + config.ADMIN_USER_ID]).then(function(adminExists) {
        if (adminExists === 0) {
            console.log('🔧 Creating admin user...');
            
            // Hash admin password
            var passwordHash = utils.sha256(config.ADMIN_PASSWORD + 'devstral_salt_2024');
            
            // Create admin user data
            var adminData = {
                id: config.ADMIN_USER_ID,
                username: config.ADMIN_USERNAME,
                password_hash: passwordHash,
                is_admin: 'true',
                is_approved: 'true',
                created_at: new Date().toISOString()
            };
            
            // Save admin user using multiple HSET operations
            return createAdminUserData(config.ADMIN_USER_ID, adminData);
        } else {
            console.log('✅ Admin user already exists');
            
            // Ensure admin has correct privileges
            var promises = [
                sendRedisCommand(['HSET', 'user:' + config.ADMIN_USER_ID, 'is_admin', 'true']),
                sendRedisCommand(['HSET', 'user:' + config.ADMIN_USER_ID, 'is_approved', 'true'])
            ];
            
            return Promise.all(promises);
        }
    }).then(function() {
        console.log('✅ Admin user created successfully');
        console.log('📝 Username: ' + config.ADMIN_USERNAME);
        console.log('📝 Password: ' + config.ADMIN_PASSWORD);
        console.log('⚠️ CHANGE THE ADMIN PASSWORD AFTER FIRST LOGIN!');
    }).catch(function(error) {
        console.error('❌ Error creating admin user:', error);
        throw error;
    });
}

function setMigrationComplete() {
    return sendRedisCommand(['SET', 'migration:v1_complete', 'true']).then(function() {
        console.log('✅ Migration marker set');
    }).catch(function(error) {
        console.error('❌ Error setting migration marker:', error);
        throw error;
    });
}

// System health check
function performHealthCheck() {
    var health = {
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
    return sendRedisCommand(['PING']).then(function() {
        health.checks.redis = true;
        return sendRedisCommand(['EXISTS', 'user:' + config.ADMIN_USER_ID]);
    }).catch(function(error) {
        health.checks.redis = false;
        health.details.redis_error = error.message;
        health.status = 'unhealthy';
        return sendRedisCommand(['EXISTS', 'user:' + config.ADMIN_USER_ID]);
    }).then(function(adminExists) {
        health.checks.admin_user = adminExists === 1;
        if (!health.checks.admin_user) {
            health.status = 'degraded';
            health.details.admin_user_error = 'Admin user not found';
        }
        return sendRedisCommand(['EXISTS', 'user_id_counter']);
    }).catch(function(error) {
        health.checks.admin_user = false;
        health.details.admin_user_error = error.message;
        health.status = 'unhealthy';
        return sendRedisCommand(['EXISTS', 'user_id_counter']);
    }).then(function(counterExists) {
        health.checks.user_counter = counterExists === 1;
        if (!health.checks.user_counter) {
            health.status = 'degraded';
            health.details.user_counter_error = 'User ID counter not initialized';
        }
        return health;
    }).catch(function(error) {
        health.checks.user_counter = false;
        health.details.user_counter_error = error.message;
        health.status = 'unhealthy';
        return health;
    });
}

// Reset system (dangerous!)
function resetSystem(confirmationText) {
    if (confirmationText !== 'RESET_ALL_DATA') {
        throw new Error('Invalid confirmation text');
    }
    
    console.log('🔥 RESETTING ENTIRE SYSTEM...');
    
    // Clear all data
    return sendRedisCommand(['FLUSHDB']).then(function() {
        // Re-initialize
        return initializeSystem();
    }).then(function() {
        console.log('✅ System reset complete');
        
        return {
            success: true,
            message: 'System has been completely reset',
            timestamp: new Date().toISOString()
        };
    }).catch(function(error) {
        console.error('❌ System reset failed:', error);
        throw error;
    });
}

// Get system information
function getSystemInfo() {
    return performHealthCheck().then(function(health) {
        return sendRedisCommand(['GET', 'user_id_counter']).then(function(userCounter) {
            return {
                health: health,
                user_counter: userCounter,
                redis_module: 'redis2',
                timestamp: new Date().toISOString()
            };
        });
    }).catch(function(error) {
        return {
            error: error.message,
            timestamp: new Date().toISOString()
        };
    });
}

// Handle initialization endpoint
function handleInitEndpoint(r) {
    try {
        if (r.method === 'POST') {
            // Initialize system
            initializeSystem().then(function(result) {
                return utils.sendSuccess(r, result);
            }).catch(function(error) {
                console.error('Init endpoint error:', error);
                return utils.sendError(r, 500, error.message);
            });
            
        } else if (r.method === 'GET') {
            // Health check
            performHealthCheck().then(function(health) {
                return utils.sendSuccess(r, health);
            }).catch(function(error) {
                console.error('Health check error:', error);
                return utils.sendError(r, 500, error.message);
            });
            
        } else {
            return utils.sendError(r, 405, 'Method not allowed');
        }
        
    } catch (error) {
        console.error('Init endpoint error:', error);
        return utils.sendError(r, 500, error.message);
    }
}

export default {
    initializeSystem: initializeSystem,
    performHealthCheck: performHealthCheck,
    resetSystem: resetSystem,
    getSystemInfo: getSystemInfo,
    handleInitEndpoint: handleInitEndpoint,
    sendRedisCommand: sendRedisCommand,
    testRedisConnection: testRedisConnection,
    createAdminUser: createAdminUser
};