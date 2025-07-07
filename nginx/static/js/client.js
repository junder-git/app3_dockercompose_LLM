// nginx/static/js/client.js - Pure Vanilla JavaScript (No jQuery)

window.DevstralClient = (function() {
    'use strict';

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    function $(selector) {
        return document.querySelector(selector);
    }

    function $$(selector) {
        return document.querySelectorAll(selector);
    }

    function createElement(tag, className, innerHTML) {
        var element = document.createElement(tag);
        if (className) element.className = className;
        if (innerHTML) element.innerHTML = innerHTML;
        return element;
    }

    function addClass(element, className) {
        if (element) element.classList.add(className);
    }

    function removeClass(element, className) {
        if (element) element.classList.remove(className);
    }

    function hasClass(element, className) {
        return element ? element.classList.contains(className) : false;
    }

    function on(element, event, callback) {
        if (typeof element === 'string') element = $(element);
        if (element) element.addEventListener(event, callback);
    }

    function off(element, event, callback) {
        if (typeof element === 'string') element = $(element);
        if (element) element.removeEventListener(event, callback);
    }

    function val(element, value) {
        if (typeof element === 'string') element = $(element);
        if (!element) return '';
        
        if (value !== undefined) {
            element.value = value;
            return element;
        }
        return element.value || '';
    }

    function text(element, textContent) {
        if (typeof element === 'string') element = $(element);
        if (!element) return '';
        
        if (textContent !== undefined) {
            element.textContent = textContent;
            return element;
        }
        return element.textContent || '';
    }

    function html(element, htmlContent) {
        if (typeof element === 'string') element = $(element);
        if (!element) return '';
        
        if (htmlContent !== undefined) {
            element.innerHTML = htmlContent;
            return element;
        }
        return element.innerHTML || '';
    }

    function append(parent, child) {
        if (typeof parent === 'string') parent = $(parent);
        if (typeof child === 'string') {
            var temp = document.createElement('div');
            temp.innerHTML = child;
            child = temp.firstChild;
        }
        if (parent && child) parent.appendChild(child);
    }

    function remove(element) {
        if (typeof element === 'string') element = $(element);
        if (element && element.parentNode) {
            element.parentNode.removeChild(element);
        }
    }

    function prop(element, property, value) {
        if (typeof element === 'string') element = $(element);
        if (!element) return;
        
        if (value !== undefined) {
            element[property] = value;
            return element;
        }
        return element[property];
    }

    function attr(element, attribute, value) {
        if (typeof element === 'string') element = $(element);
        if (!element) return;
        
        if (value !== undefined) {
            element.setAttribute(attribute, value);
            return element;
        }
        return element.getAttribute(attribute);
    }

    function scrollTop(element, value) {
        if (typeof element === 'string') element = $(element);
        if (!element) return 0;
        
        if (value !== undefined) {
            element.scrollTop = value;
            return element;
        }
        return element.scrollTop;
    }

    // =============================================================================
    // AUTO-INITIALIZATION
    // =============================================================================

    function autoInit() {
        var path = window.location.pathname;
        
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
    // FLASH MESSAGES
    // =============================================================================

    function showFlashMessage(message, type) {
        type = type || 'info';
        
        var alertClass = {
            'success': 'alert-success',
            'error': 'alert-danger',
            'warning': 'alert-warning',
            'info': 'alert-info'
        }[type] || 'alert-info';
        
        var icon = {
            'success': 'bi-check-circle',
            'error': 'bi-exclamation-triangle',
            'warning': 'bi-exclamation-triangle',
            'info': 'bi-info-circle'
        }[type] || 'bi-info-circle';
        
        var alertDiv = createElement('div', 
            'alert ' + alertClass + ' alert-dismissible fade show',
            '<i class="bi ' + icon + '"></i> ' + escapeHtml(message) + 
            '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>'
        );
        attr(alertDiv, 'role', 'alert');
        
        var container = $('#flash-messages');
        if (container) {
            append(container, alertDiv);
            setTimeout(function() {
                remove(alertDiv);
            }, 5000);
        }
    }

    function escapeHtml(text) {
        var map = {
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

    // =============================================================================
    // AUTH FUNCTIONS
    // =============================================================================

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

    function checkAuth() {
        var token = getAuthToken();
        if (!token) return Promise.resolve(false);

        return fetch('/api/auth/verify', {
            headers: {
                'Authorization': 'Bearer ' + token
            }
        })
        .then(function(response) {
            if (response.ok) {
                return response.json().then(function(data) {
                    return data.user;
                });
            }
            return false;
        })
        .catch(function() {
            return false;
        });
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
        .then(function(response) {
            return response.json();
        })
        .then(function(data) {
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
        .then(function(response) {
            return response.json();
        });
    }

    // =============================================================================
    // CHAT FUNCTIONS
    // =============================================================================

    var isStreaming = false;
    var currentStreamingMessage = null;

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
        val('#message-input', '');

        // Show typing indicator
        var typingId = addTypingIndicator();

        // Send to API
        isStreaming = true;
        prop('#send-btn', 'disabled', true);
        html('#send-btn', '<i class="bi bi-hourglass-split"></i>');

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
        .then(function(response) {
            if (!response.ok) {
                throw new Error('HTTP ' + response.status);
            }

            // Remove typing indicator
            removeTypingIndicator(typingId);

            // Start streaming response
            currentStreamingMessage = addMessageToChat('', 'assistant');
            return handleStreamingResponse(response);
        })
        .catch(function(error) {
            removeTypingIndicator(typingId);
            showFlashMessage('Error sending message: ' + error.message, 'error');
            console.error('Chat error:', error);
        })
        .finally(function() {
            isStreaming = false;
            currentStreamingMessage = null;
            prop('#send-btn', 'disabled', false);
            html('#send-btn', '<i class="bi bi-send"></i>');
        });
    }

    function handleStreamingResponse(response) {
        var reader = response.body.getReader();
        var decoder = new TextDecoder();
        var buffer = '';

        function processStream() {
            return reader.read().then(function(result) {
                var done = result.done;
                var value = result.value;
                
                if (done) {
                    return;
                }

                buffer += decoder.decode(value, { stream: true });
                var lines = buffer.split('\n');
                buffer = lines.pop();

                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    if (line.trim()) {
                        try {
                            var data = JSON.parse(line);
                            if (data.message && data.message.content) {
                                appendToStreamingMessage(data.message.content);
                            }
                            if (data.done) {
                                return;
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
        var timestamp = new Date().toLocaleTimeString();
        var messageClass = role === 'user' ? 'user-message' : 'assistant-message';
        
        var messageId = 'msg-' + Date.now();
        var messageHtml = '<div id="' + messageId + '" class="message ' + messageClass + '">' +
            '<div class="message-content">' +
            (role === 'user' ? escapeHtml(content) : renderMarkdown(content)) +
            '</div>' +
            '<span class="message-timestamp">' + timestamp + '</span>' +
            '</div>';
        
        append('#chat-messages', messageHtml);
        scrollToBottom();
        
        return messageId;
    }

    function appendToStreamingMessage(content) {
        if (!currentStreamingMessage) return;

        var messageEl = $('#' + currentStreamingMessage);
        var contentEl = messageEl ? messageEl.querySelector('.message-content') : null;
        if (!contentEl) return;
        
        var currentText = contentEl.getAttribute('data-raw-content') || '';
        var newText = currentText + content;
        
        attr(contentEl, 'data-raw-content', newText);
        html(contentEl, renderMarkdown(newText));
        
        scrollToBottom();
    }

    function addTypingIndicator() {
        var typingId = 'typing-' + Date.now();
        var typingHtml = '<div id="' + typingId + '" class="message assistant-message">' +
            '<div class="message-content">' +
            '<div class="typing-indicator">' +
            '<span></span><span></span><span></span>' +
            '</div></div></div>';
        
        append('#chat-messages', typingHtml);
        scrollToBottom();
        
        return typingId;
    }

    function removeTypingIndicator(typingId) {
        remove('#' + typingId);
    }

    function scrollToBottom() {
        var messages = $('#chat-messages');
        if (messages) {
            scrollTop(messages, messages.scrollHeight);
        }
    }

    function renderMarkdown(text) {
        if (!text) return '';
        
        var html = escapeHtml(text);
        html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        html = html.replace(/\*(.*?)\*/g, '<em>$1</em>');
        html = html.replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
        html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
        html = html.replace(/\n/g, '<br>');
        
        return html;
    }

    // =============================================================================
    // PAGE INITIALIZATION FUNCTIONS
    // =============================================================================

    function initIndex() {
        console.log('🏠 Index page loaded');
        
        checkAuth().then(function(user) {
            if (user) {
                html('#nav-links', 
                    '<a class="nav-link" href="/chat">' +
                    '<i class="bi bi-chat-dots"></i> Chat</a>' +
                    '<a class="nav-link" href="#" onclick="DevstralClient.logout()">' +
                    '<i class="bi bi-box-arrow-right"></i> Logout</a>'
                );
                
                var actionButtons = document.querySelector('.text-center:last-child');
                if (actionButtons) {
                    html(actionButtons,
                        '<a href="/chat" class="btn btn-primary btn-lg">' +
                        '<i class="bi bi-chat-dots"></i> Continue Chatting</a>'
                    );
                }
            }
        }).catch(function(error) {
            console.log('Not authenticated, showing default options');
        });
    }

    function initLogin() {
        console.log('🔐 Login page loaded');
        
        checkAuth().then(function(user) {
            if (user) {
                window.location.href = '/chat';
            }
        });
        
        on('#loginForm', 'submit', function(e) {
            e.preventDefault();
            
            var username = val('#username').trim();
            var password = val('#password');
            
            if (!username || !password) {
                showFlashMessage('Username and password are required', 'error');
                return;
            }
            
            var loginBtn = $('#login-btn');
            prop(loginBtn, 'disabled', true);
            html(loginBtn, '<i class="bi bi-hourglass-split"></i> Logging in...');
            
            login(username, password).then(function(result) {
                if (result.success) {
                    showFlashMessage('Login successful! Redirecting...', 'success');
                    setTimeout(function() {
                        window.location.href = '/chat';
                    }, 1000);
                } else {
                    showFlashMessage(result.error, 'error');
                    prop(loginBtn, 'disabled', false);
                    html(loginBtn, '<i class="bi bi-box-arrow-in-right"></i> Login');
                }
            }).catch(function(error) {
                console.error('Login error:', error);
                showFlashMessage('Login failed: ' + error.message, 'error');
                prop(loginBtn, 'disabled', false);
                html(loginBtn, '<i class="bi bi-box-arrow-in-right"></i> Login');
            });
        });
    }

    function initRegister() {
        console.log('📝 Register page loaded');
        
        checkAuth().then(function(user) {
            if (user) {
                window.location.href = '/chat';
            }
        });
        
        showRegistrationForm();
        
        function showRegistrationForm() {
            html('#registration-info',
                '<div class="alert alert-info" role="alert">' +
                '<i class="bi bi-info-circle"></i> ' +
                '<strong>Registration requires admin approval.</strong><br>' +
                'After registering, please wait for an administrator to approve your account before you can log in.' +
                '</div>'
            );
            
            var regForm = $('#registerForm');
            if (regForm) {
                regForm.style.display = 'block';
                setupFormValidation();
            }
        }
        
        function setupFormValidation() {
            on('#confirmPassword', 'input', function() {
                var password = val('#password');
                var confirmPassword = val(this);
                
                if (confirmPassword && password !== confirmPassword) {
                    addClass(this, 'is-invalid');
                    removeClass(this, 'is-valid');
                } else if (confirmPassword) {
                    removeClass(this, 'is-invalid');
                    addClass(this, 'is-valid');
                }
            });
            
            on('#registerForm', 'submit', function(e) {
                e.preventDefault();
                handleRegistration();
            });
        }
        
        function handleRegistration() {
            var username = val('#username').trim();
            var password = val('#password');
            var confirmPassword = val('#confirmPassword');
            
            if (!username || username.length < 3) {
                showFlashMessage('Username must be at least 3 characters', 'error');
                return;
            }
            
            if (!password || password.length < 6) {
                showFlashMessage('Password must be at least 6 characters', 'error');
                return;
            }
            
            if (password !== confirmPassword) {
                showFlashMessage('Passwords do not match', 'error');
                return;
            }
            
            var registerBtn = $('#register-btn');
            prop(registerBtn, 'disabled', true);
            html(registerBtn, '<i class="bi bi-hourglass-split"></i> Registering...');
            
            register(username, password).then(function(data) {
                if (data.success) {
                    showFlashMessage('Registration successful! Your account is pending admin approval.', 'success');
                    
                    $('#registerForm').reset();
                    var validElements = $$('.is-valid, .is-invalid');
                    for (var i = 0; i < validElements.length; i++) {
                        removeClass(validElements[i], 'is-valid');
                        removeClass(validElements[i], 'is-invalid');
                    }
                } else {
                    showFlashMessage(data.error || 'Registration failed', 'error');
                }
            }).catch(function(error) {
                console.error('Registration error:', error);
                showFlashMessage('Registration failed: ' + error.message, 'error');
            }).finally(function() {
                prop(registerBtn, 'disabled', false);
                html(registerBtn, '<i class="bi bi-person-plus"></i> Register (Pending Approval)');
            });
        }
    }

    function initChat() {
        console.log('💬 Chat page loaded');
        
        checkAuth().then(function(user) {
            if (!user) {
                window.location.href = '/login';
                return;
            }
            
            text('#username-display', user.username);
            setupChatInterface();
            
        }).catch(function(error) {
            console.error('Auth check failed:', error);
            window.location.href = '/login';
        });
        
        function setupChatInterface() {
            on('#message-input', 'keydown', function(e) {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    var message = val(this).trim();
                    if (message) {
                        sendMessage(message);
                    }
                }
            });
            
            on('#send-btn', 'click', function() {
                var message = val('#message-input').trim();
                if (message) {
                    sendMessage(message);
                }
            });
            
            on('#message-input', 'input', function() {
                this.style.height = 'auto';
                this.style.height = Math.min(this.scrollHeight, 150) + 'px';
            });
            
            var messageInput = $('#message-input');
            if (messageInput) {
                messageInput.focus();
            }
            
            // Set initial timestamp
            var timestamp = $('.message-timestamp');
            if (timestamp) {
                text(timestamp, new Date().toLocaleTimeString());
            }
        }
    }

    function initAdmin() {
        console.log('👑 Admin page loaded');
        
        checkAuth().then(function(user) {
            if (!user) {
                window.location.href = '/login';
                return;
            }
            
            if (!user.isAdmin) {
                window.location.href = '/unauthorized.html';
                return;
            }
            
            setupAdminInterface();
            
        }).catch(function(error) {
            console.error('Auth check failed:', error);
            window.location.href = '/login';
        });
        
        function setupAdminInterface() {
            html('#app-content',
                '<div class="row">' +
                '<div class="col-12">' +
                '<h2><i class="bi bi-gear"></i> Admin Dashboard</h2>' +
                '<p>Admin functionality is being implemented...</p>' +
                '</div></div>'
            );
        }
    }

    // =============================================================================
    // PUBLIC API
    // =============================================================================

    return {
        showFlashMessage: showFlashMessage,
        logout: logout,
        initIndex: initIndex,
        initLogin: initLogin,
        initRegister: initRegister,
        initChat: initChat,
        initAdmin: initAdmin,
        checkAuth: checkAuth,
        login: login,
        register: register,
        sendMessage: sendMessage,
        autoInit: autoInit
    };

})();

// Global logout function for navbar
window.logout = DevstralClient.logout;

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
    DevstralClient.autoInit();
});