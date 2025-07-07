// nginx/njs/database.js - Updated Redis communication
async function getUserById(user_id) {
    try {
        const key = "user:" + user_id;
        const res = await ngx.fetch("/redis-internal/HGETALL/" + key);
        
        if (!res.ok) {
            return null;
        }
        
        const text = await res.text();
        if (!text || text.trim() === "") {
            return null;
        }
        
        // Parse Redis HGETALL response (field1\nvalue1\nfield2\nvalue2...)
        const lines = text.trim().split('\n');
        const user_data = {};
        
        for (let i = 0; i < lines.length; i += 2) {
            if (i + 1 < lines.length) {
                user_data[lines[i]] = lines[i + 1];
            }
        }
        
        return user_data.id ? user_data : null;
    } catch (e) {
        return null;
    }
}

async function getUserByUsername(username) {
    try {
        const key = "user:" + username;
        const res = await ngx.fetch("/redis-internal/HGETALL/" + key);
        
        if (!res.ok) {
            return null;
        }
        
        const text = await res.text();
        if (!text || text.trim() === "") {
            return null;
        }
        
        // Parse Redis HGETALL response
        const lines = text.trim().split('\n');
        const user_data = {};
        
        for (let i = 0; i < lines.length; i += 2) {
            if (i + 1 < lines.length) {
                user_data[lines[i]] = lines[i + 1];
            }
        }
        
        return user_data.username ? user_data : null;
    } catch (e) {
        return null;
    }
}

async function getAllUsers() {
    try {
        // Get all user keys
        const keysRes = await ngx.fetch("/redis-internal/KEYS/user:*");
        if (!keysRes.ok) {
            return [];
        }
        
        const keysText = await keysRes.text();
        if (!keysText || keysText.trim() === "") {
            return [];
        }
        
        const keys = keysText.trim().split('\n');
        const users = [];
        
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            if (key && key.startsWith('user:')) {
                const userData = await getUserByUsername(key.substring(5)); // Remove 'user:' prefix
                if (userData) {
                    users.push(userData);
                }
            }
        }
        
        return users;
    } catch (e) {
        return [];
    }
}

async function approveUser(user_id) {
    try {
        const key = "user:" + user_id;
        
        // Check if user exists
        const existsRes = await ngx.fetch("/redis-internal/EXISTS/" + key);
        if (!existsRes.ok) {
            return false;
        }
        
        const exists = await existsRes.text();
        if (exists.trim() !== "1") {
            return false;
        }
        
        // Set is_approved to true
        const setRes = await ngx.fetch("/redis-internal/HSET/" + key + "/is_approved/true");
        return setRes.ok;
    } catch (e) {
        return false;
    }
}

async function rejectUser(user_id) {
    try {
        const key = "user:" + user_id;
        
        // Check if user exists
        const existsRes = await ngx.fetch("/redis-internal/EXISTS/" + key);
        if (!existsRes.ok) {
            return false;
        }
        
        const exists = await existsRes.text();
        if (exists.trim() !== "1") {
            return false;
        }
        
        // Delete the user
        const delRes = await ngx.fetch("/redis-internal/DEL/" + key);
        return delRes.ok;
    } catch (e) {
        return false;
    }
}

async function saveUser(userDict) {
    try {
        const key = "user:" + userDict.username;
        
        // Build HSET command with all fields
        const fields = [
            "id", userDict.id,
            "username", userDict.username,
            "password_hash", userDict.password_hash,
            "is_admin", userDict.is_admin ? "true" : "false",
            "is_approved", userDict.is_approved ? "true" : "false",
            "created_at", userDict.created_at
        ];
        
        // Use HSET with multiple field-value pairs
        const command = "HSET/" + key + "/" + fields.join("/");
        const res = await ngx.fetch("/redis-internal/" + command);
        
        return res.ok;
    } catch (e) {
        return false;
    }
}

async function saveChat(chatId, userId, message, response) {
    try {
        const key = "chat:" + chatId;
        const timestamp = new Date().toISOString();
        
        const chatData = {
            id: chatId,
            user_id: userId,
            message: message,
            response: response,
            timestamp: timestamp
        };
        
        const fields = [
            "id", chatData.id,
            "user_id", chatData.user_id,
            "message", chatData.message,
            "response", chatData.response,
            "timestamp", chatData.timestamp
        ];
        
        const command = "HSET/" + key + "/" + fields.join("/");
        const res = await ngx.fetch("/redis-internal/" + command);
        
        return res.ok;
    } catch (e) {
        return false;
    }
}

async function getUserChats(userId) {
    try {
        // Get all chat keys for this user
        const keysRes = await ngx.fetch("/redis-internal/KEYS/chat:*");
        if (!keysRes.ok) {
            return [];
        }
        
        const keysText = await keysRes.text();
        if (!keysText || keysText.trim() === "") {
            return [];
        }
        
        const keys = keysText.trim().split('\n');
        const chats = [];
        
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            if (key && key.startsWith('chat:')) {
                const chatRes = await ngx.fetch("/redis-internal/HGETALL/" + key);
                if (chatRes.ok) {
                    const chatText = await chatRes.text();
                    if (chatText && chatText.trim() !== "") {
                        const lines = chatText.trim().split('\n');
                        const chatData = {};
                        
                        for (let j = 0; j < lines.length; j += 2) {
                            if (j + 1 < lines.length) {
                                chatData[lines[j]] = lines[j + 1];
                            }
                        }
                        
                        if (chatData.user_id === userId) {
                            chats.push(chatData);
                        }
                    }
                }
            }
        }
        
        // Sort by timestamp (newest first)
        chats.sort(function(a, b) {
            return new Date(b.timestamp) - new Date(a.timestamp);
        });
        
        return chats;
    } catch (e) {
        return [];
    }
}

function handleDatabaseRequest(r) {
    r.return(200, JSON.stringify({ 
        message: "Database endpoint", 
        available_functions: [
            "getUserById",
            "getUserByUsername", 
            "getAllUsers",
            "approveUser",
            "rejectUser",
            "saveUser",
            "saveChat",
            "getUserChats"
        ]
    }));
}

export default { 
    getUserById, 
    getUserByUsername,
    getAllUsers,
    approveUser, 
    rejectUser, 
    saveUser,
    saveChat,
    getUserChats,
    handleDatabaseRequest 
};