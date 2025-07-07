// nginx/njs/models.js - Server-side data models for njs

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
            is_admin: String(this.is_admin), // Redis stores as strings
            is_approved: String(this.is_approved), // Redis stores as strings
            created_at: String(this.created_at)
        };
    }
    
    fromDict(data) {
        this.id = data.id;
        this.username = data.username;
        this.password_hash = data.password_hash;
        this.is_admin = (data.is_admin === 'true'); // Convert string to boolean
        this.is_approved = (data.is_approved === 'true'); // Convert string to boolean
        this.created_at = data.created_at;
        return this;
    }

    isAdminUser() {
        return this.is_admin;
    }

    isApprovedUser() {
        return this.is_approved || this.is_admin;
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

    updateLastActivity() {
        this.updated_at = new Date().toISOString();
    }
}

// Export for njs
export default {
    User,
    ChatSession
};