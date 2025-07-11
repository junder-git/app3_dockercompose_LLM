// Enhanced Common JavaScript Functions for ai.junder.uk
// nginx/html/js/common.js

const DevstralCommon = {
    // API base configuration
    config: {
        baseUrl: '',
        timeout: 30000,
        retryAttempts: 3
    },

    // Enhanced API helper with retry logic
    async apiCall(endpoint, options = {}) {
        const defaultOptions = {
            credentials: 'include',
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            timeout: this.config.timeout,
            ...options
        };

        for (let attempt = 1; attempt <= this.config.retryAttempts; attempt++) {
            try {
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), defaultOptions.timeout);

                const response = await fetch(this.config.baseUrl + endpoint, {
                    ...defaultOptions,
                    signal: controller.signal
                });

                clearTimeout(timeoutId);

                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }

                return await response.json();
            } catch (error) {
                console.warn(`API call attempt ${attempt} failed:`, error.message);
                
                if (attempt === this.config.retryAttempts) {
                    throw error;
                }
                
                // Exponential backoff
                await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000));
            }
        }
    },

    // Enhanced user loading with detailed info
    async loadUser() {
        try {
            const data = await this.apiCall('/api/auth/me');
            
            if (data.success && data.username) {
                this.updateNavbarForLoggedInUser(data);
                return data;
            } else {
                this.updateNavbarForGuest();
                return null;
            }
        } catch (error) {
            console.warn('Could not load user info:', error);
            this.updateNavbarForGuest();
            return null;
        }
    },

    // Update navbar for logged-in user
    updateNavbarForLoggedInUser(userData) {
        const elements = {
            username: document.getElementById('navbar-username'),
            userNav: document.getElementById('user-nav'),
            adminNav: document.getElementById('admin-nav'),
            guestNav: document.getElementById('guest-nav'),
            guestNav2: document.getElementById('guest-nav-2'),
            logoutButton: document.getElementById('logout-button')
        };

        if (elements.username) {
            elements.username.textContent = userData.username;
        }

        if (elements.userNav) {
            elements.userNav.style.display = 'block';
        }

        if (elements.adminNav && userData.is_admin) {
            elements.adminNav.style.display = 'block';
        }

        if (elements.guestNav) {
            elements.guestNav.style.display = 'none';
        }

        if (elements.guestNav2) {
            elements.guestNav2.style.display = 'none';
        }

        if (elements.logoutButton) {
            elements.logoutButton.onclick = () => this.logout();
        }
    },

    // Update navbar for guest user
    updateNavbarForGuest() {
        const elements = {
            userNav: document.getElementById('user-nav'),
            adminNav: document.getElementById('admin-nav'),
            guestNav: document.getElementById('guest-nav'),
            guestNav2: document.getElementById('guest-nav-2')
        };

        if (elements.userNav) {
            elements.userNav.style.display = 'none';
        }

        if (elements.adminNav) {
            elements.adminNav.style.display = 'none';
        }

        if (elements.guestNav) {
            elements.guestNav.style.display = 'block';
        }

        if (elements.guestNav2) {
            elements.guestNav2.style.display = 'block';
        }
    },

    // Enhanced login with better error handling
    async setupLogin() {
        const form = document.getElementById('login-form');
        if (!form) return;

        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const formData = new FormData(form);
            const credentials = {
                username: formData.get('username')?.trim(),
                password: formData.get('password')
            };

            if (!credentials.username || !credentials.password) {
                this.showAlert('Please fill in all fields.', 'danger');
                return;
            }

            const submitButton = form.querySelector('button[type="submit"]');
            const originalText = submitButton.innerHTML;
            
            try {
                submitButton.disabled = true;
                submitButton.innerHTML = '<i class="bi bi-hourglass-split"></i> Signing in...';

                const data = await this.apiCall('/api/auth/login', {
                    method: 'POST',
                    body: JSON.stringify(credentials)
                });

                if (data.token) {
                    this.showAlert('Login successful! Redirecting...', 'success');
                    
                    const redirect = new URLSearchParams(window.location.search).get('redirect') || '/chat.html';
                    setTimeout(() => {
                        window.location.href = redirect;
                    }, 1000);
                } else {
                    this.showAlert(this.getLoginErrorMessage(data.error), 'danger');
                }
            } catch (error) {
                this.showAlert('Connection error. Please try again.', 'danger');
            } finally {
                submitButton.disabled = false;
                submitButton.innerHTML = originalText;
            }
        });
    },

    // Enhanced registration with validation
    async setupRegister() {
        const form = document.getElementById('register-form');
        if (!form) return;

        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const formData = new FormData(form);
            const userData = {
                username: formData.get('username')?.trim(),
                password: formData.get('password')
            };

            const confirmPassword = formData.get('confirm-password');

            // Client-side validation
            if (!userData.username || !userData.password || !confirmPassword) {
                this.showAlert('Please fill in all fields.', 'danger');
                return;
            }

            if (userData.password !== confirmPassword) {
                this.showAlert('Passwords do not match.', 'danger');
                return;
            }

            if (!this.validateUsername(userData.username)) {
                this.showAlert('Username must be 3-20 characters and contain only letters, numbers, and underscores.', 'danger');
                return;
            }

            if (userData.password.length < 6) {
                this.showAlert('Password must be at least 6 characters long.', 'danger');
                return;
            }

            const submitButton = form.querySelector('button[type="submit"]');
            const originalText = submitButton.innerHTML;
            
            try {
                submitButton.disabled = true;
                submitButton.innerHTML = '<i class="bi bi-hourglass-split"></i> Creating account...';

                const data = await this.apiCall('/api/register', {
                    method: 'POST',
                    body: JSON.stringify(userData)
                });

                if (data.message) {
                    this.showAlert(data.message + ' You can now login once approved.', 'success');
                    form.reset();
                    
                    setTimeout(() => {
                        window.location.href = '/login.html';
                    }, 3000);
                } else {
                    this.showAlert(this.getRegistrationErrorMessage(data.error), 'danger');
                }
            } catch (error) {
                this.showAlert('Connection error. Please try again.', 'danger');
            } finally {
                submitButton.disabled = false;
                submitButton.innerHTML = originalText;
            }
        });
    },

    // Logout with cleanup
    logout() {
        // Clear all authentication cookies
        document.cookie = 'access_token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
        
        // Clear any stored session data
        if (typeof(Storage) !== "undefined") {
            try {
                localStorage.removeItem('devstral_chat_history');
                localStorage.removeItem('devstral_user_preferences');
            } catch (e) {
                console.warn('Could not clear localStorage');
            }
        }

        // Show logout message
        this.showAlert('Logged out successfully', 'info');
        
        // Redirect to home page
        setTimeout(() => {
            window.location.href = '/';
        }, 1000);
    },

    // Enhanced alert system
    showAlert(message, type = 'info', duration = 5000) {
        // Remove existing alerts
        const existingAlerts = document.querySelectorAll('.flash-message');
        existingAlerts.forEach(alert => alert.remove());

        const alertDiv = document.createElement('div');
        alertDiv.className = `alert alert-${type} alert-dismissible fade show flash-message`;
        alertDiv.style.position = 'fixed';
        alertDiv.style.top = '20px';
        alertDiv.style.left = '50%';
        alertDiv.style.transform = 'translateX(-50%)';
        alertDiv.style.zIndex = '9999';
        alertDiv.style.minWidth = '300px';
        alertDiv.style.maxWidth = '500px';

        const iconMap = {
            success: 'bi-check-circle',
            danger: 'bi-x-circle',
            warning: 'bi-exclamation-triangle',
            info: 'bi-info-circle'
        };

        alertDiv.innerHTML = `
            <i class="bi ${iconMap[type] || iconMap.info}"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;

        document.body.appendChild(alertDiv);

        // Auto-dismiss
        if (duration > 0) {
            setTimeout(() => {
                if (alertDiv.parentNode) {
                    alertDiv.remove();
                }
            }, duration);
        }
    },

    // Validation helpers
    validateUsername(username) {
        const pattern = /^[a-zA-Z0-9_]{3,20}$/;
        return pattern.test(username);
    },

    validateEmail(email) {
        const pattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return pattern.test(email);
    },

    // Error message helpers
    getLoginErrorMessage(error) {
        const errorMessages = {
            'Invalid credentials': 'Invalid username or password.',
            'User not approved': 'Your account is pending approval. Please wait for an administrator to approve your account.',
            'User not found': 'Account not found. Please check your username or register for a new account.',
            'Account locked': 'Your account has been temporarily locked. Please contact support.'
        };
        
        return errorMessages[error] || error || 'Login failed. Please try again.';
    },

    getRegistrationErrorMessage(error) {
        const errorMessages = {
            'User already exists': 'Username already taken. Please choose a different username.',
            'Username and password required': 'Please provide both username and password.',
            'Invalid username': 'Username must be 3-20 characters and contain only letters, numbers, and underscores.',
            'Password too short': 'Password must be at least 6 characters long.',
            'Registration disabled': 'New registrations are currently disabled. Please contact support.'
        };
        
        return errorMessages[error] || error || 'Registration failed. Please try again.';
    },

    // Utility functions
    formatDate(dateString) {
        if (!dateString || dateString === 'Never') return 'Never';
        
        try {
            const date = new Date(dateString);
            return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
        } catch (error) {
            return dateString;
        }
    },

    formatTimeAgo(dateString) {
        if (!dateString || dateString === 'Never') return 'Never';
        
        try {
            const date = new Date(dateString);
            const now = new Date();
            const diffMs = now - date;
            const diffMins = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);
            const diffDays = Math.floor(diffMs / 86400000);

            if (diffMins < 1) return 'Just now';
            if (diffMins < 60) return `${diffMins} minute${diffMins !== 1 ? 's' : ''} ago`;
            if (diffHours < 24) return `${diffHours} hour${diffHours !== 1 ? 's' : ''} ago`;
            if (diffDays < 7) return `${diffDays} day${diffDays !== 1 ? 's' : ''} ago`;
            
            return date.toLocaleDateString();
        } catch (error) {
            return dateString;
        }
    },

    // Theme management
    setTheme(theme) {
        document.documentElement.setAttribute('data-bs-theme', theme);
        if (typeof(Storage) !== "undefined") {
            try {
                localStorage.setItem('devstral_theme', theme);
            } catch (e) {
                console.warn('Could not save theme preference');
            }
        }
    },

    loadTheme() {
        if (typeof(Storage) !== "undefined") {
            try {
                const savedTheme = localStorage.getItem('devstral_theme');
                if (savedTheme) {
                    this.setTheme(savedTheme);
                }
            } catch (e) {
                console.warn('Could not load theme preference');
            }
        }
    },

    // Initialize common functionality
    init() {
        this.loadTheme();
        this.loadUser();
        
        // Set up global error handler
        window.addEventListener('unhandledrejection', (event) => {
            console.error('Unhandled promise rejection:', event.reason);
            this.showAlert('An unexpected error occurred. Please refresh the page.', 'danger');
        });
    }
};

// Auto-initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    DevstralCommon.init();
});

// Legacy support for existing code
const apiGet = DevstralCommon.apiCall;
const apiPost = (endpoint, data) => DevstralCommon.apiCall(endpoint, { method: 'POST', body: JSON.stringify(data) });

// Export for module usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = DevstralCommon;
}