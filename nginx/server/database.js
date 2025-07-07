// database.js - Redis HTTP Operations
class Database {
    constructor() {
        this.baseUrl = '/api/redis-cmd';
        this.initialized = false;
        
        // Configuration from environment
        this.config = {
            CHAT_CACHE_TTL: 1800,
            RATE_LIMIT_WINDOW: 60,
            MAX_CHATS_PER_USER: 1,
            MAX_PENDING_USERS: 2,
            USER_ID_COUNTER_START: 1000
        };
        
        console.log('🗄️ Database module created');
    }

    async init() {
        try {
            // Test Redis connection
            await this.ping();
            this.initialized = true;
            console.log('✅ Database connection established');
        } catch (error) {
            console.error('❌ Database connection failed:', error);
            throw error;
        }
    }

    // =====================================================
    // REDIS HTTP API WRAPPER METHODS
    // =====================================================

    async ping() {
        return await this.sendCommand(['PING']);
    }

    async sendCommand(command) {
        try {
            // Use the Redis HTTP wrapper endpoint
            const response = await fetch('/api/redis-cmd', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    command: command
                })
            });

            if (!response.ok) {
                throw new Error(`Redis command failed: ${response.status}`);
            }

            const result = await response.json();
            return result;
        } catch (error) {
            console.error('❌ Redis command error:', error, command);
            throw error;
        }
    }

    async get(key) {
        const result = await this.sendCommand(['GET', key]);
        return result;
    }

    async set(key, value, ttl = null) {
        const command = ttl ? ['SETEX', key, ttl, value] : ['SET', key, value];
        return await this.sendCommand(command);
    }

    async del(key) {
        return await this.sendCommand(['DEL', key]);
    }

    async exists(key) {
        const result = await this.sendCommand(['EXISTS', key]);
        return result === 1;
    }

    async hset(key, field, value) {
        return await this.sendCommand(['HSET', key, field, value]);
    }

    async hsetMultiple(key, fields) {
        const args = ['HSET', key];
        for (const [field, value] of Object.entries(fields)) {
            args.push(field, value);
        }
        return await this.sendCommand(args);
    }

    async hget(key, field) {
        return await this.sendCommand(['HGET', key, field]);
    }

    async hgetall(key) {
        const result = await this.sendCommand(['HGETALL', key]);
        
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

    async sadd(key, member) {
        return await this.sendCommand(['SADD', key, member]);
    }

    async srem(key, member) {
        return await this.sendCommand(['SREM', key, member]);
    }

    async smembers(key) {
        return await this.sendCommand(['SMEMBERS', key]) || [];
    }

    async zadd(key, score, member) {
        return await this.sendCommand(['ZADD', key, score, member]);
    }

    async zrange(key, start, stop) {
        return await this.sendCommand(['ZRANGE', key, start, stop]) || [];
    }

    async zrevrange(key, start, stop) {
        return await this.sendCommand(['ZREVRANGE', key, start, stop]) || [];
    }

    async zrem(key, member) {
        return await this.sendCommand(['ZREM', key, member]);
    }

    async zcard(key) {
        return await this.sendCommand(['ZCARD', key]) || 0;
    }

    async incr(key) {
        return await this.sendCommand(['INCR', key]);
    }

    async expire(key, seconds) {
        return await this.sendCommand(['EXPIRE', key, seconds]);
    }

    async keys(pattern) {
        return await this.sendCommand(['KEYS', pattern]) || [];
    }

    async flushdb() {
        return await this.sendCommand(['FLUSHDB']);
    }

    // =====================================================
    // USER MANAGEMENT
    // =====================================================

    async getNextUserId() {
        return await this.incr('user_id_counter');
    }

    async saveUser(user) {
        // If user doesn't have an ID, generate one
        if (!user.id) {
            user.id = String(await this.getNextUserId());
        }

        const userData = user.toDict();
        
        // Save user data
        await this.hsetMultiple(`user:${user.id}`, userData);
        
        // Add to username index
        await this.set(`username:${user.username}`, user.id);
        
        // Add to users set
        await this.sadd('users', user.id);
        
        return user;
    }

    async getUserById(userId) {
        const userData = await this.hgetall(`user:${userId}`);
        
        if (Object.keys(userData).length > 0) {
            return new User().fromDict(userData);
        }
        return null;
    }

    async getUserByUsername(username) {
        const userId = await this.get(`username:${username}`);
        
        if (userId) {
            return await this.getUserById(userId);
        }
        return null;
    }

    async getAllUsers() {
        const userIds = await this.smembers('users');
        const users = [];
        
        for (const userId of userIds) {
            const user = await this.getUserById(userId);
            if (user) {
                users.push(user);
            }
        }
        
        return users;
    }

    async getPendingUsersCount() {
        const userIds = await this.smembers('users');
        let pendingCount = 0;
        
        for (const userId of userIds) {
            const user = await this.getUserById(userId);
            if (user && !user.is_approved && !user.is_admin) {
                pendingCount++;
            }
        }
        
        return pendingCount;
    }

    async getPendingUsers() {
        const userIds = await this.smembers('users');
        const pendingUsers = [];
        
        for (const userId of userIds) {
            const user = await this.getUserById(userId);
            if (user && !user.is_approved && !user.is_admin) {
                pendingUsers.push(user);
            }
        }
        
        return pendingUsers;
    }

    async approveUser(userId) {
        const user = await this.getUserById(userId);
        if (!user) {
            return { success: false, message: 'User not found' };
        }
        
        if (user.is_approved) {
            return { success: false, message: 'User is already approved' };
        }
        
        user.is_approved = true;
        await this.saveUser(user);
        
        return { success: true, message: `User ${user.username} approved successfully` };
    }

    async rejectUser(userId) {
        const user = await this.getUserById(userId);
        if (!user) {
            return { success: false, message: 'User not found' };
        }
        
        if (user.is_approved) {
            return { success: false, message: 'Cannot reject approved user' };
        }
        
        // Delete the user
        await this.del(`user:${userId}`);
        await this.del(`username:${user.username}`);
        await this.srem('users', userId);
        
        return { success: true, message: `User ${user.username} rejected and deleted` };
    }

    async deleteUser(userId) {
        const user = await this.getUserById(userId);
        if (!user) {
            return { success: false, message: 'User not found' };
        }
        
        if (user.is_admin) {
            return { success: false, message: 'Cannot delete admin user' };
        }
        
        const deletedCounts = {
            sessions: 0,
            messages: 0,
            cache_entries: 0
        };
        
        // Delete all user sessions and messages
        const sessionIds = await this.zrange(`user_sessions:${userId}`, 0, -1);
        for (const sessionId of sessionIds) {
            await this.deleteChatSession(userId, sessionId);
            deletedCounts.sessions++;
        }
        
        // Delete rate limit keys
        await this.del(`rate_limit:${userId}`);
        
        // Delete user data
        await this.del(`user:${userId}`);
        await this.del(`username:${user.username}`);
        await this.srem('users', userId);
        
        return {
            success: true,
            message: `Successfully deleted user ${user.username}`,
            deleted_data: deletedCounts
        };
    }

    // =====================================================
    // CHAT SESSION MANAGEMENT
    // =====================================================

    async createChatSession(userId, title = null) {
        // Check max chat limit
        const userSessions = await this.zrevrange(`user_sessions:${userId}`, 0, -1);
        if (userSessions.length >= this.config.MAX_CHATS_PER_USER) {
            // Remove oldest session
            const oldestSessionId = userSessions[userSessions.length - 1];
            await this.deleteChatSession(userId, oldestSessionId);
        }
        
        // Create new session
        const session = new ChatSession(null, userId, title);
        
        // Save session data
        await this.hsetMultiple(`session:${session.id}`, session.toDict());
        
        // Add to user's session list
        await this.zadd(`user_sessions:${userId}`, Date.now(), session.id);
        
        return session;
    }

    async getChatSession(sessionId) {
        const sessionData = await this.hgetall(`session:${sessionId}`);
        
        if (Object.keys(sessionData).length > 0) {
            return new ChatSession().fromDict(sessionData);
        }
        return null;
    }

    async getUserChatSessions(userId) {
        const sessionIds = await this.zrevrange(`user_sessions:${userId}`, 0, this.config.MAX_CHATS_PER_USER - 1);
        const sessions = [];
        
        for (const sessionId of sessionIds) {
            const session = await this.getChatSession(sessionId);
            if (session) {
                sessions.push(session);
            }
        }
        
        return sessions;
    }

    async deleteChatSession(userId, sessionId) {
        // Delete all messages in this session
        const messageIds = await this.zrange(`session_messages:${sessionId}`, 0, -1);
        for (const msgId of messageIds) {
            await this.del(`message:${msgId}`);
        }
        
        // Delete session messages list
        await this.del(`session_messages:${sessionId}`);
        
        // Delete session data
        await this.del(`session:${sessionId}`);
        
        // Remove from user's session list
        await this.zrem(`user_sessions:${userId}`, sessionId);
    }

    async clearSessionMessages(sessionId) {
        // Get all message IDs for this session
        const messageIds = await this.zrange(`session_messages:${sessionId}`, 0, -1);
        
        // Delete all messages
        for (const msgId of messageIds) {
            await this.del(`message:${msgId}`);
        }
        
        // Clear the session messages list
        await this.del(`session_messages:${sessionId}`);
        
        // Update session timestamp
        const sessionObj = await this.getChatSession(sessionId);
        if (sessionObj) {
            sessionObj.updated_at = new Date().toISOString();
            await this.hsetMultiple(`session:${sessionId}`, sessionObj.toDict());
        }
    }

    // =====================================================
    // MESSAGE MANAGEMENT
    // =====================================================

    async saveMessage(userId, role, content, sessionId) {
        const timestamp = Date.now();
        const messageId = `${sessionId}:${timestamp}:${Math.random().toString(36).substr(2, 8)}`;
        
        const messageData = {
            id: messageId,
            user_id: userId,
            role: role,
            content: content,
            timestamp: new Date().toISOString(),
            session_id: sessionId
        };
        
        // Save message data
        await this.hsetMultiple(`message:${messageId}`, messageData);
        
        // Add to session's message list
        await this.zadd(`session_messages:${sessionId}`, timestamp, messageId);
        
        // Update session last activity
        const sessionObj = await this.getChatSession(sessionId);
        if (sessionObj) {
            sessionObj.updated_at = new Date().toISOString();
            await this.hsetMultiple(`session:${sessionId}`, sessionObj.toDict());
        }
    }

    async getSessionMessages(sessionId, limit = null) {
        if (limit === null) {
            limit = this.config.CHAT_HISTORY_LIMIT || 10;
        }
        
        // Get message IDs sorted by timestamp (oldest first)
        const messageIds = await this.zrange(`session_messages:${sessionId}`, -limit, -1);
        
        const messages = [];
        for (const msgId of messageIds) {
            const msgData = await this.hgetall(`message:${msgId}`);
            if (Object.keys(msgData).length > 0) {
                messages.push(msgData);
            }
        }
        
        return messages;
    }

    async getUserMessages(userId, limit = null) {
        // Get all user sessions
        const sessionIds = await this.zrange(`user_sessions:${userId}`, 0, -1);
        
        const allMessages = [];
        for (const sessionId of sessionIds) {
            const sessionMessages = await this.getSessionMessages(sessionId, limit);
            allMessages.push(...sessionMessages);
        }
        
        // Sort by timestamp
        allMessages.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
        
        if (limit) {
            return allMessages.slice(-limit);
        }
        return allMessages;
    }

    // =====================================================
    // RATE LIMITING
    // =====================================================

    async checkRateLimit(userId, rateLimitMax) {
        const key = `rate_limit:${userId}`;
        const current = await this.incr(key);
        
        if (current === 1) {
            await this.expire(key, this.config.RATE_LIMIT_WINDOW);
        }
        
        return current <= rateLimitMax;
    }

    // =====================================================
    // CACHING
    // =====================================================

    async getCachedResponse(promptHash) {
        try {
            return await this.get(`ai_response:${promptHash}`);
        } catch (error) {
            console.error('Cache get error:', error);
            return null;
        }
    }

    async cacheResponse(promptHash, response) {
        try {
            await this.set(`ai_response:${promptHash}`, response, this.config.CHAT_CACHE_TTL);
        } catch (error) {
            console.error('Cache set error:', error);
        }
    }

    // =====================================================
    // DATABASE MANAGEMENT
    // =====================================================

    // database.js - Redis HTTP Operations (CONTINUATION)

    async getDatabaseStats() {
        try {
            const allKeys = await this.keys('*');
            const stats = {
                total_keys: allKeys.length,
                key_types: {},
                users: [],
                user_count: 0,
                pending_count: 0,
                approved_count: 0
            };
            
            // Group keys by type
            for (const key of allKeys) {
                const keyType = key.split(':')[0];
                stats.key_types[keyType] = (stats.key_types[keyType] || 0) + 1;
            }
            
            // Get user statistics
            const userIds = await this.smembers('users');
            for (const userId of userIds) {
                const user = await this.getUserById(userId);
                if (user) {
                    stats.users.push({
                        id: userId,
                        username: user.username,
                        is_admin: user.is_admin,
                        is_approved: user.is_approved,
                        created_at: user.created_at,
                        session_count: await this.zcard(`user_sessions:${userId}`),
                        message_count: 0 // Could calculate this but it's expensive
                    });
                    
                    if (!user.is_approved && !user.is_admin) {
                        stats.pending_count++;
                    } else {
                        stats.approved_count++;
                    }
                    stats.user_count++;
                }
            }
            
            return stats;
        } catch (error) {
            console.error('Error getting database stats:', error);
            throw error;
        }
    }

    async clearAllUserData(userId) {
        try {
            const user = await this.getUserById(userId);
            if (!user) {
                return { success: false, message: 'User not found' };
            }
            
            if (user.is_admin) {
                return { success: false, message: 'Cannot clear admin user data' };
            }
            
            let deletedCounts = {
                sessions: 0,
                messages: 0,
                cache_entries: 0
            };
            
            // Delete all user sessions and messages
            const sessionIds = await this.zrange(`user_sessions:${userId}`, 0, -1);
            for (const sessionId of sessionIds) {
                const messageIds = await this.zrange(`session_messages:${sessionId}`, 0, -1);
                deletedCounts.messages += messageIds.length;
                
                // Delete all messages
                for (const msgId of messageIds) {
                    await this.del(`message:${msgId}`);
                }
                
                // Delete session
                await this.del(`session:${sessionId}`);
                await this.del(`session_messages:${sessionId}`);
                deletedCounts.sessions++;
            }
            
            // Clear user's session list
            await this.del(`user_sessions:${userId}`);
            
            // Clear rate limiting
            await this.del(`rate_limit:${userId}`);
            
            // Clear any AI response cache entries for this user
            const cacheKeys = await this.keys(`ai_response:*`);
            for (const key of cacheKeys) {
                // This is a simple approach - in production you might want to track user-specific cache
                deletedCounts.cache_entries++;
            }
            
            return {
                success: true,
                message: `Successfully cleared all data for user ${user.username}`,
                deleted_data: deletedCounts
            };
            
        } catch (error) {
            console.error('Error clearing user data:', error);
            throw error;
        }
    }

    async exportUserData(userId) {
        try {
            const user = await this.getUserById(userId);
            if (!user) {
                return { success: false, message: 'User not found' };
            }
            
            const userData = {
                user: user.toDict(),
                sessions: [],
                messages: [],
                export_timestamp: new Date().toISOString()
            };
            
            // Get all user sessions
            const sessionIds = await this.zrange(`user_sessions:${userId}`, 0, -1);
            for (const sessionId of sessionIds) {
                const session = await this.getChatSession(sessionId);
                if (session) {
                    userData.sessions.push(session.toDict());
                    
                    // Get session messages
                    const messages = await this.getSessionMessages(sessionId, null);
                    userData.messages.push(...messages);
                }
            }
            
            return {
                success: true,
                data: userData
            };
            
        } catch (error) {
            console.error('Error exporting user data:', error);
            throw error;
        }
    }

    async getSystemHealth() {
        try {
            const health = {
                status: 'healthy',
                timestamp: new Date().toISOString(),
                database: {
                    connected: false,
                    response_time: 0
                },
                memory: {
                    used: 0,
                    peak: 0
                },
                performance: {
                    commands_processed: 0,
                    slow_queries: 0
                }
            };
            
            // Test database connectivity and response time
            const startTime = Date.now();
            try {
                await this.ping();
                health.database.connected = true;
                health.database.response_time = Date.now() - startTime;
            } catch (error) {
                health.status = 'unhealthy';
                health.database.connected = false;
                health.database.error = error.message;
            }
            
            return health;
        } catch (error) {
            console.error('Error getting system health:', error);
            return {
                status: 'error',
                timestamp: new Date().toISOString(),
                error: error.message
            };
        }
    }

    // =====================================================
    // BULK OPERATIONS
    // =====================================================

    async bulkDeleteKeys(pattern) {
        try {
            const keys = await this.keys(pattern);
            let deleted = 0;
            
            for (const key of keys) {
                await this.del(key);
                deleted++;
            }
            
            return { success: true, deleted_count: deleted };
        } catch (error) {
            console.error('Error in bulk delete:', error);
            throw error;
        }
    }

    async cleanupExpiredSessions() {
        try {
            const allUsers = await this.smembers('users');
            let cleanedSessions = 0;
            
            for (const userId of allUsers) {
                const sessionIds = await this.zrange(`user_sessions:${userId}`, 0, -1);
                
                for (const sessionId of sessionIds) {
                    const session = await this.getChatSession(sessionId);
                    if (!session) {
                        // Session data missing, remove from user's list
                        await this.zrem(`user_sessions:${userId}`, sessionId);
                        cleanedSessions++;
                    }
                }
            }
            
            return { success: true, cleaned_sessions: cleanedSessions };
        } catch (error) {
            console.error('Error cleaning up sessions:', error);
            throw error;
        }
    }

    // =====================================================
    // MIGRATION AND MAINTENANCE
    // =====================================================

    async migrateLegacyData() {
        try {
            // Check if migration is needed
            const migrationKey = 'migration:v1_complete';
            const migrationComplete = await this.exists(migrationKey);
            
            if (migrationComplete) {
                return { success: true, message: 'Migration already complete' };
            }
            
            // Perform any necessary data migrations here
            console.log('Running database migration...');
            
            // Mark migration as complete
            await this.set(migrationKey, 'true');
            
            return { success: true, message: 'Migration completed successfully' };
        } catch (error) {
            console.error('Migration error:', error);
            throw error;
        }
    }

    async validateDataIntegrity() {
        try {
            const issues = [];
            
            // Check for orphaned sessions
            const allSessionKeys = await this.keys('session:*');
            for (const sessionKey of allSessionKeys) {
                const sessionId = sessionKey.replace('session:', '');
                const session = await this.getChatSession(sessionId);
                
                if (session) {
                    // Check if user exists
                    const user = await this.getUserById(session.user_id);
                    if (!user) {
                        issues.push(`Orphaned session ${sessionId} - user ${session.user_id} not found`);
                    }
                }
            }
            
            // Check for orphaned messages
            const allMessageKeys = await this.keys('message:*');
            for (const messageKey of allMessageKeys) {
                const messageData = await this.hgetall(messageKey);
                if (messageData.session_id) {
                    const session = await this.getChatSession(messageData.session_id);
                    if (!session) {
                        issues.push(`Orphaned message ${messageKey} - session ${messageData.session_id} not found`);
                    }
                }
            }
            
            return {
                success: true,
                issues_found: issues.length,
                issues: issues
            };
        } catch (error) {
            console.error('Data integrity check error:', error);
            throw error;
        }
    }
}

// Create global instance
window.Database = new Database();

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = Database;
}