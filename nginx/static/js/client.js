// nginx/static/js/client.js - All client-side JavaScript functionality

window.DevstralClient = (function() {
    'use strict';

    // Configuration
    const config = {
        MAX_PENDING_USERS: 2,
        MIN_USERNAME_LENGTH: 3,
        MAX_USERNAME_LENGTH: 50,
        MIN_PASSWORD_LENGTH: 6,
        MAX_MESSAGE_LENGTH: 5000
    };

    // =============================================================================
    // AUTO-INITIALIZATION BASED ON PAGE
    // =============================================================================

    function autoInit() {
        const path = window.location.pathname;
        
        switch (path) {
            case '/':
                initIndex();
                break;
            case '/login':
                initLogin();
                break;
            case '/register':
                initRegister();
                break;
            case '/chat':
                initChat();
                break;
            case '/admin':
                initAdmin();
                break;
            default:
                console.log('No specific initialization for path:', path);
        }
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    function showFlashMessage(message, type = 'info') {
        const alertClass = {
            'success': 'alert-success',
            'error': 'alert-danger',
            'warning': 'alert-warning',
            'info': 'alert-info'
        }[type] || 'alert-info';
        
        const icon = {
            'success': 'bi-check-circle',
            'error': 'bi-exclamation-triangle',
            'warning': 'bi-exclamation-triangle',
            'info': 'bi-info-circle'
        }[type] || 'bi-info-circle';
        
        const alert = $(`
            <div class="alert ${alertClass} alert-dismissible fade show" role="alert">
                <i class="bi ${icon}"></i> ${escapeHtml(message)}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        `);
        
        $('#flash-messages').append(alert);
        setTimeout(() => alert.alert('close'), 5000);
    }

    function escapeHtml(text) {
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#x27;'
        };
        
        return String(text).replace(/[&<>"']/g, function(m) {
            return map[m];
        });
    }

    function getAuthToken() {
        return localStorage.getItem('auth_token') || '';
    }

    function setAuthToken(token) {
        if (token) {
            localStorage.setItem('auth_token', token);
        } else {
            localStorage.removeItem('auth_token');
        }
    }

    function logout() {
        setAuthToken(null);
        window.location.href = '/';
    }

    // =============================================================================
    // AUTH FUNCTIONS
    // =============================================================================

    function checkAuth() {
        const token = getAuthToken();
        if (!token) return Promise.resolve(false);

        return fetch('/api/auth/verify', {
            headers: {
                'Authorization': 'Bearer ' + token
            }
        })
        .then(response => {
            if (response.ok) {
                return response.json().then(data => data.user);
            }
            return false;
        })
        .catch(() => false);
    }

    function login(username, password) {
        return fetch('/api/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                username: username,
                password: password
            })
        })
        .then(response => response.json())
        .then(data => {
            if (data.token) {
                setAuthToken(data.token);
                return { success: true, user: data.user };
            } else {
                return { success: false, error: data.error || 'Login failed' };
            }
        });
    }

    function register(username, password) {
        return fetch('/api/auth/register', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                username: username,
                password: password
            })
        })
        .then(response => response.json());
    }

    // =============================================================================
    // CHAT FUNCTIONS
    // =============================================================================

    let isStreaming = false;
    let currentStreamingMessage = null;

    function sendMessage(message) {
        if (isStreaming) {
            showFlashMessage('Please wait for the current response to complete', 'warning');
            return;
        }

        if (!message.trim()) {
            showFlashMessage('Please enter a message', 'warning');
            return;
        }

        // Add user message to chat
        addMessageToChat(message, 'user');

        // Clear input
        $('#message-input').val('');

        // Show typing indicator
        const typingId = addTypingIndicator();

        // Send to API
        isStreaming = true;
        $('#send-btn').prop('disabled', true).html('<i class="bi bi-hourglass-split"></i>');

        fetch('/api/ollama/api/chat', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + getAuthToken()
            },
            body: JSON.stringify({
                model: 'devstral',
                messages: [
                    {
                        role: 'user',
                        content: message
                    }
                ],
                stream: true
            })
        })
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }

            // Remove typing indicator
            removeTypingIndicator(typingId);

            // Start streaming response
            currentStreamingMessage = addMessageToChat('', 'assistant');
            return handleStreamingResponse(response);
        })
        .catch(error => {
            removeTypingIndicator(typingId);
            showFlashMessage('Error sending message: ' + error.message, 'error');
            console.error('Chat error:', error);
        })
        .finally(() => {
            isStreaming = false;
            currentStreamingMessage = null;
            $('#send-btn').prop('disabled', false).html('<i class="bi bi-send"></i>');
        });
    }

    function handleStreamingResponse(response) {
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';

        function processStream() {
            return reader.read().then(({ done, value }) => {
                if (done) {
                    return;
                }

                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split('\n');
                buffer = lines.pop(); // Keep incomplete line in buffer

                for (const line of lines) {
                    if (line.trim()) {
                        try {
                            const data = JSON.parse(line);
                            if (data.message && data.message.content) {
                                appendToStreamingMessage(data.message.content);
                            }
                            if (data.done) {
                                return; // Stream complete
                            }
                        } catch (e) {
                            console.warn('Failed to parse streaming response:', line);
                        }
                    }
                }

                return processStream();
            });
        }

        return processStream();
    }

    function addMessageToChat(content, role) {
        const timestamp = new Date().toLocaleTimeString();
        const messageClass = role === 'user' ? 'user-message' : 'assistant-message';
        
        const messageId = 'msg-' + Date.now();
        const messageHtml = `
            <div id="${messageId}" class="message ${messageClass}">
                <div class="message-content">
                    ${role === 'user' ? escapeHtml(content) : renderMarkdown(content)}
                </div>
                <span class="message-timestamp">${timestamp}</span>
            </div>
        `;
        
        $('#chat-messages').append(messageHtml);
        scrollToBottom();
        
        return messageId;
    }

    function appendToStreamingMessage(content) {
        if (!currentStreamingMessage) return;

        const $message = $('#' + currentStreamingMessage);
        const $content = $message.find('.message-content');
        const currentText = $content.data('raw-content') || '';
        const newText = currentText + content;
        
        $content.data('raw-content', newText);
        $content.html(renderMarkdown(newText));
        
        scrollToBottom();
    }

    function addTypingIndicator() {
        const typingId = 'typing-' + Date.now();
        const typingHtml = `
            <div id="${typingId}" class="message assistant-message">
                <div class="message-content">
                    <div class="typing-indicator">
                        <span></span>
                        <span></span>
                        <span></span>
                    </div>
                </div>
            </div>
        `;
        
        $('#chat-messages').append(typingHtml);
        scrollToBottom();
        
        return typingId;
    }

    function removeTypingIndicator(typingId) {
        $('#' + typingId).remove();
    }

    function scrollToBottom() {
        const $messages = $('#chat-messages');
        $messages.scrollTop($messages[0].scrollHeight);
    }

    // Simple markdown rendering
    function renderMarkdown(text) {
        if (!text) return '';
        
        // Escape HTML first
        let html = escapeHtml(text);
        
        // Bold **text**
        html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        
        // Italic *text*
        html = html.replace(/\*(.*?)\*/g, '<em>$1</em>');
        
        // Code blocks ```code```
        html = html.replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
        
        // Inline code `code`
        html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
        
        // Line breaks
        html = html.replace(/\n/g, '<br>');
        
        return html;
    }

    // =============================================================================
    // PAGE INITIALIZATION FUNCTIONS
    // =============================================================================

    function initIndex() {
        console.log('🏠 Index page loaded');
        
        // Check if user is already authenticated
        checkAuth().then(user => {
            if (user) {
                // User is authenticated, update nav links
                $('#nav-links').html(`
                    <a class="nav-link" href="/chat">
                        <i class="bi bi-chat-dots"></i> Chat
                    </a>
                    <a class="nav-link" href="#" onclick="DevstralClient.logout()">
                        <i class="bi bi-box-arrow-right"></i> Logout
                    </a>
                `);
                
                // Update action buttons
                $('.text-center').last().html(`
                    <a href="/chat" class="btn btn-primary btn-lg">
                        <i class="bi bi-chat-dots"></i> Continue Chatting
                    </a>
                `);
            }
        }).catch(error => {
            console.log('Not authenticated, showing default options');
        });
    }

    function initLogin() {
        console.log('🔐 Login page loaded');
        
        // Check if already authenticated
        checkAuth().then(user => {
            if (user) {
                window.location.href = '/chat';
            }
        });
        
        // Handle login form submission
        $('#loginForm').on('submit', function(e) {
            e.preventDefault();
            
            const username = $('#username').val().trim();
            const password = $('#password').val();
            
            if (!username || !password) {
                showFlashMessage('Username and password are required', 'error');
                return;
            }
            
            // Disable form
            $('#login-btn').prop('disabled', true).html('<i class="bi bi-hourglass-split"></i> Logging in...');
            
            // Attempt login
            login(username, password).then(result => {
                if (result.success) {
                    showFlashMessage('Login successful! Redirecting...', 'success');
                    setTimeout(() => {
                        window.location.href = '/chat';
                    }, 1000);
                } else {
                    showFlashMessage(result.error, 'error');
                    $('#login-btn').prop('disabled', false).html('<i class="bi bi-box-arrow-in-right"></i> Login');
                }
            }).catch(error => {
                console.error('Login error:', error);
                showFlashMessage('Login failed: ' + error.message, 'error');
                $('#login-btn').prop('disabled', false).html('<i class="bi bi-box-arrow-in-right"></i> Login');
            });
        });
    }

    function initRegister() {
        console.log('📝 Register page loaded');
        
        // Check if already authenticated
        checkAuth().then(user => {
            if (user) {
                window.location.href = '/chat';
            }
        });
        
        // Show registration form
        showRegistrationForm();
        
        function showRegistrationForm() {
            $('#registration-info').html(`
                <div class="alert alert-info" role="alert">
                    <i class="bi bi-info-circle"></i> 
                    <strong>Registration requires admin approval.</strong><br>
                    After registering, please wait for an administrator to approve your account before you can log in.
                </div>
            `);
            
            $('#registerForm').show();
            setupFormValidation();
        }
        
        function setupFormValidation() {
            // Password confirmation validation
            $('#confirmPassword').on('input', function() {
                const password = $('#password').val();
                const confirmPassword = $(this).val();
                
                if (confirmPassword && password !== confirmPassword) {
                    $(this).addClass('is-invalid');
                } else if (confirmPassword) {
                    $(this).removeClass('is-invalid').addClass('is-valid');
                }
            });
            
            // Form submission
            $('#registerForm').on('submit', function(e) {
                e.preventDefault();
                handleRegistration();
            });
        }
        
        function handleRegistration() {
            const username = $('#username').val().trim();
            const password = $('#password').val();
            const confirmPassword = $('#confirmPassword').val();
            
            // Basic validation
            if (!username || username.length < config.MIN_USERNAME_LENGTH) {
                showFlashMessage(`Username must be at least ${config.MIN_USERNAME_LENGTH} characters`, 'error');
                return;
            }
            
            if (!password || password.length < config.MIN_PASSWORD_LENGTH) {
                showFlashMessage(`Password must be at least ${config.MIN_PASSWORD_LENGTH} characters`, 'error');
                return;
            }
            
            if (password !== confirmPassword) {
                showFlashMessage('Passwords do not match', 'error');
                return;
            }
            
            // Disable form
            $('#register-btn').prop('disabled', true).html('<i class="bi bi-hourglass-split"></i> Registering...');
            
            // Attempt registration
            register(username, password).then(data => {
                if (data.success) {
                    showFlashMessage('Registration successful! Your account is pending admin approval.', 'success');
                    
                    // Clear form
                    $('#registerForm')[0].reset();
                    $('.is-valid, .is-invalid').removeClass('is-valid is-invalid');
                } else {
                    showFlashMessage(data.error || 'Registration failed', 'error');
                }
            }).catch(error => {
                console.error('Registration error:', error);
                showFlashMessage('Registration failed: ' + error.message, 'error');
            }).finally(() => {
                $('#register-btn').prop('disabled', false).html('<i class="bi bi-person-plus"></i> Register (Pending Approval)');
            });
        }
    }

    function initChat() {
        console.log('💬 Chat page loaded');
        
        // Check authentication
        checkAuth().then(user => {
            if (!user) {
                window.location.href = '/login';
                return;
            }
            
            // Update user info in navbar
            $('#username-display').text(user.username);
            
            // Setup chat interface
            setupChatInterface();
            
        }).catch(error => {
            console.error('Auth check failed:', error);
            window.location.href = '/login';
        });
        
        function setupChatInterface() {
            // Handle message input
            $('#message-input').on('keydown', function(e) {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    const message = $(this).val().trim();
                    if (message) {
                        sendMessage(message);
                    }
                }
            });
            
            // Handle send button
            $('#send-btn').on('click', function() {
                const message = $('#message-input').val().trim();
                if (message) {
                    sendMessage(message);
                }
            });
            
            // Auto-resize textarea
            $('#message-input').on('input', function() {
                this.style.height = 'auto';
                this.style.height = Math.min(this.scrollHeight, 150) + 'px';
            });
            
            // Focus on input
            $('#message-input').focus();
        }
    }

    function initAdmin() {
        console.log('👑 Admin page loaded');
        
        // Check authentication and admin status
        checkAuth().then(user => {
            if (!user) {
                window.location.href = '/login';
                return;
            }
            
            if (!user.isAdmin) {
                window.location.href = '/unauthorized.html';
                return;
            }
            
            // Setup admin interface
            setupAdminInterface();
            
        }).catch(error => {
            console.error('Auth check failed:', error);
            window.location.href = '/login';
        });
        
        function setupAdminInterface() {
            // TODO: Implement admin functionality
            $('#app-content').html(`
                <div class="row">
                    <div class="col-12">
                        <h2><i class="bi bi-gear"></i> Admin Dashboard</h2>
                        <p>Admin functionality is being implemented...</p>
                    </div>
                </div>
            `);
        }
    }

    // =============================================================================
    // PUBLIC API
    // =============================================================================

    return {
        // Utility functions
        showFlashMessage: showFlashMessage,
        logout: logout,
        
        // Page initialization
        initIndex: initIndex,
        initLogin: initLogin,
        initRegister: initRegister,
        initChat: initChat,
        initAdmin: initAdmin,
        
        // Auth functions
        checkAuth: checkAuth,
        login: login,
        register: register,
        
        // Chat functions
        sendMessage: sendMessage
    };

})();

// Global logout function for navbar
window.logout = DevstralClient.logout;

// Auto-initialize when DOM is ready
$(document).ready(function() {
    DevstralClient.autoInit();
});

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    function showFlashMessage(message, type = 'info') {
        const alertClass = {
            'success': 'alert-success',
            'error': 'alert-danger',
            'warning': 'alert-warning',
            'info': 'alert-info'
        }[type] || 'alert-info';
        
        const icon = {
            'success': 'bi-check-circle',
            'error': 'bi-exclamation-triangle',
            'warning': 'bi-exclamation-triangle',
            'info': 'bi-info-circle'
        }[type] || 'bi-info-circle';
        
        const alert = $(`
            <div class="alert ${alertClass} alert-dismissible fade show" role="alert">
                <i class="bi ${icon}"></i> ${escapeHtml(message)}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        `);
        
        $('#flash-messages').append(alert);
        setTimeout(() => alert.alert('close'), 5000);
    }

    function escapeHtml(text) {
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#x27;'
        };
        
        return String(text).replace(/[&<>"']/g, function(m) {
            return map[m];
        });
    }

    function getAuthToken() {
        return localStorage.getItem('auth_token') || '';
    }

    function setAuthToken(token) {
        if (token) {
            localStorage.setItem('auth_token', token);
        } else {
            localStorage.removeItem('auth_token');
        }
    }

    function logout() {
        setAuthToken(null);
        window.location.href = '/';
    }

    // =============================================================================
    // AUTH FUNCTIONS
    // =============================================================================

    function checkAuth() {
        const token = getAuthToken();
        if (!token) return Promise.resolve(false);

        return fetch('/api/auth/verify', {
            headers: {
                'Authorization': 'Bearer ' + token
            }
        })
        .then(response => {
            if (response.ok) {
                return response.json().then(data => data.user);
            }
            return false;
        })
        .catch(() => false);
    }

    function login(username, password) {
        return fetch('/api/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                username: username,
                password: password
            })
        })
        .then(response => response.json())
        .then(data => {
            if (data.token) {
                setAuthToken(data.token);
                return { success: true, user: data.user };
            } else {
                return { success: false, error: data.error || 'Login failed' };
            }
        });
    }

    function register(username, password) {
        return fetch('/api/auth/register', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                username: username,
                password: password
            })
        })
        .then(response => response.json());
    }

    // =============================================================================
    // CHAT FUNCTIONS
    // =============================================================================

    let isStreaming = false;
    let currentStreamingMessage = null;

    function sendMessage(message) {
        if (isStreaming) {
            showFlashMessage('Please wait for the current response to complete', 'warning');
            return;
        }

        if (!message.trim()) {
            showFlashMessage('Please enter a message', 'warning');
            return;
        }

        // Add user message to chat
        addMessageToChat(message, 'user');

        // Clear input
        $('#message-input').val('');

        // Show typing indicator
        const typingId = addTypingIndicator();

        // Send to API
        isStreaming = true;
        $('#send-btn').prop('disabled', true).html('<i class="bi bi-hourglass-split"></i>');

        fetch('/api/ollama/api/chat', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + getAuthToken()
            },
            body: JSON.stringify({
                model: 'devstral',
                messages: [
                    {
                        role: 'user',
                        content: message
                    }
                ],
                stream: true
            })
        })
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }

            // Remove typing indicator
            removeTypingIndicator(typingId);

            // Start streaming response
            currentStreamingMessage = addMessageToChat('', 'assistant');
            return handleStreamingResponse(response);
        })
        .catch(error => {
            removeTypingIndicator(typingId);
            showFlashMessage('Error sending message: ' + error.message, 'error');
            console.error('Chat error:', error);
        })
        .finally(() => {
            isStreaming = false;
            currentStreamingMessage = null;
            $('#send-btn').prop('disabled', false).html('<i class="bi bi-send"></i>');
        });
    }

    function handleStreamingResponse(response) {
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';

        function processStream() {
            return reader.read().then(({ done, value }) => {
                if (done) {
                    return;
                }

                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split('\n');
                buffer = lines.pop(); // Keep incomplete line in buffer

                for (const line of lines) {
                    if (line.trim()) {
                        try {
                            const data = JSON.parse(line);
                            if (data.message && data.message.content) {
                                appendToStreamingMessage(data.message.content);
                            }
                            if (data.done) {
                                return; // Stream complete
                            }
                        } catch (e) {
                            console.warn('Failed to parse streaming response:', line);
                        }
                    }
                }

                return processStream();
            });
        }

        return processStream();
    }

    function addMessageToChat(content, role) {
        const timestamp = new Date().toLocaleTimeString();
        const messageClass = role === 'user' ? 'user-message' : 'assistant-message';
        
        const messageId = 'msg-' + Date.now();
        const messageHtml = `
            <div id="${messageId}" class="message ${messageClass}">
                <div class="message-content">
                    ${role === 'user' ? escapeHtml(content) : renderMarkdown(content)}
                </div>
                <span class="message-timestamp">${timestamp}</span>
            </div>
        `;
        
        $('#chat-messages').append(messageHtml);
        scrollToBottom();
        
        return messageId;
    }

    function appendToStreamingMessage(content) {
        if (!currentStreamingMessage) return;

        const $message = $('#' + currentStreamingMessage);
        const $content = $message.find('.message-content');
        const currentText = $content.data('raw-content') || '';
        const newText = currentText + content;
        
        $content.data('raw-content', newText);
        $content.html(renderMarkdown(newText));
        
        scrollToBottom();
    }

    function addTypingIndicator() {
        const typingId = 'typing-' + Date.now();
        const typingHtml = `
            <div id="${typingId}" class="message assistant-message">
                <div class="message-content">
                    <div class="typing-indicator">
                        <span></span>
                        <span></span>
                        <span></span>
                    </div>
                </div>
            </div>
        `;
        
        $('#chat-messages').append(typingHtml);
        scrollToBottom();
        
        return typingId;
    }

    function removeTypingIndicator(typingId) {
        $('#' + typingId).remove();
    }

    function scrollToBottom() {
        const $messages = $('#chat-messages');
        $messages.scrollTop($messages[0].scrollHeight);
    }

    // Simple markdown rendering
    function renderMarkdown(text) {
        if (!text) return '';
        
        // Escape HTML first
        let html = escapeHtml(text);
        
        // Bold **text**
        html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        
        // Italic *text*
        html = html.replace(/\*(.*?)\*/g, '<em>$1</em>');
        
        // Code blocks ```code```
        html = html.replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
        
        // Inline code `code`
        html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
        
        // Line breaks
        html = html.replace(/\n/g, '<br>');
        
        return html;
    }

    // =============================================================================
    // PAGE INITIALIZATION FUNCTIONS
    // =============================================================================

    function initIndex() {
        console.log('🏠 Index page loaded');
        
        // Check if user is already authenticated
        checkAuth().then(user => {
            if (user) {
                // User is authenticated, update nav links
                $('#nav-links').html(`
                    <a class="nav-link" href="/chat">
                        <i class="bi bi-chat-dots"></i> Chat
                    </a>
                    <a class="nav-link" href="#" onclick="DevstralClient.logout()">
                        <i class="bi bi-box-arrow-right"></i> Logout
                    </a>
                `);
                
                // Update action buttons
                $('.text-center').last().html(`
                    <a href="/chat" class="btn btn-primary btn-lg">
                        <i class="bi bi-chat-dots"></i> Continue Chatting
                    </a>
                `);
            }
        }).catch(error => {
            console.log('Not authenticated, showing default options');
        });
    }

    function initLogin() {
        console.log('🔐 Login page loaded');
        
        // Check if already authenticated
        checkAuth().then(user => {
            if (user) {
                window.location.href = '/chat';
            }
        });
        
        // Handle login form submission
        $('#loginForm').on('submit', function(e) {
            e.preventDefault();
            
            const username = $('#username').val().trim();
            const password = $('#password').val();
            
            if (!username || !password) {
                showFlashMessage('Username and password are required', 'error');
                return;
            }
            
            // Disable form
            $('#login-btn').prop('disabled', true).html('<i class="bi bi-hourglass-split"></i> Logging in...');
            
            // Attempt login
            login(username, password).then(result => {
                if (result.success) {
                    showFlashMessage('Login successful! Redirecting...', 'success');
                    setTimeout(() => {
                        window.location.href = '/chat';
                    }, 1000);
                } else {
                    showFlashMessage(result.error, 'error');
                    $('#login-btn').prop('disabled', false).html('<i class="bi bi-box-arrow-in-right"></i> Login');
                }
            }).catch(error => {
                console.error('Login error:', error);
                showFlashMessage('Login failed: ' + error.message, 'error');
                $('#login-btn').prop('disabled', false).html('<i class="bi bi-box-arrow-in-right"></i> Login');
            });
        });
    }

    function initRegister() {
        console.log('📝 Register page loaded');
        
        // Check if already authenticated
        checkAuth().then(user => {
            if (user) {
                window.location.href = '/chat';
            }
        });
        
        // Show registration form
        showRegistrationForm();
        
        function showRegistrationForm() {
            $('#registration-info').html(`
                <div class="alert alert-info" role="alert">
                    <i class="bi bi-info-circle"></i> 
                    <strong>Registration requires admin approval.</strong><br>
                    After registering, please wait for an administrator to approve your account before you can log in.
                </div>
            `);
            
            $('#registerForm').show();
            setupFormValidation();
        }
        
        function setupFormValidation() {
            // Password confirmation validation
            $('#confirmPassword').on('input', function() {
                const password = $('#password').val();
                const confirmPassword = $(this).val();
                
                if (confirmPassword && password !== confirmPassword) {
                    $(this).addClass('is-invalid');
                } else if (confirmPassword) {
                    $(this).removeClass('is-invalid').addClass('is-valid');
                }
            });
            
            // Form submission
            $('#registerForm').on('submit', function(e) {
                e.preventDefault();
                handleRegistration();
            });
        }
        
        function handleRegistration() {
            const username = $('#username').val().trim();
            const password = $('#password').val();
            const confirmPassword = $('#confirmPassword').val();
            
            // Basic validation
            if (!username || username.length < config.MIN_USERNAME_LENGTH) {
                showFlashMessage(`Username must be at least ${config.MIN_USERNAME_LENGTH} characters`, 'error');
                return;
            }
            
            if (!password || password.length < config.MIN_PASSWORD_LENGTH) {
                showFlashMessage(`Password must be at least ${config.MIN_PASSWORD_LENGTH} characters`, 'error');
                return;
            }
            
            if (password !== confirmPassword) {
                showFlashMessage('Passwords do not match', 'error');
                return;
            }
            
            // Disable form
            $('#register-btn').prop('disabled', true).html('<i class="bi bi-hourglass-split"></i> Registering...');
            
            // Attempt registration
            register(username, password).then(data => {
                if (data.success) {
                    showFlashMessage('Registration successful! Your account is pending admin approval.', 'success');
                    
                    // Clear form
                    $('#registerForm')[0].reset();
                    $('.is-valid, .is-invalid').removeClass('is-valid is-invalid');
                } else {
                    showFlashMessage(data.error || 'Registration failed', 'error');
                }
            }).catch(error => {
                console.error('Registration error:', error);
                showFlashMessage('Registration failed: ' + error.message, 'error');
            }).finally(() => {
                $('#register-btn').prop('disabled', false).html('<i class="bi bi-person-plus"></i> Register (Pending Approval)');
            });
        }
    }

    function initChat() {
        console.log('💬 Chat page loaded');
        
        // Check authentication
        checkAuth().then(user => {
            if (!user) {
                window.location.href = '/login';
                return;
            }
            
            // Update user info in navbar
            $('#username-display').text(user.username);
            
            // Setup chat interface
            setupChatInterface();
            
        }).catch(error => {
            console.error('Auth check failed:', error);
            window.location.href = '/login';
        });
        
        function setupChatInterface() {
            // Handle message input
            $('#message-input').on('keydown', function(e) {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    const message = $(this).val().trim();
                    if (message) {
                        sendMessage(message);
                    }
                }
            });
            
            // Handle send button
            $('#send-btn').on('click', function() {
                const message = $('#message-input').val().trim();
                if (message) {
                    sendMessage(message);
                }
            });
            
            // Auto-resize textarea
            $('#message-input').on('input', function() {
                this.style.height = 'auto';
                this.style.height = Math.min(this.scrollHeight, 150) + 'px';
            });
            
            // Focus on input
            $('#message-input').focus();
        }
    }

    function initAdmin() {
        console.log('👑 Admin page loaded');
        
        // Check authentication and admin status
        checkAuth().then(user => {
            if (!user) {
                window.location.href = '/login';
                return;
            }
            
            if (!user.isAdmin) {
                window.location.href = '/unauthorized.html';
                return;
            }
            
            // Setup admin interface
            setupAdminInterface();
            
        }).catch(error => {
            console.error('Auth check failed:', error);
            window.location.href = '/login';
        });
        
        function setupAdminInterface() {
            // TODO: Implement admin functionality
            $('#app-content').html(`
                <div class="row">
                    <div class="col-12">
                        <h2><i class="bi bi-gear"></i> Admin Dashboard</h2>
                        <p>Admin functionality is being implemented...</p>
                    </div>
                </div>
            `);
        }
    }

    // =============================================================================
    // PUBLIC API
    // =============================================================================

    return {
        // Utility functions
        showFlashMessage: showFlashMessage,
        logout: logout,
        
        // Page initialization
        initIndex: initIndex,
        initLogin: initLogin,
        initRegister: initRegister,
        initChat: initChat,
        initAdmin: initAdmin,
        
        // Auth functions
        checkAuth: checkAuth,
        login: login,
        register: register,
        
        // Chat functions
        sendMessage: sendMessage
    };

// Global logout function for navbar
window.logout = DevstralClient.logout;