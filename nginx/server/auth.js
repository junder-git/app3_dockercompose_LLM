// auth.js - Authentication Module (JavaScript equivalent of Python auth.py)

class AuthModule {
    constructor(app) {
        this.app = app;
        this.session = window.authSession;
        
        // Configuration
        this.config = {
            MAX_PENDING_USERS: 2,
            MIN_USERNAME_LENGTH: 3,
            MAX_USERNAME_LENGTH: 50,
            MIN_PASSWORD_LENGTH: 6,
            MAX_PASSWORD_LENGTH: 128
        };
        
        console.log('🔐 AuthModule created');
    }

    async loadLoginPage() {
        const html = `
            <div class="row justify-content-center">
                <div class="col-md-6 col-lg-4">
                    <div class="card border-secondary">
                        <div class="card-header">
                            <h4 class="mb-0">
                                <i class="bi bi-box-arrow-in-right"></i> Login
                            </h4>
                        </div>
                        <div class="card-body">
                            <div id="login-error" class="alert alert-danger d-none">
                                <i class="bi bi-exclamation-triangle"></i> <span id="login-error-text"></span>
                            </div>
                            
                            <form id="login-form">
                                <div class="mb-3">
                                    <label for="login-username" class="form-label">
                                        <i class="bi bi-person"></i> Username
                                    </label>
                                    <input type="text" class="form-control" id="login-username" name="username" required autofocus>
                                </div>
                                <div class="mb-3">
                                    <label for="login-password" class="form-label">
                                        <i class="bi bi-lock"></i> Password
                                    </label>
                                    <input type="password" class="form-control" id="login-password" name="password" required>
                                </div>
                                <div class="d-grid">
                                    <button type="submit" class="btn btn-primary" id="login-submit">
                                        <i class="bi bi-box-arrow-in-right"></i> Login
                                    </button>
                                </div>
                            </form>
                            
                            <div class="mt-3 text-center">
                                <p>Don't have an account? 
                                    <a href="#register" class="text-primary" data-route="register">
                                        <i class="bi bi-person-plus"></i> Register here
                                    </a>
                                </p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        $('#app-content').html(html);
        this.bindLoginEvents();
    }

    bindLoginEvents() {
        $('#login-form').on('submit', async (e) => {
            e.preventDefault();
            await this.handleLogin();
        });
        
        // Handle register link
        $('a[data-route="register"]').on('click', (e) => {
            e.preventDefault();
            this.app.navigate('register');
        });
    }

    async handleLogin() {
        try {
            const username = $('#login-username').val().trim();
            const password = $('#login-password').val();
            
            if (!username || !password) {
                this.showLoginError('Username and password are required');
                return;
            }
            
            // Disable form
            $('#login-submit').prop('disabled', true).html('<span class="spinner-border spinner-border-sm" role="status"></span> Logging in...');
            
            // Get user from database
            const user = await window.Database.getUserByUsername(username);
            
            if (user && await this.verifyPassword(password, user.password_hash)) {
                // Check if user is approved
                if (user.is_admin || user.is_approved) {
                    // Successful login
                    const csrfToken = this.generateCsrfToken();
                    this.session.setSession(user, csrfToken);
                    
                    console.log('✅ User logged in:', user.username);
                    
                    // Update app user and navigate to chat
                    await this.app.refreshCurrentUser();
                    this.app.navigate('chat');
                } else {
                    this.showLoginError('Your account is pending admin approval. Please wait for activation.');
                }
            } else {
                this.showLoginError('Invalid username or password');
            }
            
        } catch (error) {
            console.error('❌ Login error:', error);
            this.showLoginError('Login failed. Please try again.');
        } finally {
            $('#login-submit').prop('disabled', false).html('<i class="bi bi-box-arrow-in-right"></i> Login');
        }
    }

    async loadRegisterPage() {
        // Get pending user count
        const pendingCount = await window.Database.getPendingUsersCount();
        const registrationClosed = pendingCount >= this.config.MAX_PENDING_USERS;
        
        const html = `
            <div class="row justify-content-center">
                <div class="col-md-6 col-lg-4">
                    <div class="card border-secondary">
                        <div class="card-header">
                            <h4 class="mb-0">
                                <i class="bi bi-person-plus"></i> Register
                            </h4>
                        </div>
                        <div class="card-body">
                            <div id="register-error" class="alert alert-danger d-none">
                                <i class="bi bi-exclamation-triangle"></i> <span id="register-error-text"></span>
                            </div>
                            
                            <div id="register-success" class="alert alert-success d-none">
                                <i class="bi bi-check-circle"></i> <span id="register-success-text"></span>
                            </div>
                            
                            ${registrationClosed ? this.getRegistrationClosedHtml(pendingCount) : this.getRegistrationFormHtml(pendingCount)}
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        $('#app-content').html(html);
        
        if (!registrationClosed) {
            this.bindRegisterEvents();
        }
        
        // Handle login link
        $('a[data-route="login"]').on('click', (e) => {
            e.preventDefault();
            this.app.navigate('login');
        });
    }

    getRegistrationClosedHtml(pendingCount) {
        return `
            <div class="alert alert-warning" role="alert">
                <i class="bi bi-exclamation-triangle"></i> 
                <strong>Registration Temporarily Closed</strong><br>
                We currently have the maximum number of pending registrations (${pendingCount}/${this.config.MAX_PENDING_USERS}). 
                Please check back later when spots become available.
            </div>
            
            <div class="text-center">
                <p>Already have an account? 
                    <a href="#login" class="text-primary" data-route="login">
                        <i class="bi bi-box-arrow-in-right"></i> Login here
                    </a>
                </p>
            </div>
        `;
    }

    getRegistrationFormHtml(pendingCount) {
        return `
            <div class="alert alert-info" role="alert">
                <i class="bi bi-info-circle"></i> 
                <strong>Registration requires admin approval.</strong><br>
                After registering, please wait for an administrator to approve your account before you can log in.
                
                <div class="mt-2">
                    <small class="text-muted">
                        <i class="bi bi-people"></i> 
                        Current pending registrations: ${pendingCount}/${this.config.MAX_PENDING_USERS}
                        ${pendingCount >= this.config.MAX_PENDING_USERS - 1 ? '<span class="text-warning">(Registration will close after this submission)</span>' : ''}
                    </small>
                </div>
            </div>
            
            <form id="register-form">
                <div class="mb-3">
                    <label for="register-username" class="form-label">
                        <i class="bi bi-person"></i> Username
                    </label>
                    <input type="text" class="form-control" id="register-username" name="username" 
                           placeholder="${this.config.MIN_USERNAME_LENGTH}-${this.config.MAX_USERNAME_LENGTH} characters" 
                           required autofocus 
                           minlength="${this.config.MIN_USERNAME_LENGTH}"
                           maxlength="${this.config.MAX_USERNAME_LENGTH}">
                    <div class="form-text">${this.config.MIN_USERNAME_LENGTH}-${this.config.MAX_USERNAME_LENGTH} characters, letters, numbers, underscore, and dash only</div>
                </div>
                <div class="mb-3">
                    <label for="register-password" class="form-label">
                        <i class="bi bi-lock"></i> Password
                    </label>
                    <input type="password" class="form-control" id="register-password" name="password" 
                           placeholder="${this.config.MIN_PASSWORD_LENGTH}-${this.config.MAX_PASSWORD_LENGTH} characters" 
                           required
                           minlength="${this.config.MIN_PASSWORD_LENGTH}"
                           maxlength="${this.config.MAX_PASSWORD_LENGTH}">
                    <div class="form-text">${this.config.MIN_PASSWORD_LENGTH}-${this.config.MAX_PASSWORD_LENGTH} characters</div>
                </div>
                <div class="mb-3">
                    <label for="register-confirm-password" class="form-label">
                        <i class="bi bi-lock-fill"></i> Confirm Password
                    </label>
                    <input type="password" class="form-control" id="register-confirm-password" 
                           name="confirm_password" required
                           minlength="${this.config.MIN_PASSWORD_LENGTH}"
                           maxlength="${this.config.MAX_PASSWORD_LENGTH}">
                </div>
                <div class="d-grid">
                    <button type="submit" class="btn btn-primary" id="register-submit">
                        <i class="bi bi-person-plus"></i> Register (Pending Approval)
                    </button>
                </div>
            </form>
            
            <div class="mt-3 text-center">
                <p>Already have an account? 
                    <a href="#login" class="text-primary" data-route="login">
                        <i class="bi bi-box-arrow-in-right"></i> Login here
                    </a>
                </p>
            </div>
        `;
    }

    bindRegisterEvents() {
        $('#register-form').on('submit', async (e) => {
            e.preventDefault();
            await this.handleRegister();
        });
        
        // Password confirmation validation
        $('#register-confirm-password').on('input', function() {
            const password = $('#register-password').val();
            const confirmPassword = $(this).val();
            
            if (password !== confirmPassword) {
                this.setCustomValidity('Passwords do not match');
            } else {
                this.setCustomValidity('');
            }
        });

        // Username validation
        $('#register-username').on('input', function() {
            const username = $(this).val();
            const usernamePattern = /^[a-zA-Z0-9_-]+$/;
            
            if (username && !usernamePattern.test(username)) {
                this.setCustomValidity('Username can only contain letters, numbers, underscore and dash');
            } else {
                this.setCustomValidity('');
            }
        });
    }

    async handleRegister() {
        try {
            const username = $('#register-username').val().trim();
            const password = $('#register-password').val();
            const confirmPassword = $('#register-confirm-password').val();
            
            // Validate inputs
            const validation = this.validateRegistration(username, password, confirmPassword);
            if (!validation.valid) {
                this.showRegisterError(validation.message);
                return;
            }
            
            // Check pending users limit
            const pendingCount = await window.Database.getPendingUsersCount();
            if (pendingCount >= this.config.MAX_PENDING_USERS) {
                this.showRegisterError(`Registration temporarily closed. Too many pending approvals (${pendingCount}/${this.config.MAX_PENDING_USERS}). Please try again later.`);
                return;
            }
            
            // Disable form
            $('#register-submit').prop('disabled', true).html('<span class="spinner-border spinner-border-sm" role="status"></span> Registering...');
            
            // Check if user exists
            const existingUser = await window.Database.getUserByUsername(username);
            if (existingUser) {
                this.showRegisterError('Username already exists');
                return;
            }
            
            // Create new user
            const passwordHash = await this.hashPassword(password);
            const newUser = new User(
                null, // ID will be auto-generated
                username,
                passwordHash,
                false, // is_admin
                false  // is_approved (requires admin approval)
            );
            
            await window.Database.saveUser(newUser);
            
            this.showRegisterSuccess('Registration successful! Your account is pending admin approval. You will be notified when activated.');
            
            // Clear form
            $('#register-form')[0].reset();
            
        } catch (error) {
            console.error('❌ Registration error:', error);
            this.showRegisterError('Registration failed. Please try again.');
        } finally {
            $('#register-submit').prop('disabled', false).html('<i class="bi bi-person-plus"></i> Register (Pending Approval)');
        }
    }

    validateRegistration(username, password, confirmPassword) {
        if (username.length < this.config.MIN_USERNAME_LENGTH) {
            return { valid: false, message: `Username must be at least ${this.config.MIN_USERNAME_LENGTH} characters` };
        }
        
        if (username.length > this.config.MAX_USERNAME_LENGTH) {
            return { valid: false, message: `Username must be no more than ${this.config.MAX_USERNAME_LENGTH} characters` };
        }
        
        if (password.length < this.config.MIN_PASSWORD_LENGTH) {
            return { valid: false, message: `Password must be at least ${this.config.MIN_PASSWORD_LENGTH} characters` };
        }
        
        if (password.length > this.config.MAX_PASSWORD_LENGTH) {
            return { valid: false, message: `Password must be no more than ${this.config.MAX_PASSWORD_LENGTH} characters` };
        }
        
        if (password !== confirmPassword) {
            return { valid: false, message: 'Passwords do not match' };
        }
        
        if (!/^[a-zA-Z0-9_-]+$/.test(username)) {
            return { valid: false, message: 'Username can only contain letters, numbers, underscore and dash' };
        }
        
        return { valid: true };
    }

    async logout() {
        try {
            console.log('🚪 Logging out user');
            
            // Clear session
            this.session.clearSession();
            
            // Update app state
            this.app.currentUser = null;
            this.app.updateNavigation();
            
            // Navigate to login
            this.app.navigate('login');
            
            // Show message
            this.app.showFlashMessage('Logged out successfully', 'success');
            
        } catch (error) {
            console.error('❌ Logout error:', error);
            this.app.showFlashMessage('Logout error', 'error');
        }
    }

    async getCurrentUser() {
        return this.session.getCurrentUser();
    }

    generateCsrfToken() {
        return this.session.generateCsrfToken();
    }

    async hashPassword(password) {
        return await window.AppInit.hashPassword(password);
    }

    async verifyPassword(password, hash) {
        return await window.AppInit.verifyPassword(password, hash);
    }

    showLoginError(message) {
        $('#login-error-text').text(message);
        $('#login-error').removeClass('d-none');
        
        // Auto-hide after 5 seconds
        setTimeout(() => {
            $('#login-error').addClass('d-none');
        }, 5000);
    }

    showRegisterError(message) {
        $('#register-error-text').text(message);
        $('#register-error').removeClass('d-none');
        $('#register-success').addClass('d-none');
        
        // Auto-hide after 5 seconds
        setTimeout(() => {
            $('#register-error').addClass('d-none');
        }, 5000);
    }

    showRegisterSuccess(message) {
        $('#register-success-text').text(message);
        $('#register-success').removeClass('d-none');
        $('#register-error').addClass('d-none');
    }

    // Utility methods
    isAuthenticated() {
        return this.session.isAuthenticated();
    }

    requireAuth() {
        if (!this.isAuthenticated()) {
            this.app.showFlashMessage('Please log in to access this page', 'warning');
            this.app.navigate('login');
            return false;
        }
        return true;
    }

    requireAdmin() {
        if (!this.requireAuth()) {
            return false;
        }
        
        const user = this.getCurrentUser();
        if (!user || !user.is_admin) {
            this.app.showFlashMessage('Admin access required', 'danger');
            this.app.navigate('chat');
            return false;
        }
        
        return true;
    }
}

// Make available globally
window.AuthModule = AuthModule;

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AuthModule;
}