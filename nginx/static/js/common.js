// Guest Chat Storage Manager - localStorage for guest sessions
// Add this to chat.html or common.js for guest users

const GuestChatStorage = {
    STORAGE_KEY: 'guest_chat_history',
    MAX_MESSAGES: 50,

    // Save message to localStorage
    saveMessage(role, content) {
        try {
            const messages = this.getMessages();
            const message = {
                role: role,
                content: content,
                timestamp: new Date().toISOString(),
                id: Date.now() + '_' + Math.random().toString(36).substr(2, 9)
            };

            messages.push(message);

            // Keep only last MAX_MESSAGES
            if (messages.length > this.MAX_MESSAGES) {
                messages.splice(0, messages.length - this.MAX_MESSAGES);
            }

            localStorage.setItem(this.STORAGE_KEY, JSON.stringify(messages));
            return true;
        } catch (error) {
            console.warn('Failed to save guest message to localStorage:', error);
            return false;
        }
    },

    // Get all messages from localStorage
    getMessages() {
        try {
            const stored = localStorage.getItem(this.STORAGE_KEY);
            return stored ? JSON.parse(stored) : [];
        } catch (error) {
            console.warn('Failed to load guest messages from localStorage:', error);
            return [];
        }
    },

    // Get recent messages for context
    getRecentMessages(limit = 10) {
        const messages = this.getMessages();
        return messages.slice(-limit);
    },

    // Clear all messages
    clearMessages() {
        try {
            localStorage.removeItem(this.STORAGE_KEY);
            return true;
        } catch (error) {
            console.warn('Failed to clear guest messages from localStorage:', error);
            return false;
        }
    },

    // Get storage info
    getStorageInfo() {
        const messages = this.getMessages();
        return {
            messageCount: messages.length,
            maxMessages: this.MAX_MESSAGES,
            storageType: 'localStorage',
            canLoadHistory: messages.length > 0,
            lastMessage: messages.length > 0 ? messages[messages.length - 1].timestamp : null
        };
    },

    // Import messages (for debugging or data migration)
    importMessages(messages) {
        try {
            const validMessages = messages.filter(msg => 
                msg.role && msg.content && typeof msg.content === 'string'
            );
            localStorage.setItem(this.STORAGE_KEY, JSON.stringify(validMessages));
            return true;
        } catch (error) {
            console.warn('Failed to import guest messages:', error);
            return false;
        }
    },

    // Export messages (for user download)
    exportMessages() {
        const messages = this.getMessages();
        const exportData = {
            exportType: 'guest_chat_history',
            exportedAt: new Date().toISOString(),
            messageCount: messages.length,
            messages: messages,
            note: 'Guest session chat history - stored in browser localStorage only'
        };

        return JSON.stringify(exportData, null, 2);
    }
};

// Integration with existing chat system
window.GuestChatStorage = GuestChatStorage;

// Auto-detect guest users and initialize
document.addEventListener('DOMContentLoaded', function() {
    // Check if user is a guest (you can detect this from server headers or user type)
    const chatStorageType = document.querySelector('meta[name="chat-storage"]')?.content;
    const userType = document.querySelector('meta[name="user-type"]')?.content;
    
    if (chatStorageType === 'localStorage' || userType === 'guest') {
        console.log('🔄 Guest user detected - using localStorage for chat history');
        
        // Override chat history functions if they exist
        if (window.chat && typeof window.chat === 'object') {
            // Save original functions
            window.chat._originalLoadHistory = window.chat.loadChatHistory;
            window.chat._originalClearHistory = window.chat.clearChat;
            
            // Replace with localStorage versions
            window.chat.loadChatHistory = function() {
                const messages = GuestChatStorage.getMessages();
                if (messages.length > 0) {
                    // Hide welcome prompt
                    const welcomePrompt = document.getElementById('welcome-prompt');
                    if (welcomePrompt) {
                        welcomePrompt.style.display = 'none';
                    }
                    
                    // Load messages into chat
                    messages.forEach(msg => {
                        this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false);
                    });
                    
                    console.log('📱 Loaded', messages.length, 'messages from localStorage');
                }
            };
            
            window.chat.clearChat = function() {
                if (confirm('Clear chat history? This will only clear your local browser storage.')) {
                    GuestChatStorage.clearMessages();
                    document.getElementById('chat-messages').innerHTML = '';
                    document.getElementById('welcome-prompt').style.display = 'block';
                    console.log('🗑️ Guest chat history cleared from localStorage');
                }
            };
            
            // Hook into message sending
            const originalAddMessage = window.chat.addMessage;
            window.chat.addMessage = function(sender, content, isStreaming = false) {
                // Call original function
                const result = originalAddMessage.call(this, sender, content, isStreaming);
                
                // Save to localStorage if not streaming (final message)
                if (!isStreaming && content.trim()) {
                    GuestChatStorage.saveMessage(sender === 'user' ? 'user' : 'assistant', content);
                }
                
                return result;
            };
        }
        
        // Add storage info to page
        const storageInfo = GuestChatStorage.getStorageInfo();
        console.log('💾 Guest storage info:', storageInfo);
        
        // Add notice about guest storage
        const chatContainer = document.querySelector('.chat-container');
        if (chatContainer) {
            const notice = document.createElement('div');
            notice.className = 'alert alert-info alert-dismissible fade show';
            notice.style.cssText = 'position: absolute; top: 10px; left: 50%; transform: translateX(-50%); z-index: 1000; max-width: 500px;';
            notice.innerHTML = `
                <i class="bi bi-info-circle"></i>
                <strong>Guest Session:</strong> Your chat history is stored locally in your browser only.
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            `;
            
            chatContainer.style.position = 'relative';
            chatContainer.appendChild(notice);
            
            // Auto-hide after 5 seconds
            setTimeout(() => {
                if (notice.parentNode) {
                    notice.remove();
                }
            }, 5000);
        }
    }
});

// Add export function to download guest chat history
window.downloadGuestHistory = function() {
    if (typeof GuestChatStorage === 'undefined') {
        alert('Guest storage not available');
        return;
    }
    
    const exportData = GuestChatStorage.exportMessages();
    const blob = new Blob([exportData], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = 'guest-chat-history-' + new Date().toISOString().split('T')[0] + '.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    
    console.log('📥 Guest chat history downloaded');
};

const DevstralCommon = {
    async logout() {
        try {
            await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });

            // Clear cookies
            const cookies = ['access_token', 'session', 'auth_token', 'guest_session'];
            cookies.forEach(name => {
                document.cookie = name + '=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax';
            });

            // Clear storage
            localStorage.clear();
            sessionStorage.clear();

            // Redirect and force reload
            window.location.href = '/?clear_cache=1';
        } catch (err) {
            console.error('Logout failed', err);
        }
    },

    // Optional user loading - doesn't fail if auth is broken
    async loadUser() {
        try {
            const response = await fetch('/api/auth/me', { 
                credentials: 'include',
                // Add timeout to prevent hanging
                signal: AbortSignal.timeout(5000)
            });
            
            if (response.ok) {
                const data = await response.json();
                if (data.success && data.username) {
                    // Update any username displays
                    const usernameElements = document.querySelectorAll('#navbar-username, .username-display');
                    usernameElements.forEach(el => {
                        if (el) el.textContent = data.username;
                    });
                    
                    // Show authenticated nav items
                    const authElements = document.querySelectorAll('.auth-required');
                    authElements.forEach(el => {
                        if (el) el.style.display = 'block';
                    });
                    
                    // Hide guest nav items
                    const guestElements = document.querySelectorAll('.guest-only');
                    guestElements.forEach(el => {
                        if (el) el.style.display = 'none';
                    });
                    
                    return data;
                }
            }
        } catch (error) {
            console.warn('Auth check failed (this is normal for guests):', error);
        }
        
        // Fallback for guests/unauthenticated users
        const usernameElements = document.querySelectorAll('#navbar-username, .username-display');
        usernameElements.forEach(el => {
            if (el) el.textContent = 'Guest';
        });
        
        // Show guest nav items
        const guestElements = document.querySelectorAll('.guest-only');
        guestElements.forEach(el => {
            if (el) el.style.display = 'block';
        });
        
        // Hide authenticated nav items
        const authElements = document.querySelectorAll('.auth-required');
        authElements.forEach(el => {
            if (el) el.style.display = 'none';
        });
        
        return null;
    },

    setupSmoothScrolling() {
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                const target = document.querySelector(this.getAttribute('href'));
                if (target) {
                    target.scrollIntoView({
                        behavior: 'smooth',
                        block: 'start'
                    });
                }
            });
        });
    },

    setupFeatureCardAnimations() {
        const featureCards = document.querySelectorAll('.feature-card');

        featureCards.forEach((card, index) => {
            card.style.animationDelay = (index * 0.1) + 's';
            card.classList.add('animate-in');

            card.addEventListener('mouseenter', function () {
                this.style.transform = 'translateY(-8px) scale(1.02)';
                this.style.boxShadow = '0 15px 40px rgba(13, 110, 253, 0.3)';
            });

            card.addEventListener('mouseleave', function () {
                this.style.transform = 'translateY(0) scale(1)';
                this.style.boxShadow = '0 10px 30px rgba(13, 110, 253, 0.2)';
            });
        });
    },

    setupKeyboardNavigation() {
        document.addEventListener('keydown', function (e) {
            if (e.altKey && e.key === 'h') {
                e.preventDefault();
                window.location.href = '/';
            }
            if (e.altKey && e.key === 'c') {
                e.preventDefault();
                window.location.href = '/chat.html';
            }
            if (e.altKey && e.key === 'l') {
                e.preventDefault();
                window.location.href = '/login.html';
            }
            if (e.altKey && e.key === 'r') {
                e.preventDefault();
                window.location.href = '/register.html';
            }
        });
    },

    setupAnalytics() {
        const trackableElements = {
            'cta-start-chat': document.querySelector('.cta-button'),
            'cta-get-started': document.querySelector('.btn[href*="register"]'),
            'nav-chat': document.querySelector('.nav-link[href*="chat"]'),
            'nav-login': document.querySelector('.nav-link[href*="login"]'),
            'nav-register': document.querySelector('.nav-link[href*="register"]')
        };

        Object.entries(trackableElements).forEach(([key, element]) => {
            if (element) {
                element.addEventListener('click', function () {
                    console.log('User interaction: ' + key);
                    DevstralCommon.trackEvent('button_click', key);
                });
            }
        });
    },

    trackEvent(action, label) {
        const event = {
            timestamp: new Date().toISOString(),
            action: action,
            label: label,
            page: window.location.pathname,
            userAgent: navigator.userAgent.substring(0, 100)
        };

        console.log('Event tracked:', event);

        // You can POST this to your analytics server here
        // fetch('/api/analytics/track', { method: 'POST', body: JSON.stringify(event) });
    },

    setupPerformanceMonitoring() {
        window.addEventListener('load', function () {
            const loadTime = performance.timing.loadEventEnd - performance.timing.navigationStart;
            console.log('Page load time: ' + loadTime + 'ms');

            if (loadTime > 3000) {
                console.warn('Page load time is slow, consider optimization');
            }
        });

        let lastFrameTime = performance.now();
        let frameCount = 0;
        let fps = 0;

        function monitorFPS() {
            const currentTime = performance.now();
            frameCount++;

            if (currentTime - lastFrameTime >= 1000) {
                fps = Math.round((frameCount * 1000) / (currentTime - lastFrameTime));
                frameCount = 0;
                lastFrameTime = currentTime;

                if (fps < 30) {
                    console.warn('Low FPS detected: ' + fps + ' fps');
                }
            }

            requestAnimationFrame(monitorFPS);
        }

        setTimeout(() => {
            monitorFPS();
        }, 2000);
    },

    // Utility function to show notifications
    showNotification(message, type, duration) {
        type = type || 'info';
        duration = duration || 3000;

        // Create notification element
        const notification = document.createElement('div');
        notification.className = 'alert alert-' + type + ' alert-dismissible fade show position-fixed';
        notification.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
        notification.innerHTML = message + 
            '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>';

        document.body.appendChild(notification);

        // Auto-remove after duration
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, duration);
    },

    // Utility function to format dates consistently
    formatDate(dateString) {
        try {
            const date = new Date(dateString);
            return date.toLocaleDateString() + ' ' + 
                   date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
        } catch (error) {
            return 'Invalid date';
        }
    },

    // Utility function to debounce function calls
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    },

    // Utility function to validate input
    validateInput(input, type) {
        switch (type) {
            case 'username':
                return /^[a-zA-Z0-9_]{3,20}$/.test(input);
            case 'password':
                return input.length >= 6;
            case 'email':
                return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input);
            default:
                return true;
        }
    },

    // Copy text to clipboard
    async copyToClipboard(text) {
        try {
            await navigator.clipboard.writeText(text);
            this.showNotification('Copied to clipboard!', 'success', 2000);
            return true;
        } catch (error) {
            console.error('Failed to copy to clipboard:', error);
            this.showNotification('Failed to copy to clipboard', 'error', 3000);
            return false;
        }
    },

    // Safe JSON parse
    safeJSONParse(jsonString, defaultValue) {
        try {
            return JSON.parse(jsonString);
        } catch (error) {
            console.warn('Failed to parse JSON:', error);
            return defaultValue || null;
        }
    },

    // Get URL parameters
    getUrlParameter(name) {
        const urlParams = new URLSearchParams(window.location.search);
        return urlParams.get(name);
    },

    // Set URL parameter without page reload
    setUrlParameter(name, value) {
        const url = new URL(window.location);
        url.searchParams.set(name, value);
        window.history.pushState({}, '', url);
    },

    // Remove URL parameter without page reload
    removeUrlParameter(name) {
        const url = new URL(window.location);
        url.searchParams.delete(name);
        window.history.pushState({}, '', url);
    },

    // Check if user is on mobile device
    isMobile() {
        return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
    },

    // Check if user prefers dark mode
    prefersDarkMode() {
        return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    },

    // Escape HTML to prevent XSS
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    // Truncate text with ellipsis
    truncateText(text, maxLength) {
        if (text.length <= maxLength) return text;
        return text.substr(0, maxLength) + '...';
    },

    // Generate random ID
    generateId(prefix) {
        prefix = prefix || 'id';
        return prefix + '-' + Math.random().toString(36).substr(2, 9);
    },

    // Check current authentication status (optional)
    async checkAuthStatus() {
        try {
            const response = await fetch('/api/guest/status', { 
                credentials: 'include',
                signal: AbortSignal.timeout(3000)
            });
            
            if (response.ok) {
                const data = await response.json();
                return data;
            }
        } catch (error) {
            console.warn('Auth status check failed:', error);
        }
        
        return { success: false, user_type: 'none' };
    }
};

document.addEventListener('DOMContentLoaded', () => {
    // Universal logout button handler
    const logoutBtn = document.getElementById('logout-button');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', (e) => {
            e.preventDefault();
            DevstralCommon.logout();
        });
    }

    // Initialize performance monitoring in development
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
        DevstralCommon.setupPerformanceMonitoring();
    }
});