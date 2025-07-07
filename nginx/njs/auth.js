// nginx/njs/auth.js - Server-side authentication using njs

import database from './database.js';
import utils from './utils.js';

// Configuration from environment (these would be set via nginx variables)
const config = {
    JWT_SECRET: process.env.JWT_SECRET || 'devstral-secret-2024',
    ADMIN_USERNAME: process.env.ADMIN_USERNAME || 'admin',
    ADMIN_PASSWORD: process.env.ADMIN_PASSWORD || 'admin',
    MAX_PENDING_USERS: parseInt(process.env.MAX_PENDING_USERS) || 2,
    MIN_USERNAME_LENGTH: 3,
    MAX_USERNAME_LENGTH: 50,
    MIN_PASSWORD_LENGTH: 6,
    RATE_LIMIT_MAX: 100
};

// Simple JWT implementation for njs
function createJWT(payload, secret) {
    const header = { alg: 'HS256', typ: 'JWT' };
    const headerB64 = utils.base64urlEncode(JSON.stringify(header));
    const payloadB64 = utils.base64urlEncode(JSON.stringify(payload));
    const signature = utils.hmacSha256(headerB64 + '.' + payloadB64, secret);
    const signatureB64 = utils.base64urlEncode(signature);
    return headerB64 + '.' + payloadB64 + '.' + signatureB64;
}

function verifyJWT(token, secret) {
    try {
        const parts = token.split('.');
        if (parts.length !== 3) return null;
        
        const [headerB64, payloadB64, signatureB64] = parts;
        const expectedSignature = utils.hmacSha256(headerB64 + '.' + payloadB64, secret);
        const expectedSignatureB64 = utils.base64urlEncode(expectedSignature);
        
        if (signatureB64 !== expectedSignatureB64) return null;
        
        const payload = JSON.parse(utils.base64urlDecode(payloadB64));
        
        // Check expiration
        if (payload.exp && Date.now() / 1000 > payload.exp) return null;
        
        return payload;
    } catch (error) {
        return null;
    }
}

async function hashPassword(password) {
    // Simple SHA-256 based password hashing for njs
    // In production, use a proper password hashing library
    const salt = 'devstral_salt_2024';
    return utils.sha256(password + salt);
}

async function verifyPassword(password, hash) {
    const computed = await hashPassword(password);
    return computed === hash;
}

function validateUsername(username) {
    if (!username || typeof username !== 'string') {
        return { valid: false, message: 'Username is required' };
    }
    
    if (username.length < config.MIN_USERNAME_LENGTH) {
        return { valid: false, message: `Username must be at least ${config.MIN_USERNAME_LENGTH} characters` };
    }
    
    if (username.length > config.MAX_USERNAME_LENGTH) {
        return { valid: false, message: `Username must be no more than ${config.MAX_USERNAME_LENGTH} characters` };
    }
    
    if (!/^[a-zA-Z0-9_-]+$/.test(username)) {
        return { valid: false, message: 'Username can only contain letters, numbers, underscore and dash' };
    }
    
    return { valid: true };
}

function validatePassword(password) {
    if (!password || typeof password !== 'string') {
        return { valid: false, message: 'Password is required' };
    }
    
    if (password.length < config.MIN_PASSWORD_LENGTH) {
        return { valid: false, message: `Password must be at least ${config.MIN_PASSWORD_LENGTH} characters` };
    }
    
    return { valid: true };
}

// Main handler functions for nginx locations
async function handleLogin(r) {
    try {
        if (r.method !== 'POST') {
            return utils.sendError(r, 405, 'Method not allowed');
        }
        
        let body;
        try {
            body = JSON.parse(r.requestBody);
        } catch (error) {
            return utils.sendError(r, 400, 'Invalid JSON');
        }
        
        const { username, password } = body;
        
        // Server-side validation
        const usernameValidation = validateUsername(username);
        if (!usernameValidation.valid) {
            return utils.sendError(r, 400, usernameValidation.message);
        }
        
        const passwordValidation = validatePassword(password);
        if (!passwordValidation.valid) {
            return utils.sendError(r, 400, passwordValidation.message);
        }
        
        // Get user from database
        const user = await database.getUserByUsername(username);
        if (!user) {
            return utils.sendError(r, 401, 'Invalid credentials');
        }
        
        // Verify password
        const isValidPassword = await verifyPassword(password, user.password_hash);
        if (!isValidPassword) {
            return utils.sendError(r, 401, 'Invalid credentials');
        }
        
        // Check if user is approved
        if (!user.is_admin && !user.is_approved) {
            return utils.sendError(r, 403, 'Account pending approval');
        }
        
        // Generate JWT token
        const payload = {
            userId: user.id,
            username: user.username,
            isAdmin: user.is_admin,
            isApproved: user.is_approved,
            exp: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours
        };
        
        const token = createJWT(payload, config.JWT_SECRET);
        
        return utils.sendSuccess(r, {
            success: true,
            token,
            user: {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin,
                is_approved: user.is_approved
            }
        });
        
    } catch (error) {
        r.error('Login error: ' + error.message);
        return utils.sendError(r, 500, 'Internal server error');
    }
}

async function handleRegister(r) {
    try {
        if (r.method !== 'POST') {
            return utils.sendError(r, 405, 'Method not allowed');
        }
        
        let body;
        try {
            body = JSON.parse(r.requestBody);
        } catch (error) {
            return utils.sendError(r, 400, 'Invalid JSON');
        }
        
        const { username, password } = body;
        
        // Server-side validation
        const usernameValidation = validateUsername(username);
        if (!usernameValidation.valid) {
            return utils.sendError(r, 400, usernameValidation.message);
        }
        
        const passwordValidation = validatePassword(password);
        if (!passwordValidation.valid) {
            return utils.sendError(r, 400, passwordValidation.message);
        }
        
        // Check pending user limit (SERVER-SIDE ENFORCEMENT)
        const pendingCount = await database.getPendingUsersCount();
        if (pendingCount >= config.MAX_PENDING_USERS) {
            return utils.sendError(r, 429, 'Registration temporarily closed');
        }
        
        // Check if username exists
        const existingUser = await database.getUserByUsername(username);
        if (existingUser) {
            return utils.sendError(r, 409, 'Username already exists');
        }
        
        // Hash password and create user
        const passwordHash = await hashPassword(password);
        const newUser = {
            id: null, // Will be auto-generated
            username: username,
            password_hash: passwordHash,
            is_admin: false,
            is_approved: false,
            created_at: new Date().toISOString()
        };
        
        await database.saveUser(newUser);
        
        return utils.sendSuccess(r, {
            success: true,
            message: 'Registration successful, pending approval'
        });
        
    } catch (error) {
        r.error('Registration error: ' + error.message);
        return utils.sendError(r, 500, 'Internal server error');
    }
}

function verifyToken(r) {
    try {
        const authHeader = r.headersIn.Authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            r.status = 401;
            return;
        }
        
        const token = authHeader.substring(7);
        const decoded = verifyJWT(token, config.JWT_SECRET);
        
        if (!decoded) {
            r.status = 401;
            return;
        }
        
        // Set headers for nginx
        r.headersOut['X-User-ID'] = decoded.userId;
        r.headersOut['X-Username'] = decoded.username;
        r.headersOut['X-Is-Admin'] = decoded.isAdmin.toString();
        r.headersOut['X-Is-Approved'] = decoded.isApproved.toString();
        
        r.status = 200;
        r.sendHeader();
        r.finish();
        
    } catch (error) {
        r.error('Token verification error: ' + error.message);
        r.status = 401;
    }
}

function verifyTokenEndpoint(r) {
    try {
        const authHeader = r.headersIn.Authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return utils.sendError(r, 401, 'No token provided');
        }
        
        const token = authHeader.substring(7);
        const decoded = verifyJWT(token, config.JWT_SECRET);
        
        if (!decoded) {
            return utils.sendError(r, 401, 'Invalid token');
        }
        
        return utils.sendSuccess(r, { valid: true, user: decoded });
        
    } catch (error) {
        r.error('Token endpoint error: ' + error.message);
        return utils.sendError(r, 500, 'Internal server error');
    }
}

async function handleAdminRequest(r) {
    // This would handle admin-specific endpoints
    // Implementation depends on the specific admin functionality needed
    return utils.sendError(r, 501, 'Admin endpoints not implemented yet');
}

// Configuration getters for nginx variables
function getAdminUsername() {
    return config.ADMIN_USERNAME;
}

function getMaxPendingUsers() {
    return config.MAX_PENDING_USERS.toString();
}

export default {
    handleLogin,
    handleRegister,
    verifyToken,
    verifyTokenEndpoint,
    handleAdminRequest,
    getAdminUsername,
    getMaxPendingUsers,
    hashPassword,
    verifyPassword
};