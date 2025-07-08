// nginx/njs/auth.js - Fixed for new endpoint structure
import utils from "./utils.js";

function generateToken(user) {
    var payload = {
        user_id: user.id,
        username: user.username,
        is_admin: user.is_admin,
        exp: Date.now() + (7 * 24 * 60 * 60 * 1000) // 7 days
    };
    return Buffer.from(JSON.stringify(payload)).toString('base64');
}

function verifyToken(token) {
    try {
        var payload = JSON.parse(Buffer.from(token, 'base64').toString());
        if (payload.exp < Date.now()) {
            return null;
        }
        return payload;
    } catch (e) {
        return null;
    }
}

async function verifyRequest(r) {
    try {
        var authHeader = r.headersIn.Authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return { success: false, error: "No token provided" };
        }

        var token = authHeader.substring(7);
        var payload = verifyToken(token);
        
        if (!payload) {
            return { success: false, error: "Invalid or expired token" };
        }

        // Use Redis direct access instead of database.js
        var userRes = await ngx.fetch("/redis/hgetall?key=user:" + payload.user_id, {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        if (!userRes.ok) {
            return { success: false, error: "User not found" };
        }
        
        var userData = await userRes.json();
        if (!userData.success || !userData.data.id) {
            return { success: false, error: "User not found" };
        }
        
        var user = userData.data;
        if (user.is_approved !== 'true') {
            return { success: false, error: "Account not approved" };
        }

        return { 
            success: true, 
            user: {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true'
            }
        };

    } catch (e) {
        return { success: false, error: "Authentication failed" };
    }
}

async function handleAuthRequest(r) {
    try {
        var path = r.uri.replace('/api/auth/', '');
        var method = r.method;

        if (path === 'login' && method === 'POST') {
            await handleLogin(r);
        } else if (path === 'register' && method === 'POST') {
            await handleRegister(r);
        } else if (path === 'verify' && method === 'GET') {
            await verifyTokenEndpoint(r);
        } else {
            r.return(404, JSON.stringify({ error: "Auth endpoint not found" }));
        }
    } catch (e) {
        r.log('Auth error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Internal server error" }));
    }
}

async function handleLogin(r) {
    try {
        if (r.method !== 'POST') {
            r.return(405, JSON.stringify({ error: 'Method not allowed' }));
            return;
        }

        var body = r.requestBody;
        if (!body) {
            r.return(400, JSON.stringify({ error: 'Request body required' }));
            return;
        }

        var data = JSON.parse(body);
        var username = data.username;
        var password = data.password;

        // Validate input
        var usernameValidation = utils.validateUsername(username);
        if (!usernameValidation[0]) {
            r.return(400, JSON.stringify({ error: usernameValidation[1] }));
            return;
        }

        var passwordValidation = utils.validatePassword(password);
        if (!passwordValidation[0]) {
            r.return(400, JSON.stringify({ error: passwordValidation[1] }));
            return;
        }

        // Get user from Redis
        var userRes = await ngx.fetch("/redis/hgetall?key=user:" + username, {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        if (!userRes.ok) {
            r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
            return;
        }
        
        var userData = await userRes.json();
        if (!userData.success || !userData.data.username) {
            r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
            return;
        }
        
        var user = userData.data;

        // Check password
        if (user.password_hash !== password) {
            r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
            return;
        }

        // Check if user is approved
        if (user.is_approved !== 'true') {
            r.return(403, JSON.stringify({ error: 'Account pending approval' }));
            return;
        }

        // Generate token
        var token = generateToken({
            id: user.id,
            username: user.username,
            is_admin: user.is_admin === 'true'
        });

        r.return(200, JSON.stringify({
            success: true,
            token: token,
            user: {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true'
            }
        }));

    } catch (e) {
        r.log('Login error: ' + e.message);
        r.return(500, JSON.stringify({ error: 'Internal server error' }));
    }
}

async function handleRegister(r) {
    try {
        if (r.method !== 'POST') {
            r.return(405, JSON.stringify({ error: 'Method not allowed' }));
            return;
        }

        var body = r.requestBody;
        if (!body) {
            r.return(400, JSON.stringify({ error: 'Request body required' }));
            return;
        }

        var data = JSON.parse(body);
        var username = data.username;
        var password = data.password;

        // Validate input
        var usernameValidation = utils.validateUsername(username);
        if (!usernameValidation[0]) {
            r.return(400, JSON.stringify({ error: usernameValidation[1] }));
            return;
        }

        var passwordValidation = utils.validatePassword(password);
        if (!passwordValidation[0]) {
            r.return(400, JSON.stringify({ error: passwordValidation[1] }));
            return;
        }

        // Check if user already exists
        var existingUserRes = await ngx.fetch("/redis/hgetall?key=user:" + username, {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        if (existingUserRes.ok) {
            var existingData = await existingUserRes.json();
            if (existingData.success && existingData.data.username) {
                r.return(409, JSON.stringify({ error: 'Username already exists' }));
                return;
            }
        }

        // Create new user
        var userId = Date.now().toString();
        var createUserRes = await ngx.fetch("/redis/hset", {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': 'Bearer internal'
            },
            body: JSON.stringify({
                key: "user:" + username,
                field: "id",
                value: userId
            })
        });

        if (!createUserRes.ok) {
            r.return(500, JSON.stringify({ error: 'Failed to create user' }));
            return;
        }

        // Set user data
        var fields = [
            ['username', username],
            ['password_hash', password],
            ['is_admin', 'false'],
            ['is_approved', 'false'],
            ['created_at', new Date().toISOString()]
        ];

        for (var i = 0; i < fields.length; i++) {
            await ngx.fetch("/redis/hset", {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer internal'
                },
                body: JSON.stringify({
                    key: "user:" + username,
                    field: fields[i][0],
                    value: fields[i][1]
                })
            });
        }

        r.return(201, JSON.stringify({
            success: true,
            message: 'User created successfully. Pending admin approval.',
            user: {
                id: userId,
                username: username,
                is_approved: false
            }
        }));

    } catch (e) {
        r.log('Register error: ' + e.message);
        r.return(500, JSON.stringify({ error: 'Internal server error' }));
    }
}

async function verifyTokenEndpoint(r) {
    try {
        var authResult = await verifyRequest(r);
        
        if (!authResult.success) {
            r.return(401, JSON.stringify({ error: authResult.error }));
            return;
        }

        r.return(200, JSON.stringify({
            success: true,
            user: authResult.user
        }));

    } catch (e) {
        r.log('Token verification error: ' + e.message);
        r.return(500, JSON.stringify({ error: 'Token verification failed' }));
    }
}

export default { 
    generateToken, 
    verifyToken,
    verifyRequest,
    handleAuthRequest,
    handleLogin, 
    handleRegister,
    verifyTokenEndpoint
};