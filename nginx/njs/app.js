// nginx/njs/app.js - Main application router with initialization

import auth from './auth.js';
import init from './init.js';
import utils from './utils.js';

async function handleRequest(r) {
    try {
        // Handle CORS
        if (utils.handleCors(r)) {
            return;
        }
        
        const uri = r.uri;
        const method = r.method;
        
        // Route requests
        if (uri.startsWith('/api/auth/')) {
            return await handleAuthRoute(r);
        } else if (uri === '/api/init' || uri === '/api/system/init') {
            return await init.handleInitEndpoint(r);
        } else if (uri === '/health') {
            return utils.healthCheck(r);
        } else {
            return utils.sendError(r, 404, 'Not found');
        }
        
    } catch (error) {
        r.error('Request handler error: ' + error.message);
        return utils.sendError(r, 500, 'Internal server error');
    }
}

async function handleAuthRoute(r) {
    const path = r.uri.replace('/api/auth/', '');
    
    switch (path) {
        case 'login':
            return await auth.handleLogin(r);
        case 'register':
            return await auth.handleRegister(r);
        case 'verify':
            return await auth.verifyTokenEndpoint(r);
        default:
            return utils.sendError(r, 404, 'Auth endpoint not found');
    }
}

export default {
    handleRequest
};