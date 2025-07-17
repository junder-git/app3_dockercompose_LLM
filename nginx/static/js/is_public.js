// =============================================================================
// nginx/static/js/public.js - COMPLETE CLASS-BASED APPROACH WITH SIMPLE LOGOUT
// =============================================================================

class PublicInterface {
    constructor() {
        this.init();
        this.setupGlobalMethods(); // Expose needed methods globally
    }

    init() {
        this.setupPublicFeatures();
        console.log('🌐 Public interface initialized');
    }

    setupGlobalMethods() {
        // Only expose methods that need to be called from HTML onclick attributes
        window.logout = this.logout.bind(this);
        window.startGuestSession = this.startGuestSession.bind(this);
        
        // These are also exposed for backward compatibility but could be removed
        window.updateNavigation = this.updateNavigation.bind(this);
        window.checkAuth = this.checkAuth.bind(this);
    }

    setupPublicFeatures() {
        this.setupAuthForms();
        this.setupGuestSessionButtons();
        this.setupPasswordToggle();
        this.setupEventDelegation();
    }

    setupAuthForms() {
        const loginForm = document.getElementById('login-form');
        if (loginForm) {
            loginForm.addEventListener('submit', this.handleLogin.bind(this));
        }

        const registerForm = document.getElementById('register-form');
        if (registerForm) {
            registerForm.addEventListener('submit', this.handleRegister.bind(this));
        }
    }

    setupPasswordToggle() {
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

    setupGuestSessionButtons() {
        // Handle existing onclick attributes
        const guestButtons = document.querySelectorAll('[onclick*="startGuestSession"]');
        guestButtons.forEach(button => {
            // Remove onclick and add event listener instead
            button.removeAttribute('onclick');
            button.addEventListener('click', this.startGuestSession.bind(this));
        });
    }

    setupEventDelegation() {
        // Modern event delegation for data attributes (optional upgrade path)
        document.addEventListener('click', (e) => {
            const action = e.target.getAttribute('data-action');
            
            switch (action) {
                case 'logout':
                    e.preventDefault();
                    this.logout();
                    break;
                case 'start-guest-session':
                    e.preventDefault();
                    this.startGuestSession();
                    break;
                case 'update-nav':
                    e.preventDefault();
                    this.updateNavigation();
                    break;
            }
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
        const originalBtnContent = loginBtn ? loginBtn.innerHTML : null;
        
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
                
                // Update navigation immediately with server response
                if (data.nav_html) {
                    this.updateNavigation(data.nav_html);
                }
                
                setTimeout(() => {
                    window.location.href = data.redirect || '/chat';
                }, 1000);
            } else {
                this.showError(data.error || 'Login failed');
            }
        } catch (error) {
            console.error('Login error:', error);
            this.showError('Login error: ' + error.message);
        } finally {
            if (loginBtn && originalBtnContent) {
                loginBtn.disabled = false;
                loginBtn.innerHTML = originalBtnContent;
            }
        }
    }

    async handleRegister(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        const userData = {
            username: formData.get('username'),
            password: formData.get('password')
        };

        const registerBtn = document.getElementById('register-btn');
        const originalBtnContent = registerBtn ? registerBtn.innerHTML : null;
        
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
            console.error('Registration error:', error);
            this.showError('Registration error: ' + error.message);
        } finally {
            if (registerBtn && originalBtnContent) {
                registerBtn.disabled = false;
                registerBtn.innerHTML = originalBtnContent;
            }
        }
    }

    async startGuestSession() {
        console.log('🎮 Starting guest session...');
        if (button) {
            button.disabled = true;
            button.innerHTML = '<i class="bi bi-hourglass-split"></i> Creating session...';
        }
        
        try {
            const response = await fetch('/api/guest/create-session', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include'
            });

            const data = await response.json();
            
            if (data.success) {
                console.log('✅ Guest session created:', data.username);
                this.showSuccess(`Guest session created as ${data.username}! Redirecting...`);
                
                // Update navigation if provided
                if (data.nav_html) {
                    this.updateNavigation(data.nav_html);
                }
                
                setTimeout(() => {
                    window.location.href = '/chat';
                }, 1000);
            } else {
                console.error('❌ Guest session failed:', data);
                this.showError(data.message || 'Failed to start guest session');
                
                // If guest sessions are full, redirect to main page with info
                if (data.error === 'no_slots_available') {
                    setTimeout(() => {
                        window.location.href = '/dash?guest_unavailable=1';
                    }, 2000);
                }
            }
        } catch (error) {
            console.error('Guest session error:', error);
            this.showError('Guest session error: ' + error.message);
        } finally {
            // Reset button state
            if (button) {
                button.disabled = false;
                button.innerHTML = '<i class="bi bi-chat-dots"></i> Start Chat';
            }
        }
    }

    clearClientData() {
        console.log('🧹 Clearing client data...');
        
        // Clear storage
        localStorage.clear();
        sessionStorage.clear();
        
        // Clear cookies with multiple approaches
        const cookies = ['access_token', 'guest_token', 'session'];
        cookies.forEach(name => {
            document.cookie = `${name}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax`;
            document.cookie = `${name}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax; Secure`;
            document.cookie = `${name}=; Path=/; Max-Age=0; SameSite=Lax`;
        });
        
        // Clear any other cookies that might exist
        document.cookie.split(";").forEach(function(c) {
            const eqPos = c.indexOf("=");
            const name = eqPos > -1 ? c.substr(0, eqPos) : c;
            const cleanName = name.trim();
            if (cleanName) {
                document.cookie = cleanName + "=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/";
                document.cookie = cleanName + "=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/;domain=" + window.location.hostname;
            }
        });
    }

    async logout() {
        console.log('🚪 Logging out...');
        
        const logoutBtn = document.querySelector('[onclick*="logout"], [data-action="logout"]');
        const originalContent = logoutBtn ? logoutBtn.innerHTML : null;
        
        if (logoutBtn) {
            logoutBtn.disabled = true;
            logoutBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Logging out...';
        }
        
        try {
            // JWT blacklisting on server prevents race condition - simple logout now!
            const response = await fetch('/api/auth/logout', { 
                method: 'POST', 
                credentials: 'include',
                headers: { 'Content-Type': 'application/json' }
            });
            
            const data = await response.json();
            console.log('✅ Server logout successful:', data);
            
            // Update navigation with server response
            if (data.nav_html) {
                this.updateNavigation(data.nav_html);
                console.log('🔄 Navigation updated after logout');
            }
            
            // Clear client-side data
            this.clearClientData();
            
            // Show success message
            this.showSuccess('Logged out successfully');
            
            // Simple redirect - JWT is blacklisted so no re-auth possible
            setTimeout(() => {
                window.location.href = data.redirect || '/';
            }, 500);
            
        } catch (error) {
            console.warn('Server logout failed, but continuing with client logout:', error);
            
            // Fallback: clear client data and redirect anyway
            this.clearClientData();
            
            // Reset button state
            if (logoutBtn && originalContent) {
                logoutBtn.disabled = false;
                logoutBtn.innerHTML = originalContent;
            }
            
            // Show warning and redirect
            this.showError('Logout may not be complete. Redirecting...');
            
            setTimeout(() => {
                window.location.href = '/';
            }, 1500);
        }
    }

    updateNavigation(navHtml = null) {
        if (navHtml) {
            // Direct update with provided HTML
            const navElement = document.querySelector('nav');
            if (navElement) {
                navElement.outerHTML = navHtml;
                console.log('🔄 Navigation updated directly');
                
                // Re-setup event listeners for new nav elements
                this.setupGuestSessionButtons();
            }
            return Promise.resolve();
        }

        // Fetch latest nav if not provided
        return fetch('/api/auth/check', { credentials: 'include' })
            .then(response => response.json())
            .then(data => {
                if (data.nav_html) {
                    const navElement = document.querySelector('nav');
                    if (navElement) {
                        navElement.outerHTML = data.nav_html;
                        console.log('🔄 Navigation updated from server');
                        
                        // Re-setup event listeners for new nav elements
                        this.setupGuestSessionButtons();
                    }
                }
                return data;
            })
            .catch(error => {
                console.warn('Failed to update navigation:', error);
                return null;
            });
    }

    async checkAuth() {
        try {
            const response = await fetch('/api/auth/check', { credentials: 'include' });
            const data = await response.json();
            
            console.log('🔍 Auth check result:', data.user_type || 'none');
            return data;
        } catch (error) {
            console.warn('Auth check failed:', error);
            return { authenticated: false, user_type: 'none' };
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
        
        // Auto-remove after 5 seconds
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
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
        
        // Auto-remove after 3 seconds for success messages
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, 3000);
    }

    showInfo(message) {
        this.removeExistingAlerts();
        const alert = document.createElement('div');
        alert.className = 'alert alert-info alert-dismissible fade show';
        alert.innerHTML = `
            <i class="bi bi-info-circle"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        
        const container = document.getElementById('alert-container') || document.body;
        if (container === document.body) {
            container.insertBefore(alert, container.firstChild);
        } else {
            container.appendChild(alert);
        }
        
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, 4000);
    }

    removeExistingAlerts() {
        const alerts = document.querySelectorAll('.alert');
        alerts.forEach(alert => {
            if (alert.parentNode) {
                alert.remove();
            }
        });
    }

    // Utility method for debugging
    getStatus() {
        return {
            initialized: true,
            currentPage: window.location.pathname,
            hasLoginForm: !!document.getElementById('login-form'),
            hasRegisterForm: !!document.getElementById('register-form'),
            hasNavigation: !!document.querySelector('nav'),
            timestamp: new Date().toISOString()
        };
    }
}

// =============================================================================
// AUTO-INITIALIZATION AND GLOBAL SETUP
// =============================================================================

let appInterface = null;

document.addEventListener('DOMContentLoaded', () => {
    console.log('🚀 Initializing application...');
    
    // Single initialization point
    appInterface = new PublicInterface();
    
    // Make available globally for debugging
    window.appInterface = appInterface;
    
    // Page-specific setup
    if (document.querySelector('.hero-section')) {
        document.body.classList.add('index-page');
        console.log('📄 Index page detected');
    }
    
    if (document.getElementById('login-form')) {
        console.log('🔐 Login page detected');
    }
    
    if (document.getElementById('register-form')) {
        console.log('📝 Register page detected');
    }
    
    // Initialize Bootstrap components if available
    if (typeof bootstrap !== 'undefined') {
        // Initialize tooltips
        const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
        tooltipTriggerList.map(function (tooltipTriggerEl) {
            return new bootstrap.Tooltip(tooltipTriggerEl);
        });
        
        // Initialize popovers
        const popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'));
        popoverTriggerList.map(function (popoverTriggerEl) {
            return new bootstrap.Popover(popoverTriggerEl);
        });
        
        console.log('🎨 Bootstrap components initialized');
    }
    
    // Auto-update navigation on page load
    appInterface.updateNavigation();
    
    console.log('✅ Application initialized successfully');
});

// Handle page visibility changes (user switches tabs)
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && appInterface) {
        console.log('👁️ Page became visible, checking auth status...');
        appInterface.checkAuth().then(data => {
            if (data && data.nav_html) {
                appInterface.updateNavigation(data.nav_html);
            }
        });
    }
});

// Handle browser back/forward navigation
window.addEventListener('popstate', () => {
    if (appInterface) {
        console.log('🔄 Browser navigation detected, updating nav...');
        appInterface.updateNavigation();
    }
});

// Handle online/offline status
window.addEventListener('online', () => {
    if (appInterface) {
        console.log('🌐 Connection restored');
        appInterface.showInfo('Connection restored');
        appInterface.updateNavigation();
    }
});

window.addEventListener('offline', () => {
    if (appInterface) {
        console.log('📴 Connection lost');
        appInterface.showError('Connection lost - some features may not work');
    }
});

// Global error handler for unhandled promises
window.addEventListener('unhandledrejection', (event) => {
    console.error('Unhandled promise rejection:', event.reason);
    if (appInterface) {
        appInterface.showError('An unexpected error occurred');
    }
});


document.addEventListener('DOMContentLoaded', () => {
    const chatInput = document.getElementById('chat-input');
    if (chatInput) {
        chatInput.addEventListener('input', function() {
            this.style.height = '';
            this.style.height = this.scrollHeight + 'px';
        });
    }
});