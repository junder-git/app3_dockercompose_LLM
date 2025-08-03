// =============================================================================
// nginx/static/js/is_shared.js - SIMPLIFIED SHARED FUNCTIONALITY WITH SESSION HANDLING
// =============================================================================

// =============================================================================
// SHARED INTERFACE - NO AUTH STATUS CHECKS
// =============================================================================

class SharedInterface {
    constructor() {
        this.init();
        this.setupGlobalMethods();
    }

    init() {
        this.setupPublicFeatures();
        console.log('🌐 Shared interface initialized');
    }

    setupGlobalMethods() {
        // Only expose methods that need to be called from HTML onclick attributes
        window.logout = this.logout.bind(this);
        window.handleLogin = this.handleLogin.bind(this);
        window.handleRegister = this.handleRegister.bind(this);
        window.startGuestSession = this.startGuestSession.bind(this);
    }

    setupPublicFeatures() {
        this.setupAuthForms();
        this.setupPasswordToggle();
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

    // =============================================================================
    // FIXED handleLogin function - Add this to replace the existing one in is_shared.js
    // =============================================================================

    async handleLogin(e) {
        e.preventDefault();
        
        console.log('🚀 Login form submitted');
        
        const form = e.target.closest('form') || document.getElementById('login-form');
        if (!form) {
            console.error('❌ No form found');
            return;
        }
        
        const formData = new FormData(form);
        const credentials = {
            username: formData.get('username'),
            password: formData.get('password')
        };

        console.log('🔑 Extracted credentials:', {
            username: credentials.username,
            hasPassword: !!credentials.password,
            passwordLength: credentials.password ? credentials.password.length : 0
        });

        if (!credentials.username || !credentials.password) {
            this.showError('Please enter both username and password');
            return;
        }

        const submitBtn = form.querySelector('button[type="submit"]');
        const originalContent = submitBtn ? submitBtn.innerHTML : null;
        
        if (submitBtn) {
            submitBtn.disabled = true;
            submitBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Signing in...';
        }

        try {
            const requestBody = JSON.stringify(credentials);
            console.log('📤 Sending request with body:', requestBody);
            
            const response = await fetch('/api/auth/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                // CRITICAL: Don't follow redirects automatically
                redirect: 'manual',
                // CRITICAL FIX: Add the missing body
                body: requestBody
            });

            console.log('📡 Response received:', response.status, response.statusText);

            // Handle server redirect (302)
            if (response.status === 302) {
                const location = response.headers.get('Location');
                console.log('✅ Server redirect to:', location);
                
                this.showSuccess('Login successful! Redirecting...');
                
                // Small delay to ensure cookie is processed
                setTimeout(() => {
                    window.location.href = location || '/chat';
                }, 500);
                return;
            }

            // Handle JSON responses (errors)
            if (response.headers.get('content-type')?.includes('application/json')) {
                const data = await response.json();
                
                if (data.success) {
                    // Fallback JSON success (shouldn't happen with new code)
                    this.showSuccess('Login successful! Redirecting...');
                    setTimeout(() => {
                        window.location.href = data.redirect || '/chat';
                    }, 1000);
                } else {
                    // Handle error responses
                    let errorMessage = data.error || 'Login failed';
                    
                    if (data.reason === 'sessions_full') {
                        errorMessage = `Login blocked: ${data.message || 'Sessions are currently full.'}`;
                    } else if (data.reason === 'concurrent_session_limit') {
                        errorMessage = `Cannot login: ${data.message || 'Another user is currently logged in.'}`;
                    }
                    
                    console.error('❌ Login error:', errorMessage);
                    this.showError(errorMessage);
                }
            } else {
                // Unexpected response
                console.error('❌ Unexpected response type');
                throw new Error(`Unexpected response: ${response.status}`);
            }
            
        } catch (error) {
            console.error('❌ Login error:', error);
            this.showError('Login error: ' + error.message);
        } finally {
            if (submitBtn && originalContent) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalContent;
            }
        }
    }

    async handleRegister(e) {
        e.preventDefault();
        
        const form = e.target.closest('form') || document.getElementById('registerForm');
        if (!form) return;
        
        const formData = new FormData(form);
        const userData = {
            username: formData.get('username'),
            password: formData.get('password')
        };

        const confirmPassword = formData.get('confirmPassword');
        if (confirmPassword && userData.password !== confirmPassword) {
            this.showError('Passwords do not match');
            return;
        }

        if (!userData.username || !userData.password) {
            this.showError('Please fill in all fields');
            return;
        }

        const submitBtn = form.querySelector('button[type="submit"]');
        const originalContent = submitBtn ? submitBtn.innerHTML : null;
        
        if (submitBtn) {
            submitBtn.disabled = true;
            submitBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Creating account...';
        }

        try {
            const response = await fetch('/api/auth/register', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(userData)
            });

            const data = await response.json();
            
            if (data.success) {
                this.showSuccess('Registration successful! Please wait for approval.');
                setTimeout(() => {
                    window.location.href = data.redirect || '/login';
                }, 2000);
            } else {
                this.showError(data.error || 'Registration failed');
            }
        } catch (error) {
            console.error('Registration error:', error);
            this.showError('Registration error: ' + error.message);
        } finally {
            if (submitBtn && originalContent) {
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalContent;
            }
        }
    }

    async startGuestSession() {
        console.log('🎮 Starting guest session...');
        
        const button = document.querySelector('button[onclick*="startGuestSession"]');
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
                this.showSuccess('Guest session created! Redirecting...');
                
                // Direct redirect - let server handle auth state
                setTimeout(() => {
                    window.location.href = data.redirect || '/chat';
                }, 1000);
            } else {
                // Handle sessions full error specifically
                let errorMessage = data.error || 'Failed to create guest session';
                
                if (data.reason === 'sessions_full') {
                    errorMessage = `Sessions are currently full. ${data.message || 'Please try again later.'}`;
                }
                
                this.showError(errorMessage);
            }
        } catch (error) {
            console.error('Guest session error:', error);
            this.showError('Failed to create guest session: ' + error.message);
        } finally {
            if (button) {
                button.disabled = false;
                button.innerHTML = '<i class="bi bi-chat-dots"></i> Start Guest Chat';
            }
        }
    }

    async logout() {
        console.log('🚪 Logging out...');
        
        const logoutBtn = document.querySelector('[onclick*="logout"]');
        const originalContent = logoutBtn ? logoutBtn.innerHTML : null;
        
        if (logoutBtn) {
            logoutBtn.disabled = true;
            logoutBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Logging out...';
        }
        
        try {
            const response = await fetch('/api/auth/logout', { 
                method: 'POST', 
                credentials: 'include',
                headers: { 'Content-Type': 'application/json' }
            });
            
            const data = await response.json();
            console.log('✅ Server logout successful:', data);
            
            this.showSuccess('Logged out successfully');
            
            // Direct redirect - let server handle auth state
            setTimeout(() => {
                window.location.href = data.redirect || '/';
            }, 500);
            
        } catch (error) {
            console.warn('Server logout failed, but continuing with redirect:', error);
            
            if (logoutBtn && originalContent) {
                logoutBtn.disabled = false;
                logoutBtn.innerHTML = originalContent;
            }
            
            this.showError('Logout may not be complete. Redirecting...');
            
            setTimeout(() => {
                window.location.href = '/';
            }, 1500);
        }
    }

    // =============================================================================
    // ALERT SYSTEM
    // =============================================================================
    showError(message) {
        this.showAlert(message, 'danger', 'exclamation-triangle');
    }

    showSuccess(message) {
        this.showAlert(message, 'success', 'check-circle');
    }

    showInfo(message) {
        this.showAlert(message, 'info', 'info-circle');
    }

    showWarning(message) {
        this.showAlert(message, 'warning', 'exclamation-triangle');
    }

    showAlert(message, type, icon) {
        // Remove existing alerts
        document.querySelectorAll('.auth-message, .alert').forEach(alert => {
            if (alert.parentNode) alert.remove();
        });
        
        const alert = document.createElement('div');
        alert.className = `alert alert-${type} alert-dismissible fade show auth-message`;
        alert.style.cssText = 'position: fixed; top: 20px; left: 50%; transform: translateX(-50%); z-index: 9999; max-width: 500px;';
        alert.innerHTML = `
            <i class="bi bi-${icon}"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        
        document.body.appendChild(alert);
        
        // Auto-remove
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, type === 'success' ? 3000 : 5000);
    }
}

// =============================================================================
// MODAL UTILITIES
// =============================================================================

class SharedModalUtils {
    static createModal(id, title, body, buttons = []) {
        const modalHTML = `
            <div class="modal fade" id="${id}" tabindex="-1" aria-labelledby="${id}Label" aria-hidden="true">
                <div class="modal-dialog modal-dialog-centered">
                    <div class="modal-content bg-dark">
                        <div class="modal-header">
                            <h5 class="modal-title" id="${id}Label">${title}</h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                        </div>
                        <div class="modal-body">
                            ${body}
                        </div>
                        <div class="modal-footer">
                            ${buttons.map(btn => `<button type="button" class="btn btn-${btn.type}" ${btn.dismiss ? 'data-bs-dismiss="modal"' : ''} id="${btn.id}">${btn.text}</button>`).join('')}
                        </div>
                    </div>
                </div>
            </div>
        `;

        document.body.insertAdjacentHTML('beforeend', modalHTML);
        return new bootstrap.Modal(document.getElementById(id));
    }
}

// =============================================================================
// INITIALIZATION
// =============================================================================

let sharedInterface = null;

document.addEventListener('DOMContentLoaded', () => {
    console.log('🚀 Initializing simplified shared interface...');
    
    sharedInterface = new SharedInterface();
    
    // Make available globally
    window.sharedInterface = sharedInterface;
    window.SharedModalUtils = SharedModalUtils;
    
    console.log('✅ Simplified shared interface initialized');
});

// Global error handler
window.addEventListener('unhandledrejection', (event) => {
    console.error('Unhandled promise rejection:', event.reason);
    if (sharedInterface) {
        sharedInterface.showError('An unexpected error occurred');
    }
});