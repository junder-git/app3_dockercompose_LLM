// nginx/njs/auth.js - Server-side authentication using njs (ES5 compatible) - FIXED

import database from './database.js';
import utils from './utils.js';

// Configuration from environment (these would be set via nginx variables)
var config = {
    JWT_SECRET: process.env.JWT_SECRET || 'devstral-secret-2024',
    ADMIN_USERNAME: process.env.ADMIN_USERNAME || 'admin',
    ADMIN_PASSWORD: process.env.ADMIN_PASSWORD || 'admin',
    MAX_PENDING_USERS: parseInt(process.env.MAX_PENDING_USERS) || 2,
    MIN_USERNAME_LENGTH: 3,
    MAX_USERNAME_LENGTH: 14,
    MIN_PASSWORD_LENGTH: 5,
    RATE_LIMIT_MAX: 100
};

// Simple JWT implementation for njs
function createJWT(payload, secret) {
    var header = { alg: 'HS256', typ: 'JWT' };
    var headerB64 = utils.base64urlEncode(JSON.stringify(header));
    var payloadB64 = utils.base64urlEncode(JSON.stringify(payload));
    var signature = utils.hmacSha256(headerB64 + '.' + payloadB64, secret);
    var signatureB64 = utils.base64urlEncode(signature);
    return headerB64 + '.' + payloadB64 + '.' + signatureB64;
}

function verifyJWT(token, secret) {
    try {
        var parts = token.split('.');
        if (parts.length !== 3) return null;
        
        var headerB64 = parts[0];
        var payloadB64 = parts[1];
        var signatureB64 = parts[2];
        var expectedSignature = utils.hmacSha256(headerB64 + '.' + payloadB64, secret);
        var expectedSignatureB64 = utils.base64urlEncode(expectedSignature);
        
        if (signatureB64 !== expectedSignatureB64) return null;
        
        var payload = JSON.parse(utils.base64urlDecode(payloadB64));
        
        // Check expiration
        if (payload.exp && Date.now() / 1000 > payload.exp) return null;
        
        return payload;
    } catch (error) {
        return null;
    }
}

function hashPassword(password) {
    // Simple SHA-256 based password hashing for njs
    // In production, use a proper password hashing library
    var salt = 'devstral_salt_2024';
    return utils.sha256(password + salt);
}

function verifyPassword(password, hash) {
    var computed = hashPassword(password);
    return computed === hash;
}

function validateUsername(username) {
    if (!username || typeof username !== 'string') {
        return { valid: false, message: 'Username is required' };
    }
    
    if (username.length < config.MIN_USERNAME_LENGTH) {
        return { valid: false, message: 'Username must be at least ' + config.MIN_USERNAME_LENGTH + ' characters' };
    }
    
    if (username.length > config.MAX_USERNAME_LENGTH) {
        return { valid: false, message: 'Username must be no more than ' + config.MAX_USERNAME_LENGTH + ' characters' };
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
        return { valid: false, message: 'Password must be at least ' + config.MIN_PASSWORD_LENGTH + ' characters' };
    }
    
    return { valid: true };
}

// Helper function to read request body
function readRequestBody(r) {
    return new Promise(function(resolve, reject) {
        var body = '';
        
        // Check if request body is already available (synchronously)
        if (r.requestText) {
            resolve(r.requestText);
            return;
        }
        
        // For POST requests, we need to read the body
        if (r.method === 'POST') {
            try {
                // Try to get the body directly if available
                var directBody = r.requestBody || r.requestText || '';
                if (directBody) {
                    resolve(directBody);
                    return;
                }
                
                // If no direct access, try reading from variables
                var contentLength = parseInt(r.headersIn['Content-Length'] || '0', 10);
                if (contentLength === 0) {
                    resolve('{}');
                    return;
                }
                
                // Fallback: assume empty body
                resolve('{}');
                
            } catch (error) {
                r.error('Error reading request body: ' + error.message);
                reject(error);
            }
        } else {
            resolve('{}');
        }
    });
}

// Main handler functions for nginx locations
function handleLogin(r) {
    try {
        if (r.method !== 'POST') {
            return utils.sendError(r, 405, 'Method not allowed');
        }
        
        // Read request body
        readRequestBody(r).then(function(bodyText) {
            var body;
            try {
                body = JSON.parse(bodyText || '{}');
            } catch (error) {
                r.error('JSON parse error: ' + error.message + ', body: ' + bodyText);
                return utils.sendError(r, 400, 'Invalid JSON: ' + error.message);
            }
            
            var username = body.username;
            var password = body.password;
            
            // Server-side validation
            var usernameValidation = validateUsername(username);
            if (!usernameValidation.valid) {
                return utils.sendError(r, 400, usernameValidation.message);
            }
            
            var passwordValidation = validatePassword(password);
            if (!passwordValidation.valid) {
                return utils.sendError(r, 400, passwordValidation.message);
            }
            
            // Get user from database
            return database.getUserByUsername(username);
            
        }).then(function(user) {
            if (!user) {
                return utils.sendError(r, 401, 'Invalid credentials');
            }
            
            // Verify password
            var isValidPassword = verifyPassword(password, user.password_hash);
            if (!isValidPassword) {
                return utils.sendError(r, 401, 'Invalid credentials');
            }
            
            // Check if user is approved
            if (!user.is_admin && !user.is_approved) {
                return utils.sendError(r, 403, 'Account pending approval');
            }
            
            // Generate JWT token
            var payload = {
                userId: user.id,
                username: user.username,
                isAdmin: user.is_admin,
                isApproved: user.is_approved,
                exp: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours
            };
            
            var token = createJWT(payload, config.JWT_SECRET);
            
            return utils.sendSuccess(r, {
                success: true,
                token: token,
                user: {
                    id: user.id,
                    username: user.username,
                    is_admin: user.is_admin,
                    is_approved: user.is_approved
                }
            });
            
        }).catch(function(error) {
            r.error('Login error: ' + error.message);
            return utils.sendError(r, 500, 'Internal server error');
        });
        
    } catch (error) {
        r.error('Login handler error: ' + error.message);
        return utils.sendError(r, 500, 'Internal server error');
    }
}

function handleRegister(r) {
    try {
        if (r.method !== 'POST') {
            return utils.sendError(r, 405, 'Method not allowed');
        }
        
        // Read request body
        readRequestBody(r).then(function(bodyText) {
            var body;
            try {
                body = JSON.parse(bodyText || '{}');
            } catch (error) {
                r.error('JSON parse error: ' + error.message + ', body: ' + bodyText);
                return utils.sendError(r, 400, 'Invalid JSON: ' + error.message);
            }
            
            var username = body.username;
            var password = body.password;
            
            // Server-side validation
            var usernameValidation = validateUsername(username);
            if (!usernameValidation.valid) {
                return utils.sendError(r, 400, usernameValidation.message);
            }
            
            var passwordValidation = validatePassword(password);
            if (!passwordValidation.valid) {
                return utils.sendError(r, 400, passwordValidation.message);
            }
            
            // Check pending user limit (SERVER-SIDE ENFORCEMENT)
            return database.getPendingUsersCount();
            
        }).then(function(pendingCount) {
            if (pendingCount >= config.MAX_PENDING_USERS) {
                return utils.sendError(r, 429, 'Registration temporarily closed');
            }
            
            // Check if username exists
            return database.getUserByUsername(username);
            
        }).then(function(existingUser) {
            if (existingUser) {
                return utils.sendError(r, 409, 'Username already exists');
            }
            
            // Hash password and create user
            var passwordHash = hashPassword(password);
            var newUser = {
                id: null, // Will be auto-generated
                username: username,
                password_hash: passwordHash,
                is_admin: false,
                is_approved: false,
                created_at: new Date().toISOString()
            };
            
            return database.saveUser(newUser);
            
        }).then(function() {
            return utils.sendSuccess(r, {
                success: true,
                message: 'Registration successful, pending approval'
            });
            
        }).catch(function(error) {
            r.error('Registration error: ' + error.message);
            return utils.sendError(r, 500, 'Internal server error');
        });
        
    } catch (error) {
        r.error('Registration handler error: ' + error.message);
        return utils.sendError(r, 500, 'Internal server error');
    }
}

function verifyToken(r) {
    try {
        var authHeader = r.headersIn.Authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            r.status = 401;
            return;
        }
        
        var token = authHeader.substring(7);
        var decoded = verifyJWT(token, config.JWT_SECRET);
        
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
        var authHeader = r.headersIn.Authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return utils.sendError(r, 401, 'No token provided');
        }
        
        var token = authHeader.substring(7);
        var decoded = verifyJWT(token, config.JWT_SECRET);
        
        if (!decoded) {
            return utils.sendError(r, 401, 'Invalid token');
        }
        
        return utils.sendSuccess(r, { valid: true, user: decoded });
        
    } catch (error) {
        r.error('Token endpoint error: ' + error.message);
        return utils.sendError(r, 500, 'Internal server error');
    }
}

function handleAdminRequest(r) {
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
    handleLogin: handleLogin,
    handleRegister: handleRegister,
    verifyToken: verifyToken,
    verifyTokenEndpoint: verifyTokenEndpoint,
    handleAdminRequest: handleAdminRequest,
    getAdminUsername: getAdminUsername,
    getMaxPendingUsers: getMaxPendingUsers,
    hashPassword: hashPassword,
    verifyPassword: verifyPassword,
    readRequestBody: readRequestBody
};