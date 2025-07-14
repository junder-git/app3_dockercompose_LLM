// nginx/static/js/common.js - Universal JS for all pages
const GuestChatStorage = {
    STORAGE_KEY: 'guest_chat_history',
    MAX_MESSAGES: 50,

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

    getMessages() {
        try {
            const stored = localStorage.getItem(this.STORAGE_KEY);
            return stored ? JSON.parse(stored) : [];
        } catch (error) {
            console.warn('Failed to load guest messages from localStorage:', error);
            return [];
        }
    },

    clearMessages() {
        try {
            localStorage.removeItem(this.STORAGE_KEY);
            return true;
        } catch (error) {
            console.warn('Failed to clear guest messages from localStorage:', error);
            return false;
        }
    },

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

// Universal Chat System - works for all user types
class UniversalChat {
    constructor() {
        this.userData = null;
        this.isTyping = false;
        this.abortController = null;
        this.messageCount = 0;
        this.init();
    }

    async init() {
        // Get user data first
        this.userData = await DevstralCommon.loadUser();
        this.setupEventListeners();
        this.loadChatHistory();
        this.setupSuggestionChips();
        this.updateUIBasedOnUser();
        
        console.log('💬 Universal chat initialized for:', this.userData?.username || 'Guest');
    }

    updateUIBasedOnUser() {
        if (!this.userData || !this.userData.success) {
            // Guest user
            this.setupGuestFeatures();
        } else if (this.userData.is_admin) {
            // Admin user
            this.setupAdminFeatures();
        } else if (this.userData.is_approved) {
            // Approved user
            this.setupApprovedFeatures();
        } else {
            // Pending user - redirect
            window.location.href = '/pending';
        }
    }

    setupGuestFeatures() {
        console.log('🔄 Setting up guest features');
        document.querySelector('.chat-input')?.setAttribute('placeholder', 'Guest mode: Ask a quick question...');
        
        // Show guest limitations
        const featuresDiv = document.querySelector('.user-features');
        if (featuresDiv) {
            featuresDiv.innerHTML = `
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0"><i class="bi bi-clock-history text-warning"></i> Guest Session</h6>
                        <small class="text-muted">Limited messages • localStorage only • No history saved</small>
                    </div>
                    <div class="d-flex gap-2">
                        <button class="btn btn-outline-warning btn-sm" onclick="downloadGuestHistory()">
                            <i class="bi bi-download"></i> Download
                        </button>
                        <a href="/register" class="btn btn-warning btn-sm">
                            <i class="bi bi-person-plus"></i> Register
                        </a>
                    </div>
                </div>
            `;
        }
    }

    setupApprovedFeatures() {
        console.log('✅ Setting up approved user features');
        const featuresDiv = document.querySelector('.user-features');
        if (featuresDiv) {
            featuresDiv.innerHTML = `
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0"><i class="bi bi-check-circle"></i> Full Access Features</h6>
                        <small class="text-muted">Chat history saved • No message limits • Priority access</small>
                    </div>
                    <div class="d-flex gap-2">
                        <button class="btn btn-outline-primary btn-sm" onclick="exportUserChats()">
                            <i class="bi bi-download"></i> Export
                        </button>
                        <a href="/dashboard" class="btn btn-outline-info btn-sm">
                            <i class="bi bi-speedometer2"></i> Dashboard
                        </a>
                    </div>
                </div>
            `;
        }
    }

    setupAdminFeatures() {
        console.log('👑 Setting up admin features');
        const featuresDiv = document.querySelector('.user-features');
        if (featuresDiv) {
            featuresDiv.innerHTML = `
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h6 class="mb-0"><i class="bi bi-shield-check"></i> Admin Access</h6>
                        <small class="text-muted">Full access • Admin controls • System management</small>
                    </div>
                    <div class="d-flex gap-2">
                        <a href="/admin" class="btn btn-outline-danger btn-sm">
                            <i class="bi bi-gear"></i> Admin Panel
                        </a>
                        <button class="btn btn-outline-primary btn-sm" onclick="exportUserChats()">
                            <i class="bi bi-download"></i> Export
                        </button>
                    </div>
                </div>
            `;
        }
    }

    setupEventListeners() {
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault();
                this.sendMessage();
            });
        }

        const stopButton = document.getElementById('stop-button');
        if (stopButton) {
            stopButton.addEventListener('click', () => this.stopGeneration());
        }

        const clearButton = document.getElementById('clear-chat');
        if (clearButton) {
            clearButton.addEventListener('click', () => this.clearChat());
        }
        
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.addEventListener('input', (e) => this.updateCharCount());
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    this.sendMessage();
                }
            });
        }
    }

    setupSuggestionChips() {
        document.querySelectorAll('.suggestion-chip').forEach(chip => {
            chip.addEventListener('click', () => {
                const input = document.getElementById('chat-input');
                if (input) {
                    input.value = chip.dataset.prompt;
                    input.focus();
                    this.updateCharCount();
                }
            });
        });
    }

    updateCharCount() {
        const textarea = document.getElementById('chat-input');
        const countEl = document.getElementById('char-count');
        if (textarea && countEl) {
            const count = textarea.value.length;
            countEl.textContent = count;
        }
    }

    async loadChatHistory() {
        if (!this.userData || !this.userData.success) {
            // Guest user - load from localStorage
            const messages = GuestChatStorage.getMessages();
            if (messages.length > 0) {
                const welcomePrompt = document.getElementById('welcome-prompt');
                if (welcomePrompt) welcomePrompt.style.display = 'none';
                
                messages.forEach(msg => {
                    this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false);
                });
                console.log('📱 Loaded', messages.length, 'messages from localStorage');
            }
            return;
        }

        // Approved/admin user - load from server
        try {
            const response = await fetch('/api/chat/history?limit=30', { credentials: 'include' });
            if (response.ok) {
                const data = await response.json();
                if (data.success && data.messages.length > 0) {
                    const welcomePrompt = document.getElementById('welcome-prompt');
                    if (welcomePrompt) welcomePrompt.style.display = 'none';
                    
                    data.messages.reverse().forEach(msg => {
                        this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false);
                    });
                    this.messageCount = data.messages.length;
                    console.log('🗄️ Loaded', data.messages.length, 'messages from Redis');
                }
            }
        } catch (error) {
            console.warn('Could not load chat history:', error);
        }
    }

    async sendMessage() {
        const input = document.getElementById('chat-input');
        const message = input?.value?.trim();
        
        if (!message || this.isTyping) return;

        // Check if guest user has exceeded limits
        if (!this.userData?.success) {
            const guestMessages = GuestChatStorage.getMessages();
            if (guestMessages.length >= 10) {
                alert('Guest message limit reached! Register for unlimited access.');
                return;
            }
        }

        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt) welcomePrompt.style.display = 'none';
        
        this.addMessage('user', message);
        input.value = '';
        this.updateCharCount();
        
        this.isTyping = true;
        this.updateButtons(true);

        this.abortController = new AbortController();
        const aiMessage = this.addMessage('ai', '', true);
        let accumulated = '';

        try {
            const requestBody = { 
                message: message,
                options: {
                    temperature: 0.7,
                    max_tokens: this.userData?.success ? 2048 : 1024
                }
            };

            // Only include history for approved users
            if (this.userData?.success) {
                requestBody.include_history = true;
            }

            const response = await fetch('/api/chat/stream', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                signal: this.abortController.signal,
                body: JSON.stringify(requestBody)
            });

            if (!response.ok) throw new Error('HTTP ' + response.status);

            const reader = response.body.getReader();
            const decoder = new TextDecoder();

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                const chunk = decoder.decode(value, { stream: true });
                const lines = chunk.split('\n');

                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        const jsonStr = line.slice(6);
                        if (jsonStr === '[DONE]') {
                            this.finishStreaming(aiMessage, accumulated);
                            return;
                        }

                        try {
                            const data = JSON.parse(jsonStr);
                            if (data.content) {
                                accumulated += data.content;
                                this.updateStreamingMessage(aiMessage, accumulated);
                            }
                        } catch (e) {}
                    }
                }
            }
        } catch (error) {
            if (error.name !== 'AbortError') {
                console.error('Chat error:', error);
                this.updateStreamingMessage(aiMessage, '*Error: ' + error.message + '*');
            }
            this.finishStreaming(aiMessage, accumulated);
        }
    }

    addMessage(sender, content, isStreaming = false) {
        const messagesContainer = document.getElementById('chat-messages');
        if (!messagesContainer) return;

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        
        if (sender === 'user') {
            const username = this.userData?.username || 'Guest';
            const userType = this.userData?.is_admin ? 'Admin' : 
                           this.userData?.is_approved ? 'User' : 'Guest';
            
            contentDiv.innerHTML = `<div class="d-flex align-items-center mb-1">
                <i class="bi bi-person-circle text-primary me-2"></i>
                <strong>${username} (${userType})</strong>
            </div>` + (window.marked ? marked.parse(content) : content);
            
            // Save to appropriate storage
            if (!this.userData?.success) {
                GuestChatStorage.saveMessage('user', content);
            }
        } else {
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
                
            // Save AI response for guests
            if (!isStreaming && !this.userData?.success && content.trim()) {
                GuestChatStorage.saveMessage('assistant', content);
            }
        }
        
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        return messageDiv;
    }

    updateStreamingMessage(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const parsedContent = window.marked ? marked.parse(content) : content;
            streamingEl.innerHTML = parsedContent + '<span class="cursor">▋</span>';
        }
    }

    finishStreaming(messageDiv, finalContent) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const parsedContent = window.marked ? marked.parse(finalContent) : finalContent;
            streamingEl.innerHTML = parsedContent;
            
            // Save AI response for guests
            if (!this.userData?.success && finalContent.trim()) {
                GuestChatStorage.saveMessage('assistant', finalContent);
            }
        }
        this.isTyping = false;
        this.updateButtons(false);
    }

    stopGeneration() {
        if (this.abortController) {
            this.abortController.abort();
        }
    }

    updateButtons(isTyping) {
        const sendButton = document.getElementById('send-button');
        const stopButton = document.getElementById('stop-button');
        const chatInput = document.getElementById('chat-input');

        if (sendButton) sendButton.style.display = isTyping ? 'none' : 'flex';
        if (stopButton) stopButton.style.display = isTyping ? 'flex' : 'none';
        if (chatInput) chatInput.disabled = isTyping;
    }

    async clearChat() {
        if (!this.userData?.success) {
            // Guest user
            if (!confirm('Clear chat history? This will only clear your browser storage.')) return;
            GuestChatStorage.clearMessages();
        } else {
            // Approved/admin user
            if (!confirm('Clear your chat history? This will clear your saved Redis history.')) return;
            
            try {
                const response = await fetch('/api/chat/clear', {
                    method: 'POST',
                    credentials: 'include'
                });

                if (!response.ok) throw new Error('Failed to clear chat');
            } catch (error) {
                console.error('Clear chat error:', error);
                alert('Failed to clear chat: ' + error.message);
                return;
            }
        }

        const messagesContainer = document.getElementById('chat-messages');
        const welcomePrompt = document.getElementById('welcome-prompt');
        
        if (messagesContainer) messagesContainer.innerHTML = '';
        if (welcomePrompt) welcomePrompt.style.display = 'block';
        
        this.messageCount = 0;
        console.log('🗑️ Chat history cleared');
    }
}

// Universal Dashboard System
class UniversalDashboard {
    constructor() {
        this.userData = null;
        this.sessionStartTime = Date.now();
        this.init();
    }

    async init() {
        this.userData = await DevstralCommon.loadUser();
        
        if (!this.userData?.success) {
            window.location.href = '/login';
            return;
        }

        this.loadDashboardData();
        this.startSessionTimer();
        this.setupEventListeners();
        this.updateUIBasedOnUser();
        
        console.log('📊 Universal dashboard initialized for:', this.userData.username);
    }

    updateUIBasedOnUser() {
        if (this.userData.is_admin) {
            this.setupAdminDashboard();
        } else if (this.userData.is_approved) {
            this.setupUserDashboard();
        } else {
            window.location.href = '/pending';
        }
    }

    setupAdminDashboard() {
        console.log('👑 Setting up admin dashboard features');
        // Add admin-specific features
        const quickActions = document.querySelector('.quick-actions');
        if (quickActions) {
            const adminAction = document.createElement('a');
            adminAction.href = '/admin';
            adminAction.className = 'action-card';
            adminAction.innerHTML = `
                <div class="action-icon"><i class="bi bi-shield-check"></i></div>
                <h6>Admin Panel</h6>
                <small class="text-muted">Manage users and system</small>
            `;
            quickActions.appendChild(adminAction);
        }
    }

    setupUserDashboard() {
        console.log('✅ Setting up user dashboard features');
        // Standard user dashboard - no special admin features
    }

    setupEventListeners() {
        // Universal event listeners that work for all user types
    }

    async loadDashboardData() {
        // Load stats based on user permissions
        if (!this.userData?.success) return;

        try {
            // Mock data - replace with actual API calls
            const stats = {
                totalMessages: Math.floor(Math.random() * 500) + 50,
                messagesToday: Math.floor(Math.random() * 20) + 1,
                monthlyMessages: Math.floor(Math.random() * 300) + 100,
                activeDays: Math.floor(Math.random() * 30) + 5
            };

            this.updateStats(stats);
        } catch (error) {
            console.error('Failed to load dashboard data:', error);
        }
    }

    updateStats(stats) {
        const elements = {
            'total-messages': stats.totalMessages,
            'messages-today': stats.messagesToday,
            'monthly-messages': stats.monthlyMessages,
            'active-days': stats.activeDays
        };

        Object.entries(elements).forEach(([id, value]) => {
            const element = document.getElementById(id);
            if (element) element.textContent = value;
        });
    }

    startSessionTimer() {
        setInterval(() => {
            const sessionDuration = Math.floor((Date.now() - this.sessionStartTime) / 1000);
            const hours = Math.floor(sessionDuration / 3600);
            const minutes = Math.floor((sessionDuration % 3600) / 60);
            const seconds = sessionDuration % 60;
            
            let timeString = '';
            if (hours > 0) timeString += hours + 'h ';
            if (minutes > 0) timeString += minutes + 'm ';
            timeString += seconds + 's';
            
            const sessionTimeEl = document.getElementById('session-time');
            if (sessionTimeEl) sessionTimeEl.textContent = timeString;
        }, 1000);
    }
}

const DevstralCommon = {
    async logout() {
        try {
            await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });

            const cookies = ['access_token', 'session', 'auth_token', 'guest_session', 'guest_token'];
            cookies.forEach(name => {
                document.cookie = name + '=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax';
            });

            localStorage.clear();
            sessionStorage.clear();
            window.location.href = '/';
        } catch (err) {
            console.error('Logout failed', err);
            window.location.href = '/';
        }
    },

    async loadUser() {
        try {
            const response = await fetch('/api/auth/me', { 
                credentials: 'include',
                signal: AbortSignal.timeout(5000)
            });
            
            if (response.ok) {
                const data = await response.json();
                if (data.success && data.username) {
                    this.updateUserDisplay(data);
                    return data;
                }
            }
        } catch (error) {
            console.warn('Auth check failed (this is normal for guests):', error);
        }
        
        this.updateUserDisplay(null);
        return null;
    },

    updateUserDisplay(userData) {
        const usernameElements = document.querySelectorAll('#navbar-username, .username-display');
        const authElements = document.querySelectorAll('.auth-required');
        const guestElements = document.querySelectorAll('.guest-only');

        if (userData && userData.success) {
            usernameElements.forEach(el => {
                if (el) el.textContent = userData.username;
            });
            authElements.forEach(el => {
                if (el) el.style.display = 'block';
            });
            guestElements.forEach(el => {
                if (el) el.style.display = 'none';
            });
        } else {
            usernameElements.forEach(el => {
                if (el) el.textContent = 'Guest';
            });
            guestElements.forEach(el => {
                if (el) el.style.display = 'block';
            });
            authElements.forEach(el => {
                if (el) el.style.display = 'none';
            });
        }
    },

    showNotification(message, type = 'info', duration = 3000) {
        const notification = document.createElement('div');
        notification.className = `alert alert-${type} alert-dismissible fade show position-fixed`;
        notification.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
        notification.innerHTML = message + 
            '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>';

        document.body.appendChild(notification);

        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, duration);
    }
};

// Global functions accessible from anywhere
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

window.exportUserChats = async function() {
    try {
        const response = await fetch('/api/chat/history?limit=1000', {
            credentials: 'include'
        });
        
        if (response.ok) {
            const data = await response.json();
            const exportData = {
                username: window.universalChat?.userData?.username || 'user',
                exportedAt: new Date().toISOString(),
                messageCount: data.messages.length,
                messages: data.messages,
                storage: 'Redis'
            };

            const blob = new Blob([JSON.stringify(exportData, null, 2)], { 
                type: 'application/json' 
            });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'chat-history-' + new Date().toISOString().split('T')[0] + '.json';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
            DevstralCommon.showNotification('Chat history exported successfully!', 'success');
        }
    } catch (error) {
        console.error('Export error:', error);
        DevstralCommon.showNotification('Export failed: ' + error.message, 'error');
    }
};

window.clearChatHistory = async function() {
    if (window.universalChat) {
        window.universalChat.clearChat();
    }
};

// Auto-initialize based on page content
document.addEventListener('DOMContentLoaded', () => {
    // Universal logout button handler
    document.addEventListener('click', (e) => {
        if (e.target.matches('[onclick*="DevstralCommon.logout"]') || 
            e.target.closest('[onclick*="DevstralCommon.logout"]')) {
            e.preventDefault();
            DevstralCommon.logout();
        }
    });

    // Initialize chat if chat elements exist
    if (document.getElementById('chat-messages') || document.getElementById('chat-form')) {
        window.universalChat = new UniversalChat();
    }

    // Initialize dashboard if dashboard elements exist
    if (document.querySelector('.stats-grid') || document.querySelector('.dashboard-container')) {
        window.universalDashboard = new UniversalDashboard();
    }

    // Auto-detect guest users and show notifications
    const chatStorageType = document.querySelector('meta[name="chat-storage"]')?.content;
    const userType = document.querySelector('meta[name="user-type"]')?.content;
    
    if (chatStorageType === 'localStorage' || userType === 'guest') {
        console.log('🔄 Guest user detected - using localStorage for chat history');
    }
});