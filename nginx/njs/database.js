// nginx/njs/database.js - Server-side Redis operations using redis2 module

import utils from './utils.js';

// Redis operations using nginx redis2 module
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
                
            case 'SETEX':
                if (args.length !== 3) throw new Error('SETEX requires 3 arguments');
                url = `/redis-internal/setex/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}/${encodeURIComponent(args[2])}`;
                break;
                
            case 'HGET':
                if (args.length !== 2) throw new Error('HGET requires 2 arguments');
                url = `/redis-internal/hget/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}`;
                break;
                
            case 'HSET':
                if (args.length !== 3) throw new Error('HSET requires 3 arguments');
                url = `/redis-internal/hset/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}/${encodeURIComponent(args[2])}`;
                break;
                
            case 'HGETALL':
                if (args.length !== 1) throw new Error('HGETALL requires 1 argument');
                url = `/redis-internal/hgetall/${encodeURIComponent(args[0])}`;
                break;
                
            case 'SMEMBERS':
                if (args.length !== 1) throw new Error('SMEMBERS requires 1 argument');
                url = `/redis-internal/smembers/${encodeURIComponent(args[0])}`;
                break;
                
            case 'SADD':
                if (args.length !== 2) throw new Error('SADD requires 2 arguments');
                url = `/redis-internal/sadd/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}`;
                break;
                
            case 'SREM':
                if (args.length !== 2) throw new Error('SREM requires 2 arguments');
                url = `/redis-internal/srem/${encodeURIComponent(args[0])}/${encodeURIComponent(args[1])}`;
                break;
                
            case 'INCR':
                if (args.length !== 1) throw new Error('INCR requires 1 argument');
                url = `/redis-internal/incr/${encodeURIComponent(args[0])}`;
                break;
                
            case 'EXISTS':
                if (args.length !== 1) throw new Error('EXISTS requires 1 argument');
                url = `/redis-internal/exists/${encodeURIComponent(args[0])}`;
                break;
                
            case 'DEL':
                if (args.length !== 1) throw new Error('DEL requires 1 argument');
                url = `/redis-internal/del/${encodeURIComponent(args[0])}`;
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
        const response = await ngx.fetch(url, {
            method: 'GET'
        });

        if (!response.ok) {
            throw new Error(`Redis request failed: ${response.status}`);
        }

        const text = await response.text();
        
        // Parse redis2 response format
        return parseRedisResponse(text, cmdUpper);
        
    } catch (error) {
        throw new Error(`Redis operation failed: ${error.message}`);
    }
}

function parseRedisResponse(text, command) {
    // Redis2 module returns responses in Redis protocol format
    // Parse based on first character
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
    const lines = text.split('\r\n');
    const count = parseInt(lines[0].slice(1), 10);
    
    if (count === -1) return null;
    if (count === 0) return [];
    
    const result = [];
    let lineIndex = 1;
    
    for (let i = 0; i < count; i++) {
        if (lineIndex >= lines.length) break;
        
        const type = lines[lineIndex][0];
        if (type === '$') {
            const len = parseInt(lines[lineIndex].slice(1), 10);
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
        const obj = {};
        for (let i = 0; i < result.length; i += 2) {
            if (i + 1 < result.length) {
                obj[result[i]] = result[i + 1];
            }
        }
        return obj;
    }
    
    return result;
}

// Basic Redis operations
async function get(key) {
    return await sendRedisCommand(['GET', key]);
}

async function set(key, value, ttl = null) {
    const command = ttl ? ['SETEX', key, ttl, value] : ['SET', key, value];
    return await sendRedisCommand(command);
}

async function hget(key, field) {
    return await sendRedisCommand(['HGET', key, field]);
}

async function hset(key, field, value) {
    return await sendRedisCommand(['HSET', key, field, value]);
}

async function hgetall(key) {
    return await sendRedisCommand(['HGETALL', key]);
}

async function sadd(key, value) {
    return await sendRedisCommand(['SADD', key, value]);
}

async function smembers(key) {
    return await sendRedisCommand(['SMEMBERS', key]);
}

async function incr(key) {
    return await sendRedisCommand(['INCR', key]);
}

async function exists(key) {
    return await sendRedisCommand(['EXISTS', key]);
}

async function del(key) {
    return await sendRedisCommand(['DEL', key]);
}

// User management functions
async function getUserByUsername(username) {
    const userId = await get(`username:${username}`);
    if (!userId) return null;
    
    const userData = await hgetall(`user:${userId}`);
    if (Object.keys(userData).length === 0) return null;
    
    return {
        id: userData.id,
        username: userData.username,
        password_hash: userData.password_hash,
        is_admin: userData.is_admin === 'true',
        is_approved: userData.is_approved === 'true',
        created_at: userData.created_at
    };
}

async function getUserById(userId) {
    const userData = await hgetall(`user:${userId}`);
    if (Object.keys(userData).length === 0) return null;
    
    return {
        id: userData.id,
        username: userData.username,
        password_hash: userData.password_hash,
        is_admin: userData.is_admin === 'true',
        is_approved: userData.is_approved === 'true',
        created_at: userData.created_at
    };
}

async function saveUser(user) {
    // Generate ID if needed
    if (!user.id) {
        user.id = String(await incr('user_id_counter'));
    }

    // Convert user to storage format
    const userData = {
        id: String(user.id),
        username: String(user.username),
        password_hash: String(user.password_hash),
        is_admin: String(user.is_admin),
        is_approved: String(user.is_approved),
        created_at: String(user.created_at)
    };

    // Save user data - hset one field at a time
    for (const [field, value] of Object.entries(userData)) {
        await hset(`user:${user.id}`, field, value);
    }

    // Add to username index
    await set(`username:${user.username}`, user.id);

    // Add to users set
    await sadd('users', user.id);

    return user;
}

async function getAllUsers() {
    const userIds = await smembers('users') || [];
    const users = [];
    
    for (const userId of userIds) {
        const user = await getUserById(userId);
        if (user) {
            users.push(user);
        }
    }
    
    return users;
}

async function getPendingUsers() {
    const allUsers = await getAllUsers();
    return allUsers.filter(user => !user.is_approved && !user.is_admin);
}

async function getPendingUsersCount() {
    const pendingUsers = await getPendingUsers();
    return pendingUsers.length;
}

async function approveUser(userId) {
    const user = await getUserById(userId);
    if (!user) {
        return { success: false, message: 'User not found' };
    }
    
    await hset(`user:${userId}`, 'is_approved', 'true');
    
    return { 
        success: true, 
        message: `User ${user.username} approved successfully` 
    };
}

async function rejectUser(userId) {
    const user = await getUserById(userId);
    if (!user) {
        return { success: false, message: 'User not found' };
    }
    
    // Delete user data
    await del(`user:${userId}`);
    await del(`username:${user.username}`);
    await sendRedisCommand(['SREM', 'users', userId]);
    
    return { 
        success: true, 
        message: `User ${user.username} rejected and deleted` 
    };
}

async function deleteUser(userId) {
    const user = await getUserById(userId);
    if (!user) {
        return { success: false, message: 'User not found' };
    }
    
    if (user.is_admin) {
        return { success: false, message: 'Cannot delete admin user' };
    }
    
    // Delete user data
    await del(`user:${userId}`);
    await del(`username:${user.username}`);
    await sendRedisCommand(['SREM', 'users', userId]);
    
    // TODO: Delete user's chat sessions and messages
    
    return { 
        success: true, 
        message: `User ${user.username} deleted successfully` 
    };
}

// Database statistics
async function getDatabaseStats() {
    const users = await getAllUsers();
    const pendingCount = users.filter(u => !u.is_approved && !u.is_admin).length;
    const approvedCount = users.filter(u => u.is_approved || u.is_admin).length;
    
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
}

// Handle complex Redis commands
async function handleRedisCommand(r) {
    try {
        if (r.method !== 'POST') {
            return utils.sendError(r, 405, 'Method not allowed');
        }

        const body = JSON.parse(r.requestBody);
        const command = body.command;

        if (!Array.isArray(command)) {
            return utils.sendError(r, 400, 'Command must be an array');
        }

        // Security: Only allow safe commands
        const allowedCommands = [
            'GET', 'SET', 'HGET', 'HSET', 'HGETALL', 'SMEMBERS', 'SADD', 
            'SREM', 'ZADD', 'ZRANGE', 'ZREVRANGE', 'INCR', 'EXISTS', 'DEL',
            'MGET', 'MSET', 'HMGET', 'HMSET', 'KEYS', 'TYPE'
        ];

        const cmd = command[0].toUpperCase();
        if (!allowedCommands.includes(cmd)) {
            return utils.sendError(r, 403, `Command ${cmd} not allowed`);
        }

        const result = await sendRedisCommand(command);
        return utils.sendSuccess(r, result);

    } catch (error) {
        r.error('Redis command error: ' + error.message);
        return utils.sendError(r, 500, 'Redis operation failed');
    }
}

// Handle database requests
async function handleDatabaseRequest(r) {
    try {
        const pathParts = r.uri.split('/').filter(p => p);
        const operation = pathParts[2]; // /api/database/{operation}
        
        switch (operation) {
            case 'stats':
                const stats = await getDatabaseStats();
                return utils.sendSuccess(r, stats);
                
            case 'users':
                const users = await getAllUsers();
                return utils.sendSuccess(r, users);
                
            case 'pending':
                const pending = await getPendingUsers();
                return utils.sendSuccess(r, pending);
                
            default:
                return utils.sendError(r, 404, 'Database operation not found');
        }
        
    } catch (error) {
        r.error('Database request error: ' + error.message);
        return utils.sendError(r, 500, 'Database operation failed');
    }
}

// Handle chat requests
async function handleChatRequest(r) {
    try {
        // TODO: Implement chat-specific database operations
        return utils.sendError(r, 501, 'Chat endpoints not implemented yet');
        
    } catch (error) {
        r.error('Chat request error: ' + error.message);
        return utils.sendError(r, 500, 'Chat operation failed');
    }
}

export default {
    sendRedisCommand,
    get,
    set,
    hget,
    hset,
    hgetall,
    sadd,
    smembers,
    incr,
    exists,
    del,
    getUserByUsername,
    getUserById,
    saveUser,
    getAllUsers,
    getPendingUsers,
    getPendingUsersCount,
    approveUser,
    rejectUser,
    deleteUser,
    getDatabaseStats,
    handleRedisCommand,
    handleDatabaseRequest,
    handleChatRequest
};