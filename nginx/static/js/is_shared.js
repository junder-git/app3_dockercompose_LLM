// =============================================================================
// nginx/static/js/is_shared.js - SHARED FUNCTIONALITY ACROSS ALL USER TYPES
// =============================================================================

// =============================================================================
// MARKDOWN SETUP - SIMPLE CONFIGURATION
// =============================================================================

// Enhanced marked.js setup
function setupMarkedWithFormatting() {
    if (!window.marked) return;
    
    // Configure marked with better options
    marked.setOptions({
        breaks: true,           // Convert \n to <br>
        gfm: true,             // GitHub Flavored Markdown
        headerIds: false,      // Don't add IDs to headers
        mangle: false,         // Don't mangle text
        sanitize: false,       // Don't sanitize HTML
        smartLists: true,      // Better list formatting
        smartypants: false,    // Don't convert quotes/dashes
        xhtml: false           // Don't close tags
    });
}

// =============================================================================
// SHARED CHAT FUNCTIONALITY - SSE HANDLING, UI HELPERS, ETC.
// =============================================================================

// Shared Chat Base Class - Contains common functionality for all chat systems
class SharedChatBase {
    constructor() {
        this.isTyping = false;
        this.abortController = null;
        this.messageCount = 0;
    }

    // =============================================================================
    // SHARED EVENT LISTENERS SETUP
    // =============================================================================
    setupEventListeners() {
        // Prevent form submission from refreshing page
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.sendMessage();
                return false;
            });
        }

        const stopButton = document.getElementById('stop-button');
        if (stopButton) {
            stopButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.stopGeneration();
            });
        }

        const clearButton = document.getElementById('clear-chat');
        if (clearButton) {
            clearButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.clearChat();
            });
        }
        
        // Proper Enter key handling for textarea
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            // Handle input changes for character count and auto-resize
            textarea.addEventListener('input', (e) => {
                this.updateCharCount();
                this.autoResizeTextarea();
            });
            
            // Enter key handling
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    if (e.shiftKey) {
                        // Shift+Enter: Allow new line
                        return;
                    } else {
                        // Enter only: Send message
                        e.preventDefault();
                        e.stopPropagation();
                        
                        if (textarea.value.trim()) {
                            this.sendMessage();
                        }
                        return false;
                    }
                }
            });

            // Auto-resize on load
            this.autoResizeTextarea();
        }

        // Send button click handler
        const sendButton = document.getElementById('send-button');
        if (sendButton) {
            sendButton.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                
                const textarea = document.getElementById('chat-input');
                if (textarea && textarea.value.trim()) {
                    this.sendMessage();
                }
                return false;
            });
        }
    }

    setupSuggestionChips() {
        document.querySelectorAll('.suggestion-chip').forEach(chip => {
            chip.addEventListener('click', (e) => {
                e.preventDefault();
                const input = document.getElementById('chat-input');
                if (input) {
                    input.value = chip.dataset.prompt;
                    input.focus();
                    this.updateCharCount();
                    this.autoResizeTextarea();
                }
            });
        });
    }

    // =============================================================================
    // SHARED UI HELPERS
    // =============================================================================
    updateCharCount() {
        const textarea = document.getElementById('chat-input');
        const countEl = document.getElementById('char-count');
        
        if (textarea && countEl) {
            const count = textarea.value.length;
            countEl.textContent = count;
        }
    }

    autoResizeTextarea() {
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.style.height = 'auto';
            
            const maxHeight = 120; // 120px max height
            const newHeight = Math.min(textarea.scrollHeight, maxHeight);
            textarea.style.height = newHeight + 'px';
            
            textarea.style.overflowY = textarea.scrollHeight > maxHeight ? 'auto' : 'hidden';
        }
    }

    updateButtons(isTyping) {
        const sendButton = document.getElementById('send-button');
        const stopButton = document.getElementById('stop-button');
        const chatInput = document.getElementById('chat-input');

        if (sendButton) {
            sendButton.style.display = isTyping ? 'none' : 'inline-flex';
            sendButton.disabled = isTyping;
        }
        if (stopButton) {
            stopButton.style.display = isTyping ? 'inline-flex' : 'none';
            stopButton.disabled = !isTyping;
        }
        if (chatInput) {
            chatInput.disabled = isTyping;
        }
    }

    stopGeneration() {
        console.log('⏹️ Stopping generation');
        if (this.abortController) {
            this.abortController.abort();
        }
        this.isTyping = false;
        this.updateButtons(false);
    }

    // =============================================================================
    // SHARED SSE STREAM PROCESSING - USED BY ALL USER TYPES
    // =============================================================================
    async processSSEStream(response, aiMessage) {
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        let processedLines = new Set();
        let accumulated = '';

        console.log('📺 Starting SSE stream processing');

        while (true) {
            const { done, value } = await reader.read();
            
            if (done) {
                console.log('✅ Stream reader finished');
                break;
            }

            const chunk = decoder.decode(value, { stream: true });
            buffer += chunk;
            
            let newlineIndex;
            while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
                const line = buffer.slice(0, newlineIndex).trim();
                buffer = buffer.slice(newlineIndex + 1);
                
                if (line === '') continue;
                
                if (processedLines.has(line)) {
                    continue;
                }
                processedLines.add(line);
                
                console.log('📦 Processing SSE line:', line);
                
                if (line.startsWith('data: ')) {
                    const jsonStr = line.slice(6).trim();
                    
                    if (jsonStr === '[DONE]') {
                        console.log('✅ Stream completed with [DONE]');
                        this.finishStreaming(aiMessage, accumulated);
                        return accumulated;
                    }

                    try {
                        const data = JSON.parse(jsonStr);
                        console.log('📊 Parsed SSE data:', data);
                        
                        if (data.type === 'content' && data.content) {
                            accumulated += data.content;
                            this.updateStreamingMessage(aiMessage, accumulated);
                            console.log('📝 Content received:', data.content);
                        }
                        
                        if (data.type === 'complete' || data.done === true) {
                            console.log('✅ Stream completed with complete flag');
                            this.finishStreaming(aiMessage, accumulated);
                            return accumulated;
                        }
                        
                        if (data.type === 'error') {
                            console.error('❌ Stream error:', data.error);
                            const errorMsg = '*Error: ' + data.error + '*';
                            this.updateStreamingMessage(aiMessage, errorMsg);
                            this.finishStreaming(aiMessage, errorMsg);
                            return errorMsg;
                        }
                        
                    } catch (parseError) {
                        console.warn('⚠️ JSON parse error:', parseError, 'for:', jsonStr);
                    }
                }
            }
            
            await new Promise(resolve => setTimeout(resolve, 1));
        }

        console.log('🏁 Stream ended without [DONE], finishing with accumulated content');
        this.finishStreaming(aiMessage, accumulated);
        return accumulated;
    }

    updateStreamingMessage(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Show raw text during streaming (no markdown processing)
            streamingEl.innerHTML = content + '<span class="cursor blink">▋</span>';
            
            const messagesContainer = document.getElementById('chat-messages');
            if (messagesContainer) {
                messagesContainer.scrollTo({
                    top: messagesContainer.scrollHeight,
                    behavior: 'smooth'
                });
            }
        }
    }

    finishStreaming(messageDiv, finalContent) {
        console.log('🏁 Finishing stream with content length:', finalContent.length);
        
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Simply process with marked.js - let it handle the formatting
            const parsedContent = window.marked ? marked.parse(finalContent) : finalContent;
            streamingEl.innerHTML = parsedContent;
            
            // Save to appropriate storage (overridden by subclasses)
            if (this.saveMessage && finalContent.trim()) {
                this.saveMessage('assistant', finalContent);
            }
        }
        
        this.isTyping = false;
        this.updateButtons(false);
        
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            messagesContainer.scrollTo({
                top: messagesContainer.scrollHeight,
                behavior: 'smooth'
            });
        }
        
        const input = document.getElementById('chat-input');
        if (input) {
            input.focus();
        }
    }

    // =============================================================================
    // SHARED MESSAGE HANDLING - OVERRIDE IN SUBCLASSES
    // =============================================================================
    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        // This should be overridden by subclasses to handle user-specific styling
        console.warn('addMessage should be overridden by subclass');
    }

    async sendMessage() {
        // This should be overridden by subclasses
        console.warn('sendMessage should be overridden by subclass');
    }

    clearChat() {
        // This should be overridden by subclasses
        console.warn('clearChat should be overridden by subclass');
    }
}

// =============================================================================
// SHARED AUTHENTICATION AND NAVIGATION - REMOVED AUTH CHECKS
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
        window.updateNavigation = this.updateNavigation.bind(this);
    }

    setupPublicFeatures() {
        this.setupAuthForms();
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

    setupEventDelegation() {
        document.addEventListener('click', (e) => {
            const action = e.target.getAttribute('data-action');
            
            switch (action) {
                case 'logout':
                    e.preventDefault();
                    this.logout();
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

    clearClientData() {
        console.log('🧹 Clearing client data...');
        
        localStorage.clear();
        sessionStorage.clear();
        
        const cookies = ['access_token', 'guest_token', 'session'];
        cookies.forEach(name => {
            document.cookie = `${name}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax`;
            document.cookie = `${name}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax; Secure`;
            document.cookie = `${name}=; Path=/; Max-Age=0; SameSite=Lax`;
        });
        
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
            const response = await fetch('/api/auth/logout', { 
                method: 'POST', 
                credentials: 'include',
                headers: { 'Content-Type': 'application/json' }
            });
            
            const data = await response.json();
            console.log('✅ Server logout successful:', data);
            
            this.clearClientData();
            this.showSuccess('Logged out successfully');
            
            setTimeout(() => {
                window.location.href = data.redirect || '/';
            }, 500);
            
        } catch (error) {
            console.warn('Server logout failed, but continuing with client logout:', error);
            
            this.clearClientData();
            
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

    updateNavigation(navHtml = null) {
        // Navigation is now handled server-side during page rendering
        // This function is kept for compatibility but does nothing
        console.log('🔄 Navigation handled server-side during page rendering');
        return Promise.resolve();
    }

    // =============================================================================
    // SHARED ALERT SYSTEM
    // =============================================================================
    showError(message) {
        this.removeExistingAlerts();
        const alert = this.createAlert('danger', 'exclamation-triangle', message);
        this.appendAlert(alert);
        
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, 5000);
    }

    showSuccess(message) {
        this.removeExistingAlerts();
        const alert = this.createAlert('success', 'check-circle', message);
        this.appendAlert(alert);
        
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, 3000);
    }

    showInfo(message) {
        this.removeExistingAlerts();
        const alert = this.createAlert('info', 'info-circle', message);
        this.appendAlert(alert);
        
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, 4000);
    }

    showWarning(message) {
        this.removeExistingAlerts();
        const alert = this.createAlert('warning', 'exclamation-triangle', message);
        this.appendAlert(alert);
        
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, 4000);
    }

    createAlert(type, icon, message) {
        const alert = document.createElement('div');
        alert.className = `alert alert-${type} alert-dismissible fade show`;
        alert.innerHTML = `
            <i class="bi bi-${icon}"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        return alert;
    }

    appendAlert(alert) {
        const container = document.getElementById('alert-container') || document.body;
        if (container === document.body) {
            container.insertBefore(alert, container.firstChild);
        } else {
            container.appendChild(alert);
        }
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
// SHARED MODAL UTILITIES
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

    static removeModal(id) {
        const modal = document.getElementById(id);
        if (modal) {
            const bsModal = bootstrap.Modal.getInstance(modal);
            if (bsModal) {
                bsModal.hide();
            }
            setTimeout(() => {
                modal.remove();
            }, 500);
        }
    }
}

// =============================================================================
// AUTO-INITIALIZATION
// =============================================================================

let sharedInterface = null;

document.addEventListener('DOMContentLoaded', () => {
    console.log('🚀 Initializing shared interface...');
    
    // Initialize markdown formatting
    setupMarkedWithFormatting();
    
    // Single initialization point
    sharedInterface = new SharedInterface();
    
    // Make available globally for debugging
    window.sharedInterface = sharedInterface;
    window.SharedChatBase = SharedChatBase;
    window.SharedModalUtils = SharedModalUtils;
    
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
    
    console.log('✅ Shared interface initialized successfully');
});

// Handle page visibility changes
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
        console.log('👁️ Page became visible');
        // No need to check auth - handled server-side
    }
});

// Handle browser back/forward navigation
window.addEventListener('popstate', () => {
    console.log('🔄 Browser navigation detected');
    // Navigation is handled server-side during page load
});

// Handle online/offline status
window.addEventListener('online', () => {
    if (sharedInterface) {
        console.log('🌐 Connection restored');
        sharedInterface.showInfo('Connection restored');
    }
});

window.addEventListener('offline', () => {
    if (sharedInterface) {
        console.log('📴 Connection lost');
        sharedInterface.showError('Connection lost - some features may not work');
    }
});

// Global error handler for unhandled promises
window.addEventListener('unhandledrejection', (event) => {
    console.error('Unhandled promise rejection:', event.reason);
    if (sharedInterface) {
        sharedInterface.showError('An unexpected error occurred');
    }
});

// Auto-resize textarea functionality for all pages
document.addEventListener('DOMContentLoaded', () => {
    const chatInput = document.getElementById('chat-input');
    if (chatInput) {
        chatInput.addEventListener('input', function() {
            this.style.height = '';
            this.style.height = this.scrollHeight + 'px';
        });
    }
});