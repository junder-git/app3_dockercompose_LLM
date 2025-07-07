// nginx/njs/database.js - Server-side Redis operations for njs

import utils from './utils.js';

// Redis HTTP wrapper configuration
const REDIS_HTTP_URL = 'http://redis:8001';

async function sendRedisCommand(command) {
    try {
        // Use nginx's built-in ngx.fetch if available, otherwise use subrequest
        const response = await ngx.fetch(REDIS_HTTP_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ command: command })
        });

        if (!response.ok) {
            throw new Error(`Redis HTTP request failed: ${response.status}`);
        }

        const result = await response.json();
        return result;
    } catch (error) {
        throw new Error(`Redis operation failed: ${error.message}`);
    }
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
    const result = await sendRedisCommand(['HGETALL', key]);
    
    // Convert array result to object
    if (Array.isArray(result)) {
        const obj = {};
        for (let i = 0; i < result.length; i += 2) {
            obj[result[i]] = result[i + 1];
        }
        return obj;
    }
    
    return result || {};
}

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

async function saveUser(user) {
    // Generate ID if needed
    if (!user.id) {
        user.id = String(await sendRedisCommand(['INCR', 'user_id_counter']));
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

    // Save user data
    for (const [field, value] of Object.entries(userData)) {
        await hset(`user:${user.id}`, field, value);
    }

    // Add to username index
    await set(`username:${user.username}`, user.id);

    // Add to users set
    await sendRedisCommand(['SADD', 'users', user.id]);

    return user;
}

async function getPendingUsersCount() {
    const userIds = await sendRedisCommand(['SMEMBERS', 'users']) || [];
    let pendingCount = 0;

    for (const userId of userIds) {
        const userData = await hgetall(`user:${userId}`);
        if (userData.is_approved === 'false' && userData.is_admin === 'false') {
            pendingCount++;
        }
    }

    return pendingCount;
}

// Handle Redis proxy endpoint
async function handleRedisProxy(r) {
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
            'SREM', 'ZADD', 'ZRANGE', 'ZREVRANGE', 'INCR', 'EXISTS', 'DEL'
        ];

        const cmd = command[0].toUpperCase();
        if (!allowedCommands.includes(cmd)) {
            return utils.sendError(r, 403, `Command ${cmd} not allowed`);
        }

        const result = await sendRedisCommand(command);
        return utils.sendSuccess(r, result);

    } catch (error) {
        r.error('Redis proxy error: ' + error.message);
        return utils.sendError(r, 500, 'Redis operation failed');
    }
}

export default {
    get,
    set,
    hget,
    hset,
    hgetall,
    getUserByUsername,
    saveUser,
    getPendingUsersCount,
    handleRedisProxy,
    sendRedisCommand
};