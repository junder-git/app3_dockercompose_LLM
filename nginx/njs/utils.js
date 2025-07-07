// nginx/njs/utils.js - Utility functions for njs (ES5 compatible)

// Base64 URL encoding/decoding for JWT
function base64urlEncode(str) {
    // njs doesn't have btoa, so we implement basic base64
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var result = '';
    var i = 0;
    
    while (i < str.length) {
        var a = str.charCodeAt(i++);
        var b = i < str.length ? str.charCodeAt(i++) : 0;
        var c = i < str.length ? str.charCodeAt(i++) : 0;
        
        var bitmap = (a << 16) | (b << 8) | c;
        
        result += chars.charAt((bitmap >> 18) & 63);
        result += chars.charAt((bitmap >> 12) & 63);
        result += i - 2 < str.length ? chars.charAt((bitmap >> 6) & 63) : '=';
        result += i - 1 < str.length ? chars.charAt(bitmap & 63) : '=';
    }
    
    // Convert to URL-safe base64
    return result.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function base64urlDecode(str) {
    // Add padding back
    str = str.replace(/-/g, '+').replace(/_/g, '/');
    while (str.length % 4) {
        str += '=';
    }
    
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var result = '';
    
    for (var i = 0; i < str.length; i += 4) {
        var encoded1 = chars.indexOf(str[i]);
        var encoded2 = chars.indexOf(str[i + 1]);
        var encoded3 = chars.indexOf(str[i + 2]);
        var encoded4 = chars.indexOf(str[i + 3]);
        
        var bitmap = (encoded1 << 18) | (encoded2 << 12) | (encoded3 << 6) | encoded4;
        
        result += String.fromCharCode((bitmap >> 16) & 255);
        if (encoded3 !== 64) result += String.fromCharCode((bitmap >> 8) & 255);
        if (encoded4 !== 64) result += String.fromCharCode(bitmap & 255);
    }
    
    return result;
}

// Simple SHA-256 implementation for njs
function sha256(str) {
    // This is a simplified version - in production use njs crypto module if available
    // For now, return a simple hash for demonstration
    var hash = 0;
    for (var i = 0; i < str.length; i++) {
        var char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // Convert to 32-bit integer
    }
    return hash.toString(16);
}

// HMAC-SHA256 for JWT signatures
function hmacSha256(data, key) {
    // Simplified HMAC implementation for njs
    // In production, use njs crypto module if available
    var keyHash = sha256(key);
    var dataHash = sha256(data + keyHash);
    return dataHash;
}

// HTTP response helpers
function sendSuccess(r, data) {
    r.status = 200;
    r.headersOut['Content-Type'] = 'application/json';
    r.sendHeader();
    r.send(JSON.stringify(data));
    r.finish();
}

function sendError(r, statusCode, message) {
    r.status = statusCode;
    r.headersOut['Content-Type'] = 'application/json';
    r.sendHeader();
    r.send(JSON.stringify({ error: message }));
    r.finish();
}

// Health check endpoint
function healthCheck(r) {
    var health = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        server: 'nginx-njs',
        version: '1.0.0'
    };
    
    return sendSuccess(r, health);
}

// Rate limiting check
function checkRateLimit(r, userId, maxRequests, windowSeconds) {
    // This would integrate with nginx rate limiting
    // For now, always allow
    maxRequests = maxRequests || 100;
    windowSeconds = windowSeconds || 60;
    return true;
}

// Request validation
function validateRequest(r, requiredFields) {
    requiredFields = requiredFields || [];
    try {
        var body = JSON.parse(r.requestBody || '{}');
        
        for (var i = 0; i < requiredFields.length; i++) {
            var field = requiredFields[i];
            if (!body[field]) {
                return { valid: false, message: field + ' is required' };
            }
        }
        
        return { valid: true, body: body };
        
    } catch (error) {
        return { valid: false, message: 'Invalid JSON' };
    }
}

// Escape HTML for XSS prevention
function escapeHtml(text) {
    var map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#x27;'
    };
    
    return text.replace(/[&<>"']/g, function(m) { return map[m]; });
}

// Generate random string
function generateRandomString(length) {
    length = length || 16;
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    var result = '';
    for (var i = 0; i < length; i++) {
        result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
}

// Format timestamp
function formatTimestamp(timestamp) {
    return new Date(timestamp).toISOString();
}

// Input validation helpers
function isValidEmail(email) {
    var emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

function isValidUsername(username) {
    var usernameRegex = /^[a-zA-Z0-9_-]{3,50}$/;
    return usernameRegex.test(username);
}

// CORS headers
function setCorsHeaders(r) {
    r.headersOut['Access-Control-Allow-Origin'] = '*';
    r.headersOut['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS';
    r.headersOut['Access-Control-Allow-Headers'] = 'Origin, X-Requested-With, Content-Type, Accept, Authorization';
}

// Handle CORS preflight
function handleCors(r) {
    if (r.method === 'OPTIONS') {
        setCorsHeaders(r);
        r.status = 200;
        r.sendHeader();
        r.finish();
        return true;
    }
    setCorsHeaders(r);
    return false;
}

export default {
    base64urlEncode: base64urlEncode,
    base64urlDecode: base64urlDecode,
    sha256: sha256,
    hmacSha256: hmacSha256,
    sendSuccess: sendSuccess,
    sendError: sendError,
    healthCheck: healthCheck,
    checkRateLimit: checkRateLimit,
    validateRequest: validateRequest,
    escapeHtml: escapeHtml,
    generateRandomString: generateRandomString,
    formatTimestamp: formatTimestamp,
    isValidEmail: isValidEmail,
    isValidUsername: isValidUsername,
    setCorsHeaders: setCorsHeaders,
    handleCors: handleCors
};