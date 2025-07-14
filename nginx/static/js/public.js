// =============================================================================
// nginx/static/js/public.js - PUBLIC/UNAUTHENTICATED USERS
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

        try {
            const response = await fetch('/api/auth/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify(credentials)
            });

            const data = await response.json();
            
            if (data.success) {
                window.location.href = data.dashboard_url || '/chat';
            } else {
                this.showError(data.error || 'Login failed');
            }
        } catch (error) {
            this.showError('Login error: ' + error.message);
        }
    }

    async handleRegister(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        const userData = {
            username: formData.get('username'),
            password: formData.get('password')
        };

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
                window.location.href = '/chat';
            } else {
                this.showError('Failed to start guest session');
            }
        } catch (error) {
            this.showError('Guest session error: ' + error.message);
        }
    }

    showError(message) {
        const alert = document.createElement('div');
        alert.className = 'alert alert-danger';
        alert.textContent = message;
        document.body.insertBefore(alert, document.body.firstChild);
        
        setTimeout(() => alert.remove(), 5000);
    }

    showSuccess(message) {
        const alert = document.createElement('div');
        alert.className = 'alert alert-success';
        alert.textContent = message;
        document.body.insertBefore(alert, document.body.firstChild);
        
        setTimeout(() => alert.remove(), 5000);
    }
}

// Public functions
window.startGuestSession = async function() {
    const publicInterface = new PublicInterface();
    await publicInterface.startGuestSession();
};

// Auto-initialize based on page type
document.addEventListener('DOMContentLoaded', () => {
    // Initialize public interface for login/register pages
    if (document.getElementById('login-form') || document.getElementById('register-form')) {
        window.publicInterface = new PublicInterface();
    }
});