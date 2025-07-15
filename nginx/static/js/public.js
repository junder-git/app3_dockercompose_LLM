// =============================================================================
// nginx/static/js/public.js - PUBLIC/UNAUTHENTICATED USERS + GLOBAL FUNCTIONS
// =============================================================================

// Public page functionality (login, register, index)
class PublicInterface {
    constructor() {
        this.init();
    }

    init() {
        this.setupPublicFeatures();
        console.log('🌐 Public interface initialized');
    }

    setupPublicFeatures() {
        // Setup login/register forms
        this.setupAuthForms();
        this.setupGuestSessionStart();
        this.setupPasswordToggle();
    }

    setupAuthForms() {
        // Handle login form
        const loginForm = document.getElementById('login-form');
        if (loginForm) {
            loginForm.addEventListener('submit', this.handleLogin.bind(this));
        }

        // Handle register form
        const registerForm = document.getElementById('register-form');
        if (registerForm) {
            registerForm.addEventListener('submit', this.handleRegister.bind(this));
        }
    }

    setupPasswordToggle() {
        // Password visibility toggle
        const togglePassword = document.getElementById('toggle-password');
        if (togglePassword) {
            togglePassword.addEventListener('click', function() {
                const passwordInput = document.getElementById('password');
                const icon = this.querySelector('i');
                
                if (passwordInput.type === 'password') {
                    passwordInput.type = 'text';
                    icon.classList.remove('bi-eye');
                    icon.classList.add('bi-eye-slash');
                } else {
                    passwordInput.type = 'password';
                    icon.classList.remove('bi-eye-slash');
                    icon.classList.add('bi-eye');
                }
            });
        }
    }

    setupGuestSessionStart() {
        // Setup guest session creation
        const guestButtons = document.querySelectorAll('[onclick*="startGuestSession"]');
        guestButtons.forEach(button => {
            button.addEventListener('click', this.startGuestSession.bind(this));
        });
    }

    async handleLogin(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        const credentials = {
            username: formData.get('username'),
            password: formData.get('password')
        };

        const loginBtn = document.getElementById('login-btn');
        if (loginBtn) {
            loginBtn.disabled = true;
            loginBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Signing in...';
        }

        try {
            const response = await fetch('/api/auth/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify(credentials)
            });

            const data = await response.json();
            
            if (data.success) {
                this.showSuccess('Login successful! Redirecting...');
                setTimeout(() => {
                    window.location.href = data.redirect || '/chat';
                }, 1000);
            } else {
                this.showError(data.error || 'Login failed');
            }
        } catch (error) {
            this.showError('Login error: ' + error.message);
        } finally {
            if (loginBtn) {
                loginBtn.disabled = false;
                loginBtn.innerHTML = '<i class="bi bi-box-arrow-in-right"></i> Sign In';
            }
        }
    }
    async logout(e) {
    // Call backend to clear cookies
    e.preventDefault();
    fetch('/api/auth/logout', { method: 'POST', credentials: 'include' })
        .then(res => res.json())
        .then(() => {
            // Clear all storage
            localStorage.clear();
            sessionStorage.clear();

            // Remove all cookies forcibly
            document.cookie.split(";").forEach(function(c) {
                document.cookie = c
                    .replace(/^ +/, "")
                    .replace(/=.*/, "=;expires=" + new Date().toUTCString() + ";path=/");
            });

            // Finally, force reload to ensure nav refresh and backend state
            location.href = "/";
        })
        .catch(() => {
            // Even on error, fallback reload
            location.href = "/";
        });
    }

    async handleRegister(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        const userData = {
            username: formData.get('username'),
            password: formData.get('password')
        };

        const registerBtn = document.getElementById('register-btn');
        if (registerBtn) {
            registerBtn.disabled = true;
            registerBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Creating account...';
        }

        try {
            const response = await fetch('/api/register', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(userData)
            });

            const data = await response.json();
            
            if (data.success) {
                this.showSuccess('Registration successful! Please wait for approval.');
                setTimeout(() => {
                    window.location.href = '/login';
                }, 2000);
            } else {
                this.showError(data.error || 'Registration failed');
            }
        } catch (error) {
            this.showError('Registration error: ' + error.message);
        } finally {
            if (registerBtn) {
                registerBtn.disabled = false;
                registerBtn.innerHTML = '<i class="bi bi-person-plus"></i> Create Account';
            }
        }
    }

    async startGuestSession() {
        try {
            const response = await fetch('/api/guest/create-session', {
                method: 'POST',
                credentials: 'include'
            });

            const data = await response.json();
            
            if (data.success) {
                this.showSuccess('Guest session created! Redirecting...');
                setTimeout(() => {
                    window.location.href = '/chat';
                }, 1000);
            } else {
                this.showError(data.message || 'Failed to start guest session');
            }
        } catch (error) {
            this.showError('Guest session error: ' + error.message);
        }
    }

    showError(message) {
        this.removeExistingAlerts();
        const alert = document.createElement('div');
        alert.className = 'alert alert-danger alert-dismissible fade show';
        alert.innerHTML = `
            <i class="bi bi-exclamation-triangle"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        
        const container = document.getElementById('alert-container') || document.body;
        if (container === document.body) {
            container.insertBefore(alert, container.firstChild);
        } else {
            container.appendChild(alert);
        }
        
        setTimeout(() => {
            if (alert.parentNode) alert.remove();
        }, 5000);
    }

    showSuccess(message) {
        this.removeExistingAlerts();
        const alert = document.createElement('div');
        alert.className = 'alert alert-success alert-dismissible fade show';
        alert.innerHTML = `
            <i class="bi bi-check-circle"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        
        const container = document.getElementById('alert-container') || document.body;
        if (container === document.body) {
            container.insertBefore(alert, container.firstChild);
        } else {
            container.appendChild(alert);
        }
        
        setTimeout(() => {
            if (alert.parentNode) alert.remove();
        }, 5000);
    }

    removeExistingAlerts() {
        const alerts = document.querySelectorAll('.alert');
        alerts.forEach(alert => alert.remove());
    }
}

// =============================================================================
// GLOBAL FUNCTIONS - Available on all pages
// =============================================================================

// Global logout function - works for all user types
window.logout = function() {
    console.log('🚪 Logging out...');
    
    // Show loading state if possible
    const logoutBtn = document.querySelector('[onclick*="logout"]');
    if (logoutBtn) {
        logoutBtn.disabled = true;
        logoutBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Logging out...';
    }
    
    // Call server logout endpoint FIRST (before clearing client data)
    fetch('/api/auth/logout', { 
        method: 'POST', 
        credentials: 'include' 
    })
    .then(response => response.json())
    .then(data => {
        console.log('✅ Server logout successful');
        
        // Update navigation with the response if available
        if (data.nav_html) {
            const navElement = document.querySelector('nav');
            if (navElement) {
                navElement.outerHTML = data.nav_html;
                console.log('🔄 Navigation updated after logout');
            }
        }
        
        // Clear client-side data after server logout
        localStorage.clear();
        sessionStorage.clear();
        
        // Clear cookies manually
        const cookies = ['access_token', 'guest_token', 'session'];
        cookies.forEach(name => {
            document.cookie = `${name}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax`;
        });
        
        // Brief delay to show nav update, then redirect
        setTimeout(() => {
            window.location.href = '/';
        }, 500);
    })
    .catch((error) => {
        console.warn('Server logout failed, but continuing with client logout:', error);
        
        // Fallback: clear client data and redirect anyway
        localStorage.clear();
        sessionStorage.clear();
        
        const cookies = ['access_token', 'guest_token', 'session'];
        cookies.forEach(name => {
            document.cookie = `${name}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax`;
        });
        
        window.location.href = '/';
    });
};

// Guest session functions
window.startGuestSession = async function() {
    const publicInterface = new PublicInterface();
    await publicInterface.startGuestSession();
};

// Navigation update functions
window.updateNavigation = async function() {
    try {
        const response = await fetch('/api/auth/check', { credentials: 'include' });
        const data = await response.json();
        
        if (data.nav_html) {
            const navElement = document.querySelector('nav');
            if (navElement) {
                navElement.outerHTML = data.nav_html;
            }
        }
    } catch (error) {
        console.warn('Failed to update navigation:', error);
    }
};

// Check authentication status
window.checkAuth = async function() {
    try {
        const response = await fetch('/api/auth/check', { credentials: 'include' });
        const data = await response.json();
        return data;
    } catch (error) {
        console.warn('Auth check failed:', error);
        return { authenticated: false, user_type: 'none' };
    }
};

// =============================================================================
// AUTO-INITIALIZATION
// =============================================================================

// Auto-initialize based on page type
document.addEventListener('DOMContentLoaded', () => {
    // Initialize public interface for login/register pages
    if (document.getElementById('login-form') || 
        document.getElementById('register-form') ||
        document.querySelector('.hero-section')) {
        console.log('🎯 Initializing public interface');
        window.publicInterface = new PublicInterface();
    }
    
    // Add body class for index page styling
    if (document.querySelector('.hero-section')) {
        document.body.classList.add('index-page');
    }
    
    // Initialize tooltips if Bootstrap is available
    if (typeof bootstrap !== 'undefined') {
        const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
        tooltipTriggerList.map(function (tooltipTriggerEl) {
            return new bootstrap.Tooltip(tooltipTriggerEl);
        });
    }
});

// Handle page visibility changes
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
        // Refresh auth status when page becomes visible
        window.checkAuth();
    }
});