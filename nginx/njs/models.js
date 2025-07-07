// Example of database model structure definitions

export class User {
  constructor(id, username, password_hash, is_admin = false) {
    this.id = id;
    this.username = username;
    this.password_hash = password_hash;
    this.is_admin = is_admin;
  }
}

export class ChatMessage {
  constructor(id, userId, message, createdAt = new Date().toISOString()) {
    this.id = id;
    this.userId = userId;
    this.message = message;
    this.createdAt = createdAt;
  }
}

export class Session {
  constructor(id, userId, createdAt = new Date().toISOString(), isActive = true) {
    this.id = id;
    this.userId = userId;
    this.createdAt = createdAt;
    this.isActive = isActive;
  }
}
