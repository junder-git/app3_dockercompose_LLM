# quart-app/blueprints/auth_middleware.py - Fixed authentication middleware
import os
from functools import wraps
from quart import request, jsonify, redirect, url_for, g
from quart_auth import current_user
from .database import get_current_user_data

# Rate limiting settings for different endpoint types
STRICT_ENDPOINTS = {
    '/login': {'rate': 10, 'burst': 3},
    '/register': {'rate': 5, 'burst': 2},
    '/logout': {'rate': 30, 'burst': 5},
    '/': {'rate': 30, 'burst': 10},
    '/health': {'rate': 60, 'burst': 20}
}

UNLIMITED_ENDPOINTS = {
    '/chat': {'rate': 10000, 'burst': 1000},
    '/admin': {'rate': 10000, 'burst': 1000}
}

def require_auth_for_chat(f):
    """Decorator to require authentication for chat endpoints"""
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        if not await current_user.is_authenticated:
            if request.is_json:
                return jsonify({'error': 'Authentication required', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        # Check if user is approved
        user_data = await get_current_user_data(current_user.auth_id)
        if not user_data or (not user_data.is_approved and not user_data.is_admin):
            if request.is_json:
                return jsonify({'error': 'Account not approved', 'redirect': '/login'}), 403
            return redirect(url_for('auth.login'))
        
        return await f(*args, **kwargs)
    return decorated_function

def require_admin(f):
    """Decorator to require admin privileges"""
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        if not await current_user.is_authenticated:
            if request.is_json:
                return jsonify({'error': 'Authentication required', 'redirect': '/login'}), 401
            return redirect(url_for('auth.login'))
        
        # Check if user is admin
        user_data = await get_current_user_data(current_user.auth_id)
        if not user_data or not user_data.is_admin:
            if request.is_json:
                return jsonify({'error': 'Admin privileges required'}), 403
            return redirect(url_for('auth.login'))
        
        return await f(*args, **kwargs)
    return decorated_function

def get_endpoint_rate_limits(endpoint_path):
    """Get rate limiting configuration for endpoint"""
    # Check if it's a chat endpoint
    if endpoint_path.startswith('/chat'):
        return UNLIMITED_ENDPOINTS['/chat']
    
    # Check if it's an admin endpoint
    if endpoint_path.startswith('/admin'):
        return UNLIMITED_ENDPOINTS['/admin']
    
    # Check strict endpoints
    for path, limits in STRICT_ENDPOINTS.items():
        if endpoint_path == path or endpoint_path.startswith(path + '/'):
            return limits
    
    # Default strict limits
    return STRICT_ENDPOINTS['/']

async def enforce_endpoint_access():
    """Middleware to enforce access controls - LESS RESTRICTIVE"""
    path = request.path
    
    # Allow health checks without authentication
    if path == '/health':
        return
    
    # Allow static files without authentication
    if path.startswith('/static/'):
        return
    
    # Allow auth routes without authentication (login, register, logout)
    if path.startswith('/login') or path.startswith('/register') or path.startswith('/logout'):
        return
    
    # Allow root path without authentication (it redirects appropriately)
    if path == '/':
        return
    
    # ONLY block chat and admin endpoints if user is not authenticated
    # But let the individual routes handle the authentication checks
    if path.startswith('/chat') or path.startswith('/admin'):
        # Don't block here - let the individual routes handle auth
        # This allows the routes to return proper error messages/redirects
        return
    
    # For all other paths, no restriction
    return

async def add_security_context():
    """Add security context to request"""
    g.endpoint_limits = get_endpoint_rate_limits(request.path)
    g.is_unlimited_endpoint = request.path.startswith('/chat') or request.path.startswith('/admin')
    g.is_strict_endpoint = not g.is_unlimited_endpoint  # Fixed typo here