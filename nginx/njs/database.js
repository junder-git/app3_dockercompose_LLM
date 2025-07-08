// nginx/njs/database.js - Updated Redis communication
async function getUserById(user_id) {
    try {
        var key = "user:" + user_id;
        var res = await ngx.fetch("/redis-internal/HGETALL/" + key);
        
        if (!res.ok) {
            return null;
        }
        
        var text = await res.text();
        if (!text || text.trim() === "") {
            return null;
        }
        
        // Parse Redis HGETALL response (field1\nvalue1\nfield2\nvalue2...)
        var lines = text.trim().split('\n');
        var user_data = {};
        
        for (var i = 0; i < lines.length; i += 2) {
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
        var key = "user:" + username;
        var res = await ngx.fetch("/redis-internal/HGETALL/" + key);
        
        if (!res.ok) {
            return null;
        }
        
        var text = await res.text();
        if (!text || text.trim() === "") {
            return null;
        }
        
        // Parse Redis HGETALL response
        var lines = text.trim().split('\n');
        var user_data = {};
        
        for (var i = 0; i < lines.length; i += 2) {
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
        var keysRes = await ngx.fetch("/redis-internal/KEYS/user:*");
        if (!keysRes.ok) {
            return [];
        }
        
        var keysText = await keysRes.text();
        if (!keysText || keysText.trim() === "") {
            return [];
        }
        
        var keys = keysText.trim().split('\n');
        var users = [];
        
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            if (key && key.startsWith('user:')) {
                var userData = await getUserByUsername(key.substring(5)); // Remove 'user:' prefix
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
        var key = "user:" + user_id;
        
        // Check if user exists
        var existsRes = await ngx.fetch("/redis-internal/EXISTS/" + key);
        if (!existsRes.ok) {
            return false;
        }
        
        var exists = await existsRes.text();
        if (exists.trim() !== "1") {
            return false;
        }
        
        // Set is_approved to true
        var setRes = await ngx.fetch("/redis-internal/HSET/" + key + "/is_approved/true");
        return setRes.ok;
    } catch (e) {
        return false;
    }
}

async function rejectUser(user_id) {
    try {
        var key = "user:" + user_id;
        
        // Check if user exists
        var existsRes = await ngx.fetch("/redis-internal/EXISTS/" + key);
        if (!existsRes.ok) {
            return false;
        }
        
        var exists = await existsRes.text();
        if (exists.trim() !== "1") {
            return false;
        }
        
        // Delete the user
        var delRes = await ngx.fetch("/redis-internal/DEL/" + key);
        return delRes.ok;
    } catch (e) {
        return false;
    }
}

async function saveUser(userDict) {
    try {
        var key = "user:" + userDict.username;
        
        // Debug logging
        console.log('DEBUG: Attempting to save user');
        console.log('DEBUG: Key:', key);
        console.log('DEBUG: User data:', JSON.stringify(userDict));
        
        // Build HSET command with all fields
        var fields = [
            "id", userDict.id,
            "username", userDict.username,
            "password_hash", userDict.password_hash,
            "is_admin", userDict.is_admin ? "true" : "false",
            "is_approved", userDict.is_approved ? "true" : "false",
            "created_at", userDict.created_at
        ];
        
        console.log('DEBUG: Fields array:', JSON.stringify(fields));
        
        // Use HSET with multiple field-value pairs
        var command = "HSET/" + key + "/" + fields.join("/");
        console.log('DEBUG: Redis command:', command);
        
        var res = await ngx.fetch("/redis-internal/" + command);
        console.log('DEBUG: Redis response status:', res.status);
        console.log('DEBUG: Redis response ok:', res.ok);
        
        if (res.ok) {
            var responseText = await res.text();
            console.log('DEBUG: Redis response text:', responseText);
        } else {
            console.log('DEBUG: Redis request failed');
        }
        
        return res.ok;
    } catch (e) {
        console.log('DEBUG: saveUser error:', e.message);
        return false;
    }
}

async function saveChat(chatId, userId, message, response) {
    try {
        var key = "chat:" + chatId;
        var timestamp = new Date().toISOString();
        
        var chatData = {
            id: chatId,
            user_id: userId,
            message: message,
            response: response,
            timestamp: timestamp
        };
        
        var fields = [
            "id", chatData.id,
            "user_id", chatData.user_id,
            "message", chatData.message,
            "response", chatData.response,
            "timestamp", chatData.timestamp
        ];
        
        var command = "HSET/" + key + "/" + fields.join("/");
        var res = await ngx.fetch("/redis-internal/" + command);
        
        return res.ok;
    } catch (e) {
        return false;
    }
}

async function getUserChats(userId) {
    try {
        // Get all chat keys for this user
        var keysRes = await ngx.fetch("/redis-internal/KEYS/chat:*");
        if (!keysRes.ok) {
            return [];
        }
        
        var keysText = await keysRes.text();
        if (!keysText || keysText.trim() === "") {
            return [];
        }
        
        var keys = keysText.trim().split('\n');
        var chats = [];
        
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            if (key && key.startsWith('chat:')) {
                var chatRes = await ngx.fetch("/redis-internal/HGETALL/" + key);
                if (chatRes.ok) {
                    var chatText = await chatRes.text();
                    if (chatText && chatText.trim() !== "") {
                        var lines = chatText.trim().split('\n');
                        var chatData = {};
                        
                        for (var j = 0; j < lines.length; j += 2) {
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