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
            
            console.log('User data received:', data); // Debug log
            
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
        console.log('Updating navbar for user:', userData); // Debug log
        
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

        // Show admin nav if user is admin
        if (elements.adminNav) {
            if (userData.is_admin === true) {
                console.log('User is admin - showing admin nav'); // Debug log
                elements.adminNav.style.display = 'block';
            } else {
                console.log('User is not admin - hiding admin nav'); // Debug log
                elements.adminNav.style.display = 'none';
            }
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

    // Fixed logout with proper cookie clearing
    logout() {
        console.log('Logout function called'); // Debug log
        
        try {
            // Clear all authentication cookies with multiple variations
            const cookiesToClear = ['access_token', 'session', 'auth_token'];
            const cookiePaths = ['/', '/api', '/chat', '/admin'];
            const domains = [window.location.hostname, '.' + window.location.hostname, 'localhost', '127.0.0.1'];
            
            cookiesToClear.forEach(cookieName => {
                cookiePaths.forEach(path => {
                    // Clear for each path
                    document.cookie = `${cookieName}=; Path=${path}; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax`;
                    document.cookie = `${cookieName}=; Path=${path}; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure=false`;
                    
                    // Clear for each domain
                    domains.forEach(domain => {
                        document.cookie = `${cookieName}=; Path=${path}; Domain=${domain}; Expires=Thu, 01 Jan 1970 00:00:00 GMT`;
                    });
                });
            });
            
            console.log('Cookies cleared'); // Debug log
            
            // Clear any stored session data
            if (typeof(Storage) !== "undefined") {
                try {
                    localStorage.removeItem('devstral_chat_history');
                    localStorage.removeItem('devstral_user_preferences');
                    sessionStorage.clear();
                    console.log('Local storage cleared'); // Debug log
                } catch (e) {
                    console.warn('Could not clear localStorage:', e);
                }
            }

            // Update navbar immediately to show guest state
            this.updateNavbarForGuest();
            
            // Show logout message without alert popup
            console.log('Logout successful - redirecting to home page...'); // Debug log
            
            // Redirect to home page immediately without popup
            window.location.href = '/';
            
        } catch (error) {
            console.error('Logout error:', error);
            // Force redirect even if there's an error
            window.location.href = '/';
        }
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
        
        // Load user data and update navbar
        this.loadUser().then(userData => {
            if (userData) {
                console.log('User loaded successfully:', userData);
            } else {
                console.log('No user logged in');
            }
        });
        
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