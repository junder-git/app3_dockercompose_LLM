// models.js - Data Models (JavaScript equivalent of Python models.py)

class User {
    constructor(userId = null, username = null, passwordHash = null, isAdmin = false, isApproved = false, createdAt = null) {
        this.id = userId ? String(userId) : null;
        this.username = username;
        this.password_hash = passwordHash;
        this.is_admin = isAdmin;
        this.is_approved = isApproved;
        this.created_at = createdAt || new Date().toISOString();
    }
    
    toDict() {
        return {
            id: String(this.id),
            username: String(this.username),
            password_hash: String(this.password_hash),
            is_admin: String(this.is_admin).toLowerCase(), // Convert boolean to string
            is_approved: String(this.is_approved).toLowerCase(), // Convert boolean to string
            created_at: String(this.created_at)
        };
    }
    
    fromDict(data) {
        this.id = data.id;
        this.username = data.username;
        this.password_hash = data.password_hash;
        this.is_admin = (data.is_admin || 'false').toLowerCase() === 'true'; // Convert string back to boolean
        this.is_approved = (data.is_approved || 'false').toLowerCase() === 'true'; // Convert string back to boolean
        this.created_at = data.created_at;
        return this;
    }

    // Utility methods
    getDisplayName() {
        return this.username;
    }

    isAdminUser() {
        return this.is_admin;
    }

    isApprovedUser() {
        return this.is_approved || this.is_admin;
    }

    getCreatedDate() {
        return new Date(this.created_at);
    }

    getFormattedCreatedDate() {
        return this.getCreatedDate().toLocaleDateString();
    }
}

class ChatSession {
    constructor(sessionId = null, userId = null, title = null, createdAt = null, updatedAt = null) {
        this.id = sessionId || `${userId}_${Date.now()}`;
        this.user_id = String(userId);
        this.title = title || `Chat ${new Date().toLocaleString()}`;
        this.created_at = createdAt || new Date().toISOString();
        this.updated_at = updatedAt || new Date().toISOString();
    }

    toDict() {
        return {
            id: this.id,
            user_id: this.user_id,
            title: this.title,
            created_at: this.created_at,
            updated_at: this.updated_at
        };
    }

    fromDict(data) {
        this.id = data.id;
        this.user_id = data.user_id;
        this.title = data.title;
        this.created_at = data.created_at;
        this.updated_at = data.updated_at;
        return this;
    }

    // Utility methods
    getCreatedDate() {
        return new Date(this.created_at);
    }

    getUpdatedDate() {
        return new Date(this.updated_at);
    }

    getFormattedCreatedDate() {
        return this.getCreatedDate().toLocaleDateString();
    }

    getFormattedUpdatedDate() {
        return this.getUpdatedDate().toLocaleDateString();
    }

    updateLastActivity() {
        this.updated_at = new Date().toISOString();
    }

    getDisplayTitle() {
        return this.title || `Chat ${this.getFormattedCreatedDate()}`;
    }

    getShortTitle(maxLength = 30) {
        const title = this.getDisplayTitle();
        if (title.length <= maxLength) return title;
        return title.substring(0, maxLength - 3) + '...';
    }
}

class ChatMessage {
    constructor(messageId = null, userId = null, role = null, content = null, sessionId = null, timestamp = null) {
        this.id = messageId || this.generateMessageId();
        this.user_id = String(userId);
        this.role = role; // 'user' or 'assistant'
        this.content = content || '';
        this.session_id = sessionId;
        this.timestamp = timestamp || new Date().toISOString();
        this.cached = false;
    }

    generateMessageId() {
        return `msg_${Date.now()}_${Math.random().toString(36).substr(2, 8)}`;
    }

    toDict() {
        return {
            id: this.id,
            user_id: this.user_id,
            role: this.role,
            content: this.content,
            session_id: this.session_id,
            timestamp: this.timestamp,
            cached: String(this.cached).toLowerCase()
        };
    }

    fromDict(data) {
        this.id = data.id;
        this.user_id = data.user_id;
        this.role = data.role;
        this.content = data.content;
        this.session_id = data.session_id;
        this.timestamp = data.timestamp;
        this.cached = (data.cached || 'false').toLowerCase() === 'true';
        return this;
    }

    // Utility methods
    isUserMessage() {
        return this.role === 'user';
    }

    isAssistantMessage() {
        return this.role === 'assistant';
    }

    getTimestamp() {
        return new Date(this.timestamp);
    }

    getFormattedTimestamp() {
        return this.getTimestamp().toLocaleString();
    }

    getShortTimestamp() {
        const date = this.getTimestamp();
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMs / 3600000);
        const diffDays = Math.floor(diffMs / 86400000);

        if (diffMins < 1) return 'Just now';
        if (diffMins < 60) return `${diffMins}m ago`;
        if (diffHours < 24) return `${diffHours}h ago`;
        if (diffDays < 7) return `${diffDays}d ago`;
        return date.toLocaleDateString();
    }

    getContentPreview(maxLength = 100) {
        if (!this.content) return '';
        if (this.content.length <= maxLength) return this.content;
        return this.content.substring(0, maxLength - 3) + '...';
    }

    markAsCached() {
        this.cached = true;
    }
}

// Authentication and Session Management
class AuthSession {
    constructor() {
        this.sessionKey = 'devstral_auth_session';
        this.csrfKey = 'devstral_csrf_token';
        this.userKey = 'devstral_current_user';
    }

    setSession(user, csrfToken) {
        const sessionData = {
            user: user.toDict(),
            csrf_token: csrfToken,
            expires: Date.now() + (7 * 24 * 60 * 60 * 1000), // 7 days
            created: Date.now()
        };
        
        localStorage.setItem(this.sessionKey, JSON.stringify(sessionData));
        localStorage.setItem(this.csrfKey, csrfToken);
        localStorage.setItem(this.userKey, JSON.stringify(user.toDict()));
    }

    getSession() {
        try {
            const sessionData = localStorage.getItem(this.sessionKey);
            if (!sessionData) return null;

            const session = JSON.parse(sessionData);
            
            // Check if session is expired
            if (Date.now() > session.expires) {
                this.clearSession();
                return null;
            }

            return session;
        } catch (error) {
            console.error('Error getting session:', error);
            this.clearSession();
            return null;
        }
    }

    getCurrentUser() {
        const session = this.getSession();
        if (!session) return null;

        try {
            return new User().fromDict(session.user);
        } catch (error) {
            console.error('Error getting current user:', error);
            this.clearSession();
            return null;
        }
    }

    getCsrfToken() {
        const session = this.getSession();
        return session ? session.csrf_token : null;
    }

    clearSession() {
        localStorage.removeItem(this.sessionKey);
        localStorage.removeItem(this.csrfKey);
        localStorage.removeItem(this.userKey);
    }

    updateUser(user) {
        const session = this.getSession();
        if (session) {
            session.user = user.toDict();
            localStorage.setItem(this.sessionKey, JSON.stringify(session));
            localStorage.setItem(this.userKey, JSON.stringify(user.toDict()));
        }
    }

    isAuthenticated() {
        return this.getCurrentUser() !== null;
    }

    generateCsrfToken() {
        return 'csrf_' + Date.now() + '_' + Math.random().toString(36).substr(2, 16);
    }
}

// API Response Models
class ApiResponse {
    constructor(success = false, message = '', data = null, error = null) {
        this.success = success;
        this.message = message;
        this.data = data;
        this.error = error;
        this.timestamp = new Date().toISOString();
    }

    static success(message, data = null) {
        return new ApiResponse(true, message, data);
    }

    static error(message, error = null) {
        return new ApiResponse(false, message, null, error);
    }

    toJSON() {
        return {
            success: this.success,
            message: this.message,
            data: this.data,
            error: this.error,
            timestamp: this.timestamp
        };
    }
}

class StreamingResponse {
    constructor(streamId) {
        this.streamId = streamId;
        this.content = '';
        this.isComplete = false;
        this.isInterrupted = false;
        this.isCached = false;
        this.error = null;
        this.chunks = [];
        this.startTime = Date.now();
        this.endTime = null;
    }

    addContent(content) {
        this.content += content;
        this.chunks.push({
            content: content,
            timestamp: Date.now()
        });
    }

    markComplete() {
        this.isComplete = true;
        this.endTime = Date.now();
    }

    markInterrupted() {
        this.isInterrupted = true;
        this.endTime = Date.now();
    }

    markCached() {
        this.isCached = true;
        this.markComplete();
    }

    setError(error) {
        this.error = error;
        this.endTime = Date.now();
    }

    getDuration() {
        const end = this.endTime || Date.now();
        return end - this.startTime;
    }

    getWordsPerMinute() {
        if (!this.content) return 0;
        const words = this.content.split(/\s+/).length;
        const minutes = this.getDuration() / 60000;
        return Math.round(words / minutes);
    }
}

// Configuration Model
class AppConfig {
    constructor() {
        this.defaults = {
            OLLAMA_URL: '/api/ollama',
            REDIS_URL: '/api/redis',
            OLLAMA_MODEL: 'devstral',
            MODEL_TEMPERATURE: 0.7,
            MODEL_MAX_TOKENS: 32,
            CHAT_HISTORY_LIMIT: 5,
            RATE_LIMIT_MAX: 100,
            SESSION_LIFETIME_DAYS: 7,
            MIN_USERNAME_LENGTH: 3,
            MAX_USERNAME_LENGTH: 50,
            MIN_PASSWORD_LENGTH: 6,
            MAX_PASSWORD_LENGTH: 128,
            MAX_MESSAGE_LENGTH: 5000
        };
        
        this.config = { ...this.defaults };
    }

    get(key) {
        return this.config[key] || this.defaults[key];
    }

    set(key, value) {
        this.config[key] = value;
    }

    getAll() {
        return { ...this.config };
    }

    reset() {
        this.config = { ...this.defaults };
    }
}

// Make models available globally
window.User = User;
window.ChatSession = ChatSession;
window.ChatMessage = ChatMessage;
window.AuthSession = AuthSession;
window.ApiResponse = ApiResponse;
window.StreamingResponse = StreamingResponse;
window.AppConfig = AppConfig;

// Create global instances
window.authSession = new AuthSession();
window.appConfig = new AppConfig();

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        User,
        ChatSession,
        ChatMessage,
        AuthSession,
        ApiResponse,
        StreamingResponse,
        AppConfig
    };
}