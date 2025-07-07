// nginx/njs/database.js - Server-side Redis operations using redis2 module (ES5 compatible)

import utils from './utils.js';

// Redis operations using nginx redis2 module
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
                
            case 'SETEX':
                if (args.length !== 3) throw new Error('SETEX requires 3 arguments');
                url = '/redis-internal/setex/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]) + '/' + encodeURIComponent(args[2]);
                break;
                
            case 'HGET':
                if (args.length !== 2) throw new Error('HGET requires 2 arguments');
                url = '/redis-internal/hget/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]);
                break;
                
            case 'HSET':
                if (args.length !== 3) throw new Error('HSET requires 3 arguments');
                url = '/redis-internal/hset/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]) + '/' + encodeURIComponent(args[2]);
                break;
                
            case 'HGETALL':
                if (args.length !== 1) throw new Error('HGETALL requires 1 argument');
                url = '/redis-internal/hgetall/' + encodeURIComponent(args[0]);
                break;
                
            case 'SMEMBERS':
                if (args.length !== 1) throw new Error('SMEMBERS requires 1 argument');
                url = '/redis-internal/smembers/' + encodeURIComponent(args[0]);
                break;
                
            case 'SADD':
                if (args.length !== 2) throw new Error('SADD requires 2 arguments');
                url = '/redis-internal/sadd/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]);
                break;
                
            case 'SREM':
                if (args.length !== 2) throw new Error('SREM requires 2 arguments');
                url = '/redis-internal/srem/' + encodeURIComponent(args[0]) + '/' + encodeURIComponent(args[1]);
                break;
                
            case 'INCR':
                if (args.length !== 1) throw new Error('INCR requires 1 argument');
                url = '/redis-internal/incr/' + encodeURIComponent(args[0]);
                break;
                
            case 'EXISTS':
                if (args.length !== 1) throw new Error('EXISTS requires 1 argument');
                url = '/redis-internal/exists/' + encodeURIComponent(args[0]);
                break;
                
            case 'DEL':
                if (args.length !== 1) throw new Error('DEL requires 1 argument');
                url = '/redis-internal/del/' + encodeURIComponent(args[0]);
                break;
                
            case 'FLUSHDB':
                url = '/redis-internal/flushdb';
                break;
                
            default:
                // For complex commands, use the generic endpoint
                url = '/redis-internal/command';
                break;
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
            // Parse redis2 response format
            return parseRedisResponse(text, cmdUpper);
        });
        
    } catch (error) {
        return Promise.reject(new Error('Redis operation failed: ' + error.message));
    }
}

function parseRedisResponse(text, command) {
    // Redis2 module returns responses in Redis protocol format
    // Parse based on first character
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
            if (len === -1) return null; // Null bulk string
            return lines[1] || '';
            
        case '*': // Array
            return parseRedisArray(text, command);
            
        default:
            // Fallback for non-standard responses
            return text.trim();
    }
}

function parseRedisArray(text, command) {
    var lines = text.split('\r\n');
    var count = parseInt(lines[0].slice(1), 10);
    
    if (count === -1) return null;
    if (count === 0) return [];
    
    var result = [];
    var lineIndex = 1;
    
    for (var i = 0; i < count; i++) {
        if (lineIndex >= lines.length) break;
        
        var type = lines[lineIndex][0];
        if (type === '$') {
            var len = parseInt(lines[lineIndex].slice(1), 10);
            lineIndex++;
            if (len === -1) {
                result.push(null);
            } else {
                result.push(lines[lineIndex] || '');
                lineIndex++;
            }
        } else if (type === ':') {
            result.push(parseInt(lines[lineIndex].slice(1), 10));
            lineIndex++;
        } else {
            result.push(lines[lineIndex].slice(1));
            lineIndex++;
        }
    }
    
    // Special handling for HGETALL - convert array to object
    if (command === 'HGETALL') {
        var obj = {};
        for (var i = 0; i < result.length; i += 2) {
            if (i + 1 < result.length) {
                obj[result[i]] = result[i + 1];
            }
        }
        return obj;
    }
    
    return result;
}

// Basic Redis operations
function get(key) {
    return sendRedisCommand(['GET', key]);
}

function set(key, value, ttl) {
    var command = ttl ? ['SETEX', key, ttl, value] : ['SET', key, value];
    return sendRedisCommand(command);
}

function hget(key, field) {
    return sendRedisCommand(['HGET', key, field]);
}

function hset(key, field, value) {
    return sendRedisCommand(['HSET', key, field, value]);
}

function hgetall(key) {
    return sendRedisCommand(['HGETALL', key]);
}

function sadd(key, value) {
    return sendRedisCommand(['SADD', key, value]);
}

function smembers(key) {
    return sendRedisCommand(['SMEMBERS', key]);
}

function incr(key) {
    return sendRedisCommand(['INCR', key]);
}

function exists(key) {
    return sendRedisCommand(['EXISTS', key]);
}

function del(key) {
    return sendRedisCommand(['DEL', key]);
}

// User management functions
function getUserByUsername(username) {
    return get('username:' + username).then(function(userId) {
        if (!userId) return null;
        
        return hgetall('user:' + userId);
    }).then(function(userData) {
        if (!userData || Object.keys(userData).length === 0) return null;
        
        return {
            id: userData.id,
            username: userData.username,
            password_hash: userData.password_hash,
            is_admin: userData.is_admin === 'true',
            is_approved: userData.is_approved === 'true',
            created_at: userData.created_at
        };
    });
}

function getUserById(userId) {
    return hgetall('user:' + userId).then(function(userData) {
        if (!userData || Object.keys(userData).length === 0) return null;
        
        return {
            id: userData.id,
            username: userData.username,
            password_hash: userData.password_hash,
            is_admin: userData.is_admin === 'true',
            is_approved: userData.is_approved === 'true',
            created_at: userData.created_at
        };
    });
}

function saveUser(user) {
    var promise;
    
    // Generate ID if needed
    if (!user.id) {
        promise = incr('user_id_counter').then(function(newId) {
            user.id = String(newId);
            return user;
        });
    } else {
        promise = Promise.resolve(user);
    }
    
    return promise.then(function(userWithId) {
        // Convert user to storage format
        var userData = {
            id: String(userWithId.id),
            username: String(userWithId.username),
            password_hash: String(userWithId.password_hash),
            is_admin: String(userWithId.is_admin),
            is_approved: String(userWithId.is_approved),
            created_at: String(userWithId.created_at)
        };

        // Save user data - hset one field at a time
        var promises = [];
        var fields = Object.keys(userData);
        for (var i = 0; i < fields.length; i++) {
            var field = fields[i];
            var value = userData[field];
            promises.push(hset('user:' + userWithId.id, field, value));
        }

        return Promise.all(promises);
    }).then(function() {
        // Add to username index
        return set('username:' + user.username, user.id);
    }).then(function() {
        // Add to users set
        return sadd('users', user.id);
    }).then(function() {
        return user;
    });
}

function getAllUsers() {
    return smembers('users').then(function(userIds) {
        if (!userIds || userIds.length === 0) return [];
        
        var promises = [];
        for (var i = 0; i < userIds.length; i++) {
            promises.push(getUserById(userIds[i]));
        }
        
        return Promise.all(promises);
    }).then(function(users) {
        // Filter out null results
        var validUsers = [];
        for (var i = 0; i < users.length; i++) {
            if (users[i]) {
                validUsers.push(users[i]);
            }
        }
        return validUsers;
    });
}

function getPendingUsers() {
    return getAllUsers().then(function(allUsers) {
        var pendingUsers = [];
        for (var i = 0; i < allUsers.length; i++) {
            var user = allUsers[i];
            if (!user.is_approved && !user.is_admin) {
                pendingUsers.push(user);
            }
        }
        return pendingUsers;
    });
}

function getPendingUsersCount() {
    return getPendingUsers().then(function(pendingUsers) {
        return pendingUsers.length;
    });
}

function approveUser(userId) {
    return getUserById(userId).then(function(user) {
        if (!user) {
            return { success: false, message: 'User not found' };
        }
        
        return hset('user:' + userId, 'is_approved', 'true');
    }).then(function() {
        return { 
            success: true, 
            message: 'User approved successfully' 
        };
    });
}

function rejectUser(userId) {
    return getUserById(userId).then(function(user) {
        if (!user) {
            return { success: false, message: 'User not found' };
        }
        
        // Delete user data
        var promises = [
            del('user:' + userId),
            del('username:' + user.username),
            sendRedisCommand(['SREM', 'users', userId])
        ];
        
        return Promise.all(promises);
    }).then(function() {
        return { 
            success: true, 
            message: 'User rejected and deleted' 
        };
    });
}

function deleteUser(userId) {
    return getUserById(userId).then(function(user) {
        if (!user) {
            return { success: false, message: 'User not found' };
        }
        
        if (user.is_admin) {
            return { success: false, message: 'Cannot delete admin user' };
        }
        
        // Delete user data
        var promises = [
            del('user:' + userId),
            del('username:' + user.username),
            sendRedisCommand(['SREM', 'users', userId])
        ];
        
        return Promise.all(promises);
    }).then(function() {
        return { 
            success: true, 
            message: 'User deleted successfully' 
        };
    });
}

// Database statistics
function getDatabaseStats() {
    return getAllUsers().then(function(users) {
        var pendingCount = 0;
        var approvedCount = 0;
        
        for (var i = 0; i < users.length; i++) {
            var user = users[i];
            if (!user.is_approved && !user.is_admin) {
                pendingCount++;
            } else {
                approvedCount++;
            }
        }
        
        return {
            user_count: users.length,
            pending_count: pendingCount,
            approved_count: approvedCount,
            total_keys: users.length * 2, // Rough estimate: user data + username index
            key_types: {
                'user:*': users.length,
                'username:*': users.length,
                'system': 1
            }
        };
    });
}

// Handle complex Redis commands
function handleRedisCommand(r) {
    try {
        if (r.method !== 'POST') {
            return utils.sendError(r, 405, 'Method not allowed');
        }

        var body = JSON.parse(r.requestBody);
        var command = body.command;

        if (!Array.isArray(command)) {
            return utils.sendError(r, 400, 'Command must be an array');
        }

        // Security: Only allow safe commands
        var allowedCommands = [
            'GET', 'SET', 'HGET', 'HSET', 'HGETALL', 'SMEMBERS', 'SADD', 
            'SREM', 'ZADD', 'ZRANGE', 'ZREVRANGE', 'INCR', 'EXISTS', 'DEL',
            'MGET', 'MSET', 'HMGET', 'HMSET', 'KEYS', 'TYPE'
        ];

        var cmd = command[0].toUpperCase();
        var isAllowed = false;
        for (var i = 0; i < allowedCommands.length; i++) {
            if (allowedCommands[i] === cmd) {
                isAllowed = true;
                break;
            }
        }
        
        if (!isAllowed) {
            return utils.sendError(r, 403, 'Command ' + cmd + ' not allowed');
        }

        sendRedisCommand(command).then(function(result) {
            return utils.sendSuccess(r, result);
        }).catch(function(error) {
            r.error('Redis command error: ' + error.message);
            return utils.sendError(r, 500, 'Redis operation failed');
        });

    } catch (error) {
        r.error('Redis command error: ' + error.message);
        return utils.sendError(r, 500, 'Redis operation failed');
    }
}

// Handle database requests
function handleDatabaseRequest(r) {
    try {
        var pathParts = r.uri.split('/').filter(function(p) { return p; });
        var operation = pathParts[2]; // /api/database/{operation}
        
        switch (operation) {
            case 'stats':
                getDatabaseStats().then(function(stats) {
                    return utils.sendSuccess(r, stats);
                }).catch(function(error) {
                    r.error('Database stats error: ' + error.message);
                    return utils.sendError(r, 500, 'Database operation failed');
                });
                break;
                
            case 'users':
                getAllUsers().then(function(users) {
                    return utils.sendSuccess(r, users);
                }).catch(function(error) {
                    r.error('Get users error: ' + error.message);
                    return utils.sendError(r, 500, 'Database operation failed');
                });
                break;
                
            case 'pending':
                getPendingUsers().then(function(pending) {
                    return utils.sendSuccess(r, pending);
                }).catch(function(error) {
                    r.error('Get pending users error: ' + error.message);
                    return utils.sendError(r, 500, 'Database operation failed');
                });
                break;
                
            default:
                return utils.sendError(r, 404, 'Database operation not found');
        }
        
    } catch (error) {
        r.error('Database request error: ' + error.message);
        return utils.sendError(r, 500, 'Database operation failed');
    }
}

// Handle chat requests
function handleChatRequest(r) {
    try {
        // TODO: Implement chat-specific database operations
        return utils.sendError(r, 501, 'Chat endpoints not implemented yet');
        
    } catch (error) {
        r.error('Chat request error: ' + error.message);
        return utils.sendError(r, 500, 'Chat operation failed');
    }
}

export default {
    sendRedisCommand: sendRedisCommand,
    get: get,
    set: set,
    hget: hget,
    hset: hset,
    hgetall: hgetall,
    sadd: sadd,
    smembers: smembers,
    incr: incr,
    exists: exists,
    del: del,
    getUserByUsername: getUserByUsername,
    getUserById: getUserById,
    saveUser: saveUser,
    getAllUsers: getAllUsers,
    getPendingUsers: getPendingUsers,
    getPendingUsersCount: getPendingUsersCount,
    approveUser: approveUser,
    rejectUser: rejectUser,
    deleteUser: deleteUser,
    getDatabaseStats: getDatabaseStats,
    handleRedisCommand: handleRedisCommand,
    handleDatabaseRequest: handleDatabaseRequest,
    handleChatRequest: handleChatRequest
};