// nginx/njs/database.js - Updated with better Redis debugging
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
            if (key && key.indexOf('user:') === 0) {
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
        
        console.log('DEBUG: Saving user with key:', key);
        console.log('DEBUG: User data:', JSON.stringify(userDict));
        
        // Test Redis connection first
        var pingRes = await ngx.fetch("/redis-internal/PING");
        console.log('DEBUG: Redis PING response status:', pingRes.status);
        if (!pingRes.ok) {
            console.log('DEBUG: Redis ping failed');
            return false;
        }
        
        var pingText = await pingRes.text();
        console.log('DEBUG: Redis PING response:', pingText);
        
        // Try a simple SET first to test
        var testKey = "test:" + Date.now();
        var testRes = await ngx.fetch("/redis-internal/SET/" + testKey + "/testvalue");
        console.log('DEBUG: Test SET response status:', testRes.status);
        
        if (!testRes.ok) {
            console.log('DEBUG: Test SET failed');
            return false;
        }
        
        // Clean up test key
        await ngx.fetch("/redis-internal/DEL/" + testKey);
        
        // Build HSET command with all fields - try a different approach
        // Use HMSET instead of HSET for multiple fields
        var fields = [
            "id", userDict.id,
            "username", userDict.username,
            "password_hash", userDict.password_hash,
            "is_admin", userDict.is_admin ? "true" : "false",
            "is_approved", userDict.is_approved ? "true" : "false",
            "created_at", userDict.created_at
        ];
        
        console.log('DEBUG: Fields array:', JSON.stringify(fields));
        
        // Try HMSET command
        var command = "HMSET/" + key;
        for (var i = 0; i < fields.length; i += 2) {
            command += "/" + encodeURIComponent(fields[i]) + "/" + encodeURIComponent(fields[i + 1]);
        }
        
        console.log('DEBUG: Redis command:', command);
        
        var res = await ngx.fetch("/redis-internal/" + command);
        console.log('DEBUG: HMSET response status:', res.status);
        
        if (res.ok) {
            var responseText = await res.text();
            console.log('DEBUG: HMSET response text:', responseText);
            
            // Verify the user was saved by trying to read it back
            var verifyRes = await ngx.fetch("/redis-internal/HGETALL/" + key);
            if (verifyRes.ok) {
                var verifyText = await verifyRes.text();
                console.log('DEBUG: Verification read:', verifyText);
            }
        }
        
        return res.ok;
    } catch (e) {
        console.log('DEBUG: Save user error:', e.message);
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
        
        var command = "HSET/" + key;
        for (var i = 0; i < fields.length; i += 2) {
            command += "/" + encodeURIComponent(fields[i]) + "/" + encodeURIComponent(fields[i + 1]);
        }
        
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
            if (key && key.indexOf('chat:') === 0) {
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