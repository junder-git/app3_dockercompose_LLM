// nginx/njs/auth.js - Complete authentication system
import database from "./database.js";
import utils from "./utils.js";

function generateToken(user) {
    // Simple token generation - in production, use proper JWT
    const payload = {
        user_id: user.id,
        username: user.username,
        is_admin: user.is_admin,
        exp: Date.now() + (7 * 24 * 60 * 60 * 1000) // 7 days
    };
    return Buffer.from(JSON.stringify(payload)).toString('base64');
}

function verifyToken(token) {
    try {
        const payload = JSON.parse(Buffer.from(token, 'base64').toString());
        if (payload.exp < Date.now()) {
            return null; // Token expired
        }
        return payload;
    } catch (e) {
        return null; // Invalid token
    }
}

async function verifyRequest(r) {
    try {
        const authHeader = r.headersIn.Authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return { success: false, error: "No token provided" };
        }

        const token = authHeader.substring(7); // Remove 'Bearer '
        const payload = verifyToken(token);
        
        if (!payload) {
            return { success: false, error: "Invalid or expired token" };
        }

        // Verify user still exists and is approved
        const user = await database.getUserById(payload.user_id);
        if (!user) {
            return { success: false, error: "User not found" };
        }

        if (user.is_approved !== 'true' && user.is_approved !== true) {
            return { success: false, error: "Account not approved" };
        }

        return { 
            success: true, 
            user: {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true' || user.is_admin === true
            }
        };

    } catch (e) {
        return { success: false, error: "Authentication failed" };
    }
}

async function handleLogin(r) {
    try {
        if (r.method !== 'POST') {
            r.return(405, JSON.stringify({ error: 'Method not allowed' }));
            return;
        }

        const body = r.requestBody;
        if (!body) {
            r.return(400, JSON.stringify({ error: 'Request body required' }));
            return;
        }

        const data = JSON.parse(body);
        const { username, password } = data;

        // Validate input
        const [validUsername, userError] = utils.validateUsername(username);
        if (!validUsername) {
            r.return(400, JSON.stringify({ error: userError }));
            return;
        }

        const [validPassword, passError] = utils.validatePassword(password);
        if (!validPassword) {
            r.return(400, JSON.stringify({ error: passError }));
            return;
        }

        // Get user from database
        const user = await database.getUserByUsername(username);
        if (!user) {
            r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
            return;
        }

        // Check password (in production, use proper password hashing)
        if (user.password_hash !== password) {
            r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
            return;
        }

        // Check if user is approved
        if (user.is_approved !== 'true' && user.is_approved !== true) {
            r.return(403, JSON.stringify({ error: 'Account pending approval' }));
            return;
        }

        // Generate token
        const token = generateToken({
            id: user.id,
            username: user.username,
            is_admin: user.is_admin === 'true' || user.is_admin === true
        });

        // Return success response
        r.return(200, JSON.stringify({
            success: true,
            token: token,
            user: {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true' || user.is_admin === true
            }
        }));

    } catch (e) {
        r.log(`Auth error: ${e.message}`);
        r.return(500, JSON.stringify({ error: 'Internal server error' }));
    }
}

async function handleRegister(r) {
    try {
        if (r.method !== 'POST') {
            r.return(405, JSON.stringify({ error: 'Method not allowed' }));
            return;
        }

        const body = r.requestBody;
        if (!body) {
            r.return(400, JSON.stringify({ error: 'Request body required' }));
            return;
        }

        const data = JSON.parse(body);
        const { username, password } = data;

        // Validate input
        const [validUsername, userError] = utils.validateUsername(username);
        if (!validUsername) {
            r.return(400, JSON.stringify({ error: userError }));
            return;
        }

        const [validPassword, passError] = utils.validatePassword(password);
        if (!validPassword) {
            r.return(400, JSON.stringify({ error: passError }));
            return;
        }

        // Check if user already exists
        const existingUser = await database.getUserByUsername(username);
        if (existingUser) {
            r.return(409, JSON.stringify({ error: 'Username already exists' }));
            return;
        }

        // Create new user (pending approval)
        const newUser = {
            id: Date.now().toString(),
            username: username,
            password_hash: password, // In production, hash this properly
            is_admin: false,
            is_approved: false,
            created_at: new Date().toISOString()
        };

        const saved = await database.saveUser(newUser);
        if (!saved) {
            r.return(500, JSON.stringify({ error: 'Failed to create user' }));
            return;
        }

        r.return(201, JSON.stringify({
            success: true,
            message: 'User created successfully. Pending admin approval.',
            user: {
                id: newUser.id,
                username: newUser.username,
                is_approved: false
            }
        }));

    } catch (e) {
        r.log(`Register error: ${e.message}`);
        r.return(500, JSON.stringify({ error: 'Internal server error' }));
    }
}

async function verifyTokenEndpoint(r) {
    try {
        const authResult = await verifyRequest(r);
        
        if (!authResult.success) {
            r.return(401, JSON.stringify({ error: authResult.error }));
            return;
        }

        r.return(200, JSON.stringify({
            success: true,
            user: authResult.user
        }));

    } catch (e) {
        r.log(`Token verification error: ${e.message}`);
        r.return(500, JSON.stringify({ error: 'Token verification failed' }));
    }
}

export default { 
    generateToken, 
    verifyToken,
    verifyRequest,
    handleLogin, 
    handleRegister,
    verifyTokenEndpoint
};