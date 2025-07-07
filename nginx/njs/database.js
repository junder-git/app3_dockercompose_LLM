async function getUserById(user_id) {
    var key = "user:" + user_id;
    var res = await ngx.fetch("/redis-internal/hgetall/" + key);
    if (!res.ok) {
        return null;
    }
    var user_data = await res.json();
    if (!user_data || !user_data.id) {
        return null;
    }
    return user_data;
}

async function getUserByUsername(username) {
    var key = "user:" + username;
    var res = await ngx.fetch("/redis-internal/hgetall/" + key);
    if (!res.ok) {
        return null;
    }
    var user_data = await res.json();
    if (!user_data || !user_data.username) {
        return null;
    }
    return user_data;
}

async function approveUser(user_id) {
    var key = "user:" + user_id;
    var existsRes = await ngx.fetch("/redis-internal/exists/" + key);
    if (!existsRes.ok || (await existsRes.text()) !== "1") {
        return false;
    }

    var setRes = await ngx.fetch("/redis-internal/hset/" + key + "/is_approved/true");
    return setRes.ok;
}

async function rejectUser(user_id) {
    var key = "user:" + user_id;
    var existsRes = await ngx.fetch("/redis-internal/exists/" + key);
    if (!existsRes.ok || (await existsRes.text()) !== "1") {
        return false;
    }

    var delRes = await ngx.fetch("/redis-internal/del/" + key);
    return delRes.ok;
}

async function saveUser(userDict) {
    var key = "user:" + userDict.username;
    var fields = [
        "id", userDict.id,
        "username", userDict.username,
        "password_hash", userDict.password_hash,
        "is_admin", userDict.is_admin ? "true" : "false",
        "is_approved", userDict.is_approved ? "true" : "false",
        "created_at", userDict.created_at
    ];
    var query = fields.join("/");
    var res = await ngx.fetch("/redis-internal/hset/" + key + "/" + query);
    return res.ok;
}

function handleDatabaseRequest(r) {
    r.return(200, JSON.stringify({ message: "Database endpoint placeholder" }));
}

export default { 
    getUserById, 
    getUserByUsername,
    approveUser, 
    rejectUser, 
    saveUser, 
    handleDatabaseRequest 
};
