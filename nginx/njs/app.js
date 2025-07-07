// nginx/njs/app.js - Main application router with initialization (ES5 compatible)

import auth from './auth.js';
import init from './init.js';
import utils from './utils.js';

function handleRequest(r) {
    try {
        // Handle CORS
        if (utils.handleCors(r)) {
            return;
        }
        
        var uri = r.uri;
        var method = r.method;
        
        // Route requests
        if (uri.indexOf('/api/auth/') === 0) {
            return handleAuthRoute(r);
        } else if (uri === '/api/init' || uri === '/api/system/init') {
            return init.handleInitEndpoint(r);
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

function handleAuthRoute(r) {
    var path = r.uri.replace('/api/auth/', '');
    
    switch (path) {
        case 'login':
            return auth.handleLogin(r);
        case 'register':
            return auth.handleRegister(r);
        case 'verify':
            return auth.verifyTokenEndpoint(r);
        default:
            return utils.sendError(r, 404, 'Auth endpoint not found');
    }
}

export default {
    handleRequest: handleRequest
};