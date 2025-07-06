// app.js - Main Application Controller
class DevstralApp {
    constructor() {
        this.currentUser = null;
        this.currentPage = null;
        this.initialized = false;
        this.modules = {};
        
        // Configuration from environment (set during init)
        this.config = {};
        
        console.log('📱 DevstralApp created');
    }

    async init() {
        try {
            console.log('🔧 Initializing DevstralApp...');
            
            // Show loading
            this.showLoading('Initializing system...');
            
            // Initialize database connection
            await window.Database.init();
            console.log('✅ Database initialized');
            
            // Run startup initialization (create admin user, etc.)
            await window.AppInit.runStartup();
            console.log('✅ Startup initialization complete');
            
            // Load configuration
            await this.loadConfig();
            console.log('✅ Configuration loaded');
            
            // Initialize modules
            this.initializeModules();
            console.log('✅ Modules initialized');
            
            // Set up routing
            this.setupRouting();
            console.log('✅ Routing setup');
            
            // Load initial page
            await this.loadInitialPage();
            console.log('✅ Initial page loaded');
            
            this.initialized = true;
            this.hideLoading();
            
            console.log('🎉 DevstralApp initialization complete!');
            
        } catch (error) {
            console.error('❌ DevstralApp initialization failed:', error);
            this.showError('Application failed to initialize', error.message);
        }
    }

    async loadConfig() {
        // In a real deployment, this would come from environment variables
        // For now, we'll use defaults that match the .env file
        this.config = {
            OLLAMA_URL: '/api/ollama',
            REDIS_URL: '/api/redis',
            OLLAMA_MODEL: 'devstral',
            MODEL_TEMPERATURE: 0.7,
            MODEL_MAX_TOKENS: 32,
            CHAT_HISTORY_LIMIT: 5,
            RATE_LIMIT_MAX: 100,
            SESSION_LIFETIME_DAYS: 7,
            MIN_USERNAME_LENGTH: 3,
            MAX_USERNAME_LENGTH: 50,
            MIN_PASSWORD_LENGTH: 6,
            MAX_PASSWORD_LENGTH: 128,
            MAX_MESSAGE_LENGTH: 5000
        };
    }

    initializeModules() {
        // Initialize all modules with app reference
        this.modules.auth = new window.AuthModule(this);
        this.modules.chat = new window.ChatModule(this);
        this.modules.admin = new window.AdminModule(this);
        
        console.log('📦 Modules initialized:', Object.keys(this.modules));
    }

    setupRouting() {
        // Handle browser back/forward navigation
        window.addEventListener('popstate', (event) => {
            this.handleRoute(window.location.hash);
        });
        
        // Handle initial route
        this.handleRoute(window.location.hash);
        
        // Set up navigation click handlers
        this.setupNavigation();
    }

    setupNavigation() {
        // Brand link
        $('#brand-link').on('click', (e) => {
            e.preventDefault();
            this.navigate('');
        });
        
        // Dynamic navigation will be updated by updateNavigation()
    }

    handleRoute(hash) {
        // Remove # from hash
        const route = hash.replace('#', '') || '';
        console.log('🧭 Handling route:', route);
        
        // Parse route and parameters
        const [page, ...params] = route.split('/');
        
        switch (page) {
            case '':
            case 'home':
                this.loadHomePage();
                break;
            case 'login':
                this.loadPage('login');
                break;
            case 'register':
                this.loadPage('register');
                break;
            case 'chat':
                this.loadPage('chat', params);
                break;
            case 'admin':
                this.loadPage('admin', params);
                break;
            case 'user-detail':
                this.loadPage('user-detail', params);
                break;
            default:
                this.loadPage('404');
        }
    }

    async loadInitialPage() {
        // Check if user is logged in
        this.currentUser = await this.modules.auth.getCurrentUser();
        
        if (this.currentUser) {
            console.log('👤 User logged in:', this.currentUser.username);
            // User is logged in, go to chat or current hash
            if (!window.location.hash) {
                this.navigate('chat');
            } else {
                this.handleRoute(window.location.hash);
            }
        } else {
            console.log('🚪 No user logged in');
            // User not logged in, go to login or current hash
            if (!window.location.hash || window.location.hash === '#' || window.location.hash === '#home') {
                this.navigate('login');
            } else {
                this.handleRoute(window.location.hash);
            }
        }
    }

    async loadHomePage() {
        // Redirect logic for home page
        this.currentUser = await this.modules.auth.getCurrentUser();
        
        if (this.currentUser) {
            this.navigate('chat');
        } else {
            this.navigate('login');
        }
    }

    async loadPage(pageName, params = []) {
        try {
            console.log(`📄 Loading page: ${pageName}`, params);
            
            // Check authentication for protected pages
            if (['chat', 'admin', 'user-detail'].includes(pageName)) {
                this.currentUser = await this.modules.auth.getCurrentUser();
                if (!this.currentUser) {
                    this.showFlashMessage('Please log in to access this page', 'warning');
                    this.navigate('login');
                    return;
                }
                
                // Check admin access
                if (['admin', 'user-detail'].includes(pageName) && !this.currentUser.is_admin) {
                    this.showFlashMessage('Admin access required', 'danger');
                    this.navigate('chat');
                    return;
                }
            }
            
            this.currentPage = pageName;
            this.updateNavigation();
            
            // Load page content
            switch (pageName) {
                case 'login':
                    await this.modules.auth.loadLoginPage();
                    break;
                case 'register':
                    await this.modules.auth.loadRegisterPage();
                    break;
                case 'chat':
                    await this.modules.chat.loadChatPage(params[0]); // session_id
                    break;
                case 'admin':
                    await this.modules.admin.loadAdminPage();
                    break;
                case 'user-detail':
                    await this.modules.admin.loadUserDetailPage(params[0]); // user_id
                    break;
                case '404':
                    await this.load404Page();
                    break;
                default:
                    throw new Error(`Unknown page: ${pageName}`);
            }
            
        } catch (error) {
            console.error(`❌ Error loading page ${pageName}:`, error);
            this.showError(`Failed to load ${pageName}`, error.message);
        }
    }

    updateNavigation() {
        const navHtml = this.currentUser ? this.getAuthenticatedNav() : this.getUnauthenticatedNav();
        $('#nav-links').html(navHtml);
        
        // Bind navigation events
        $('.nav-link[data-route]').on('click', (e) => {
            e.preventDefault();
            const route = $(e.target).closest('.nav-link').data('route');
            this.navigate(route);
        });
        
        // Bind logout
        $('#logout-link').on('click', async (e) => {
            e.preventDefault();
            await this.modules.auth.logout();
        });
    }

    getAuthenticatedNav() {
        const isAdmin = this.currentUser?.is_admin;
        return `
            <a class="nav-link ${this.currentPage === 'chat' ? 'active' : ''}" data-route="chat" href="#chat">
                <i class="bi bi-chat"></i> Chat
            </a>
            ${isAdmin ? `
            <a class="nav-link ${this.currentPage === 'admin' ? 'active' : ''}" data-route="admin" href="#admin">
                <i class="bi bi-shield-lock"></i> Admin
            </a>
            ` : ''}
            <span class="nav-link">
                <i class="bi bi-person-circle"></i> ${this.currentUser.username}
                ${isAdmin ? '<span class="badge bg-warning text-dark ms-1">Admin</span>' : ''}
            </span>
            <a class="nav-link" href="#" id="logout-link">
                <i class="bi bi-box-arrow-right"></i> Logout
            </a>
        `;
    }

    getUnauthenticatedNav() {
        return `
            <a class="nav-link ${this.currentPage === 'login' ? 'active' : ''}" data-route="login" href="#login">
                <i class="bi bi-box-arrow-in-right"></i> Login
            </a>
            <a class="nav-link ${this.currentPage === 'register' ? 'active' : ''}" data-route="register" href="#register">
                <i class="bi bi-person-plus"></i> Register
            </a>
        `;
    }

    async load404Page() {
        const html = `
            <div class="row justify-content-center">
                <div class="col-md-6 text-center">
                    <div class="error-page-container">
                        <div class="robot-icon">🤖</div>
                        <div class="error-code">404</div>
                        <h1 class="error-message">Page Not Found</h1>
                        <p class="error-description">
                            The page you're looking for doesn't exist or has been moved.
                        </p>
                        <div class="error-actions">
                            <button class="btn btn-primary" onclick="window.DevstralApp.navigate('')">
                                🏠 Go Home
                            </button>
                            <button class="btn btn-secondary" onclick="history.back()">
                                ← Go Back
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        $('#app-content').html(html);
    }

    navigate(route) {
        const hash = route ? `#${route}` : '';
        window.location.hash = hash;
        this.handleRoute(hash);
    }

    showLoading(message = 'Loading...') {
        $('#loading-indicator').show().find('p').text(message);
        $('#app-content').hide();
    }

    hideLoading() {
        $('#loading-indicator').hide();
        $('#app-content').show();
    }

    showFlashMessage(message, type = 'info') {
        const alertClass = type === 'error' ? 'danger' : type;
        const iconClass = {
            'success': 'check-circle',
            'danger': 'exclamation-triangle',
            'warning': 'exclamation-triangle',
            'info': 'info-circle'
        }[type] || 'info-circle';
        
        const html = `
            <div class="alert alert-${alertClass} alert-dismissible fade show">
                <i class="bi bi-${iconClass}"></i> ${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        `;
        
        $('#flash-messages').html(html);
        
        // Auto-dismiss after 5 seconds
        setTimeout(() => {
            $('#flash-messages .alert').alert('close');
        }, 5000);
    }

    showError(title, message) {
        const html = `
            <div class="row justify-content-center">
                <div class="col-md-8">
                    <div class="alert alert-danger">
                        <h4><i class="bi bi-exclamation-triangle"></i> ${title}</h4>
                        <p>${message}</p>
                        <button class="btn btn-outline-danger" onclick="window.location.reload()">
                            <i class="bi bi-arrow-clockwise"></i> Reload Page
                        </button>
                    </div>
                </div>
            </div>
        `;
        
        $('#app-content').html(html);
        this.hideLoading();
    }

    async refreshCurrentUser() {
        this.currentUser = await this.modules.auth.getCurrentUser();
        this.updateNavigation();
    }

    // Utility methods
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    generateId() {
        return 'id_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    }

    formatTimestamp(timestamp) {
        if (!timestamp) return 'Unknown';
        const date = new Date(timestamp);
        return date.toLocaleString();
    }
}

// Create global instance
window.DevstralApp = new DevstralApp();

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = DevstralApp;
}