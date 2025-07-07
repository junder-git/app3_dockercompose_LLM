// nginx/njs/models.js - Server-side data models for njs (ES5 compatible)

function User(userId, username, passwordHash, isAdmin, isApproved, createdAt) {
    this.id = userId ? String(userId) : null;
    this.username = username;
    this.password_hash = passwordHash;
    this.is_admin = isAdmin || false;
    this.is_approved = isApproved || false;
    this.created_at = createdAt || new Date().toISOString();
}

User.prototype.toDict = function() {
    return {
        id: String(this.id),
        username: String(this.username),
        password_hash: String(this.password_hash),
        is_admin: String(this.is_admin), // Redis stores as strings
        is_approved: String(this.is_approved), // Redis stores as strings
        created_at: String(this.created_at)
    };
};

User.prototype.fromDict = function(data) {
    this.id = data.id;
    this.username = data.username;
    this.password_hash = data.password_hash;
    this.is_admin = (data.is_admin === 'true'); // Convert string to boolean
    this.is_approved = (data.is_approved === 'true'); // Convert string to boolean
    this.created_at = data.created_at;
    return this;
};

User.prototype.isAdminUser = function() {
    return this.is_admin;
};

User.prototype.isApprovedUser = function() {
    return this.is_approved || this.is_admin;
};

function ChatSession(sessionId, userId, title, createdAt, updatedAt) {
    this.id = sessionId || (userId + '_' + Date.now());
    this.user_id = String(userId);
    this.title = title || ('Chat ' + new Date().toLocaleString());
    this.created_at = createdAt || new Date().toISOString();
    this.updated_at = updatedAt || new Date().toISOString();
}

ChatSession.prototype.toDict = function() {
    return {
        id: this.id,
        user_id: this.user_id,
        title: this.title,
        created_at: this.created_at,
        updated_at: this.updated_at
    };
};

ChatSession.prototype.fromDict = function(data) {
    this.id = data.id;
    this.user_id = data.user_id;
    this.title = data.title;
    this.created_at = data.created_at;
    this.updated_at = data.updated_at;
    return this;
};

ChatSession.prototype.updateLastActivity = function() {
    this.updated_at = new Date().toISOString();
};

// Export for njs
export default {
    User: User,
    ChatSession: ChatSession
};