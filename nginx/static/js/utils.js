// nginx/static/js/utils.js - Simple client utilities
class Utils {
    static showFlashMessage(message, type = 'info', duration = 5000) {
        const alertClass = {
            'success': 'alert-success',
            'error': 'alert-danger', 
            'warning': 'alert-warning',
            'info': 'alert-info'
        }[type] || 'alert-info';

        const alert = $(`
            <div class="alert ${alertClass} alert-dismissible fade show" role="alert">
                ${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        `);

        $('#flash-messages').append(alert);
        if (duration > 0) setTimeout(() => alert.alert('close'), duration);
    }

    static showLoadingSpinner(selector, text = 'Loading...') {
        $(selector).prop('disabled', true).html(`<span class="spinner-border spinner-border-sm me-2"></span>${text}`);
    }

    static hideLoadingSpinner(selector, originalText = 'Submit') {
        $(selector).prop('disabled', false).html(originalText);
    }
}
window.Utils = Utils;

// nginx/static/js/auth.js - Simple auth handling
class AuthModule {
    constructor() {
        this.currentUser = null;
        this.token = localStorage.getItem('devstral_token');
    }

    async login(username, password) {
        try {
            const response = await fetch('/api/auth/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username, password })
            });

            const result = await response.json();
            
            if (response.ok && result.success) {
                this.token = result.token;
                this.currentUser = result.user;
                localStorage.setItem('devstral_token', this.token);
                return { success: true };
            } else {
                throw new Error(result.error || 'Login failed');
            }
        } catch (error) {
            return { success: false, message: error.message };
        }
    }

    async register(username, password) {
        try {
            const response = await fetch('/api/auth/register', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ username, password })
            });

            const result = await response.json();
            
            if (response.ok && result.success) {
                return { success: true, message: result.message };
            } else {
                throw new Error(result.error || 'Registration failed');
            }
        } catch (error) {
            return { success: false, message: error.message };
        }
    }

    async getCurrentUser() {
        if (!this.token) return null;
        
        try {
            const response = await fetch('/api/auth/verify', {
                headers: { 'Authorization': `Bearer ${this.token}` }
            });

            if (response.ok) {
                const result = await response.json();
                this.currentUser = result.user;
                return this.currentUser;
            } else {
                this.logout();
                return null;
            }
        } catch (error) {
            this.logout();
            return null;
        }
    }

    logout() {
        this.token = null;
        this.currentUser = null;
        localStorage.removeItem('devstral_token');
        window.location.href = '/';
    }
}

// nginx/static/js/app.js - Simple app router
class DevstralApp {
    constructor() {
        this.modules = {
            auth: new AuthModule()
        };
    }

    async init() {
        console.log('🚀 Initializing Devstral App');
        
        // Check authentication state
        const user = await this.modules.auth.getCurrentUser();
        
        // Update navbar
        this.updateNavbar(user);
        
        // Route to appropriate page
        this.handleRouting(user);
        
        // Hide loading indicator
        $('#loading-indicator').hide();
    }

    updateNavbar(user) {
        const navItems = user ? 
            `<a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Chat</a>
             ${user.is_admin ? '<a class="nav-link" href="/admin"><i class="bi bi-shield-lock"></i> Admin</a>' : ''}
             <a class="nav-link" href="#" onclick="window.DevstralApp.modules.auth.logout()"><i class="bi bi-box-arrow-right"></i> Logout</a>` :
            `<a class="nav-link" href="/login"><i class="bi bi-box-arrow-in-right"></i> Login</a>
             <a class="nav-link" href="/register"><i class="bi bi-person-plus"></i> Register</a>`;
        
        $('#nav-links, #navbar-items').html(navItems);
    }

    handleRouting(user) {
        const path = window.location.pathname;
        
        // Protected routes
        if (['/chat', '/admin'].includes(path) && !user) {
            window.location.href = '/login';
            return;
        }
        
        // Admin-only routes
        if (path === '/admin' && (!user || !user.is_admin)) {
            window.location.href = '/';
            return;
        }
        
        // Already logged in, redirect from auth pages
        if (['/login', '/register'].includes(path) && user) {
            window.location.href = '/chat';
            return;
        }
    }

    navigate(path) {
        window.location.href = `/${path}`;
    }

    showError(title, message) {
        Utils.showFlashMessage(`${title}: ${message}`, 'error');
    }

    showFlashMessage(message, type, duration) {
        Utils.showFlashMessage(message, type, duration);
    }
}

// Initialize global app instance
window.DevstralApp = new DevstralApp();

// nginx/static/js/models.js - Simple data models
class User {
    constructor(id = null, username = null, passwordHash = null, isAdmin = false, isApproved = false, createdAt = null) {
        this.id = id;
        this.username = username;
        this.password_hash = passwordHash;
        this.is_admin = isAdmin;
        this.is_approved = isApproved;
        this.created_at = createdAt || new Date().toISOString();
    }
}

class ChatSession {
    constructor(id = null, userId = null, title = null, createdAt = null, updatedAt = null) {
        this.id = id;
        this.user_id = userId;
        this.title = title || `Chat ${new Date().toLocaleString()}`;
        this.created_at = createdAt || new Date().toISOString();
        this.updated_at = updatedAt || new Date().toISOString();
    }
}

window.User = User;
window.ChatSession = ChatSession;