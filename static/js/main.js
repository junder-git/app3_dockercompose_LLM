// static/js/main.js

// Global app namespace
const ChatApp = {
    ws: null,
    currentStreamMessage: null,
    isWaitingForResponse: false,
    currentPage: null
};

// Utility functions
const Utils = {
    showError: function(message, container) {
        const errorDiv = document.createElement('div');
        errorDiv.className = 'error-message';
        errorDiv.textContent = message;
        container.appendChild(errorDiv);
        
        // Auto-remove after 5 seconds
        setTimeout(() => errorDiv.remove(), 5000);
    },
    
    formatDate: function(dateString) {
        return new Date(dateString).toLocaleString();
    }
};

// Page-specific initialization
document.addEventListener('DOMContentLoaded', function() {
    // Detect current page
    const path = window.location.pathname;
    
    if (path === '/chat') {
        ChatApp.currentPage = 'chat';
        ChatPage.init();
    } else if (path === '/admin') {
        ChatApp.currentPage = 'admin';
        AdminPage.init();
    } else if (path === '/register') {
        ChatApp.currentPage = 'register';
        RegisterPage.init();
    }
});

// Chat Page Handler
const ChatPage = {
    elements: {},
    
    init: function() {
        this.elements = {
            chatMessages: document.getElementById('chatMessages'),
            messageInput: document.getElementById('messageInput'),
            sendButton: document.getElementById('sendButton'),
            typingIndicator: document.getElementById('typingIndicator')
        };
        
        this.bindEvents();
        this.initWebSocket();
    },
    
    bindEvents: function() {
        this.elements.sendButton.addEventListener('click', () => this.sendMessage());
        this.elements.messageInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                this.sendMessage();
            }
        });
    },
    
    initWebSocket: function() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        ChatApp.ws = new WebSocket(`${protocol}//${window.location.host}/ws`);
        
        ChatApp.ws.onopen = () => {
            console.log('WebSocket connected');
            this.loadChatHistory();
            this.enableInput();
        };
        
        ChatApp.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };
        
        ChatApp.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            Utils.showError('Connection error. Please refresh the page.', this.elements.chatMessages);
        };
        
        ChatApp.ws.onclose = () => {
            console.log('WebSocket disconnected');
            this.disableInput();
            setTimeout(() => this.initWebSocket(), 3000);
        };
    },
    
    handleWebSocketMessage: function(data) {
        switch(data.type) {
            case 'message':
                if (data.role === 'assistant') {
                    this.addMessage(data.role, data.content, data.cached);
                    ChatApp.isWaitingForResponse = false;
                    this.enableInput();
                } else {
                    this.addMessage(data.role, data.content);
                }
                break;
                
            case 'stream':
                if (!ChatApp.currentStreamMessage) {
                    ChatApp.currentStreamMessage = this.addMessage('assistant', '', false, true);
                }
                ChatApp.currentStreamMessage.textContent += data.content;
                this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
                break;
                
            case 'complete':
                ChatApp.currentStreamMessage = null;
                ChatApp.isWaitingForResponse = false;
                this.enableInput();
                break;
                
            case 'typing':
                this.elements.typingIndicator.style.display = data.status === 'start' ? 'block' : 'none';
                break;
                
            case 'error':
                Utils.showError(data.message, this.elements.chatMessages);
                ChatApp.isWaitingForResponse = false;
                this.enableInput();
                break;
        }
    },
    
    loadChatHistory: async function() {
        try {
            const response = await fetch('/api/chat/history');
            const data = await response.json();
            
            this.elements.chatMessages.innerHTML = '';
            data.messages.forEach(msg => {
                this.addMessage(msg.role, msg.content);
            });
        } catch (error) {
            console.error('Error loading chat history:', error);
        }
    },
    
    addMessage: function(role, content, cached = false, streaming = false) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${role === 'user' ? 'user-message' : 'assistant-message'}`;
        if (cached) messageDiv.classList.add('cached');
        messageDiv.textContent = content;
        
        if (cached && role === 'assistant') {
            const cachedIndicator = document.createElement('div');
            cachedIndicator.className = 'cached-indicator';
            cachedIndicator.textContent = '✓ Cached response';
            messageDiv.appendChild(cachedIndicator);
        }
        
        this.elements.chatMessages.appendChild(messageDiv);
        this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
        return messageDiv;
    },
    
    sendMessage: function() {
        const message = this.elements.messageInput.value.trim();
        if (message && ChatApp.ws && ChatApp.ws.readyState === WebSocket.OPEN && !ChatApp.isWaitingForResponse) {
            ChatApp.isWaitingForResponse = true;
            this.disableInput();
            
            ChatApp.ws.send(JSON.stringify({
                type: 'chat',
                message: message
            }));
            
            this.elements.messageInput.value = '';
            ChatApp.currentStreamMessage = null;
        }
    },
    
    enableInput: function() {
        this.elements.sendButton.disabled = false;
        this.elements.messageInput.disabled = false;
        this.elements.messageInput.focus();
    },
    
    disableInput: function() {
        this.elements.sendButton.disabled = true;
        this.elements.messageInput.disabled = true;
    }
};

// Admin Page Handler
const AdminPage = {
    elements: {},
    
    init: function() {
        this.elements = {
            userList: document.getElementById('userList'),
            chatHistory: document.getElementById('chatHistory'),
            selectedUserText: document.getElementById('selectedUser')
        };
        
        this.loadUsers();
    },
    
    loadUsers: async function() {
        try {
            const response = await fetch('/api/admin/users');
            const data = await response.json();
            
            this.elements.userList.innerHTML = '';
            data.users.forEach(user => {
                const userDiv = document.createElement('div');
                userDiv.className = 'p-2 mb-2 bg-secondary rounded user-card';
                userDiv.innerHTML = `
                    <div class="d-flex justify-content-between align-items-center">
                        <span>${user.username}</span>
                        <span class="badge ${user.is_admin ? 'bg-danger' : 'bg-primary'}">
                            ${user.is_admin ? 'Admin' : 'User'}
                        </span>
                    </div>
                    <small class="text-muted">Joined: ${Utils.formatDate(user.created_at)}</small>
                `;
                userDiv.addEventListener('click', () => this.loadUserChat(user.id, user.username));
                this.elements.userList.appendChild(userDiv);
            });
        } catch (error) {
            console.error('Error loading users:', error);
            Utils.showError('Failed to load users', this.elements.userList);
        }
    },
    
    loadUserChat: async function(userId, username) {
        try {
            this.elements.selectedUserText.textContent = `Chat history for: ${username}`;
            
            const response = await fetch(`/api/admin/chat/${userId}`);
            const data = await response.json();
            
            this.elements.chatHistory.innerHTML = '';
            
            if (data.messages.length === 0) {
                this.elements.chatHistory.innerHTML = '<p class="text-muted text-center">No chat history found</p>';
                return;
            }
            
            data.messages.forEach(msg => {
                const messageDiv = document.createElement('div');
                messageDiv.className = `admin-message ${msg.role === 'user' ? 'admin-user-message' : 'admin-assistant-message'}`;
                messageDiv.innerHTML = `
                    <div>${msg.content}</div>
                    <small class="text-muted">${Utils.formatDate(msg.timestamp)}</small>
                `;
                this.elements.chatHistory.appendChild(messageDiv);
            });
            
            this.elements.chatHistory.scrollTop = this.elements.chatHistory.scrollHeight;
        } catch (error) {
            console.error('Error loading chat history:', error);
            Utils.showError('Failed to load chat history', this.elements.chatHistory);
        }
    }
};

// Register Page Handler
const RegisterPage = {
    init: function() {
        const form = document.querySelector('form');
        form.addEventListener('submit', function(e) {
            const password = document.getElementById('password').value;
            const confirmPassword = document.getElementById('confirm_password').value;
            
            if (password !== confirmPassword) {
                e.preventDefault();
                alert('Passwords do not match!');
            }
        });
    }
};