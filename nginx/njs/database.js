
async function getUserByUsername(username) {
    var key = "user:" + username;
    var res = await ngx.fetch("/redis-internal/hgetall/" + key);
    if (res.ok) {
        var data = await res.json();
        if (data && data.username) {
            return data;
        }
    }
    return null;
}

async function verifyPassword(inputPassword, storedHash) {
    return inputPassword === storedHash;
}

async function saveUser(user) {
    var key = "user:" + user.username;
    var fields = [
        "id", user.id,
        "username", user.username,
        "password_hash", user.password_hash,
        "is_admin", user.is_admin ? "true" : "false"
    ];
    var query = fields.join("/");
    var res = await ngx.fetch("/redis-internal/hset/" + key + "/" + query);
    return res.ok;
}

async function saveToken(token, username) {
    var res = await ngx.fetch("/redis-internal/setex/token:" + token + "/3600/" + username);
    return res.ok;
}
