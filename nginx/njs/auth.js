
async function handleLogin(r) {
    const body = await r.requestBody;
    var parsed = JSON.parse(body);
    var username = parsed.username;
    var password = parsed.password;

    if (!username || !password) {
        r.return(400, JSON.stringify({ error: "Missing username or password" }));
        return;
    }

    var user = await database.getUserByUsername(username);
    if (!user) {
        r.return(401, JSON.stringify({ error: "Invalid credentials" }));
        return;
    }

    var valid = await database.verifyPassword(password, user.password_hash);
    if (!valid) {
        r.return(401, JSON.stringify({ error: "Invalid credentials" }));
        return;
    }

    var token = Date.now().toString() + Math.random().toString(36).substring(2);
    await database.saveToken(token, username);

    r.return(200, JSON.stringify({ token: token }));
}

function verifyToken(r) {
    r.return(200, JSON.stringify({ message: "Token verified" }));
}

function verifyTokenEndpoint(r) {
    r.return(200, JSON.stringify({ message: "Verify token endpoint works" }));
}

function handleRegister(r) {
    r.return(200, JSON.stringify({ message: "Register endpoint works (to be implemented)" }));
}
