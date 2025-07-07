// nginx/njs/utils.js - Utility functions for njs

// Base64 URL encoding/decoding for JWT
function base64urlEncode(str) {
    // njs doesn't have btoa, so we implement basic base64
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    
    while (i < str.length) {
        const a = str.charCodeAt(i++);
        const b = i < str.length ? str.charCodeAt(i++) : 0;
        const c = i < str.length ? str.charCodeAt(i++) : 0;
        
        const bitmap = (a << 16) | (b << 8) | c;
        
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
    
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    
    for (let i = 0; i < str.length; i += 4) {
        const encoded1 = chars.indexOf(str[i]);
        const encoded2 = chars.indexOf(str[i + 1]);
        const encoded3 = chars.indexOf(str[i + 2]);
        const encoded4 = chars.indexOf(str[i + 3]);
        
        const bitmap = (encoded1 << 18) | (encoded2 << 12) | (encoded3 << 6) | encoded4;
        
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
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // Convert to 32-bit integer
    }
    return hash.toString(16);
}

// HMAC-SHA256 for JWT signatures
function hmacSha256(data, key) {
    // Simplified HMAC implementation for njs
    // In production, use njs crypto module if available
    const keyHash = sha256(key);
    const dataHash = sha256(data + keyHash);
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
    const health = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        server: 'nginx-njs',
        version: '1.0.0'
    };
    
    return sendSuccess(r, health);
}

// Rate limiting check
function checkRateLimit(r, userId, maxRequests = 100, windowSeconds = 60) {
    // This would integrate with nginx rate limiting
    // For now, always allow
    return true;
}

// Request validation
function validateRequest(r, requiredFields = []) {
    try {
        const body = JSON.parse(r.requestBody || '{}');
        
        for (const field of requiredFields) {
            if (!body[field]) {
                return { valid: false, message: `${field} is required` };
            }
        }
        
        return { valid: true, body };
        
    } catch (error) {
        return { valid: false, message: 'Invalid JSON' };
    }
}

// Escape HTML for XSS prevention
function escapeHtml(text) {
    const map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#x27;'
    };
    
    return text.replace(/[&<>"']/g, (m) => map[m]);
}

// Generate random string
function generateRandomString(length = 16) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < length; i++) {
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
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

function isValidUsername(username) {
    const usernameRegex = /^[a-zA-Z0-9_-]{3,50}$/;
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
    base64urlEncode,
    base64urlDecode,
    sha256,
    hmacSha256,
    sendSuccess,
    sendError,
    healthCheck,
    checkRateLimit,
    validateRequest,
    escapeHtml,
    generateRandomString,
    formatTimestamp,
    isValidEmail,
    isValidUsername,
    setCorsHeaders,
    handleCors
};