// static/js/chat.js - Chat Page Handler

const ChatPage = {
    elements: {},
    currentSession: null,
    ws: null,
    currentStreamMessage: null,
    isWaitingForResponse: false,
    
    init: function() {
        this.elements = {
            chatMessages: document.getElementById('chatMessages'),
            messageInput: document.getElementById('messageInput'),
            sendButton: document.getElementById('sendButton'),
            typingIndicator: document.getElementById('typingIndicator'),
            githubSettingsBtn: document.getElementById('githubSettingsBtn'),
            sessionsList: document.getElementById('sessionsList'),
            newSessionBtn: document.getElementById('newSessionBtn')
        };
        
        this.bindEvents();
        this.initWebSocket();
        this.setupTextareaAutoResize();
        this.loadSessions();
    },
    
    bindEvents: function() {
        this.elements.sendButton.addEventListener('click', () => this.sendMessage());
        this.elements.messageInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                this.sendMessage();
            }
        });

        // GitHub settings button
        if (this.elements.githubSettingsBtn) {
            this.elements.githubSettingsBtn.addEventListener('click', () => {
                const modal = new bootstrap.Modal(document.getElementById('githubSettingsModal'));
                modal.show();
            });
        }

        // New session button
        if (this.elements.newSessionBtn) {
            this.elements.newSessionBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.createNewSession();
            });
        }
    },

    loadSessions: async function() {
        try {
            const response = await fetch('/api/chat/sessions');
            const data = await response.json();
            
            this.renderSessionsList(data.sessions);
        } catch (error) {
            console.error('Error loading sessions:', error);
        }
    },

    renderSessionsList: function(sessions) {
        if (!this.elements.sessionsList) return;
        
        // Clear existing sessions (keep header and new session button)
        const existingSessions = this.elements.sessionsList.querySelectorAll('.session-item');
        existingSessions.forEach(item => item.remove());

        // Add sessions
        sessions.forEach(session => {
            const sessionItem = document.createElement('li');
            sessionItem.className = 'session-item';
            sessionItem.innerHTML = `
                <a class="dropdown-item d-flex justify-content-between align-items-center" href="#" 
                   data-session-id="${session.id}">
                    <div>
                        <div class="fw-semibold">${session.title}</div>
                        <small class="text-muted">${session.message_count} messages</small>
                    </div>
                    <button class="btn btn-sm btn-outline-danger btn-delete-session" 
                            data-session-id="${session.id}"
                            title="Delete session" ${sessions.length <= 1 ? 'disabled' : ''}>
                        <i class="bi bi-trash"></i>
                    </button>
                </a>
            `;
            
            // Add click handler for switching sessions
            const link = sessionItem.querySelector('a');
            link.addEventListener('click', (e) => {
                e.preventDefault();
                this.switchSession(session.id);
            });
            
            // Add click handler for delete button
            const deleteBtn = sessionItem.querySelector('.btn-delete-session');
            deleteBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.deleteSession(session.id);
            });
            
            this.elements.sessionsList.appendChild(sessionItem);
        });

        // Add divider if there are sessions
        if (sessions.length > 0) {
            const divider = document.createElement('li');
            divider.innerHTML = '<hr class="dropdown-divider">';
            this.elements.sessionsList.appendChild(divider);
        }
    },

    createNewSession: async function() {
        const title = prompt('Enter a title for the new chat session (optional):');
        
        try {
            const response = await fetch('/api/chat/sessions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                },
                body: JSON.stringify({ title: title || null })
            });

            if (response.ok) {
                const data = await response.json();
                this.currentSession = data.session;
                
                // Clear current chat
                this.elements.chatMessages.innerHTML = '';
                
                // Reload sessions list
                await this.loadSessions();
                
                window.Utils.showSuccess('New chat session created!', this.elements.chatMessages);
            } else {
                window.Utils.showError('Failed to create new session', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error creating session:', error);
            window.Utils.showError('Failed to create new session', this.elements.chatMessages);
        }
    },

    switchSession: async function(sessionId) {
        try {
            const response = await fetch(`/api/chat/sessions/${sessionId}/switch`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                }
            });

            if (response.ok) {
                const data = await response.json();
                this.currentSession = data.session;
                
                // Clear and reload messages
                this.elements.chatMessages.innerHTML = '';
                data.messages.forEach(msg => {
                    this.addMessage(msg.role, msg.content);
                });
                
                // Apply syntax highlighting
                setTimeout(() => this.applySyntaxHighlighting(), 100);
                
                window.Utils.showSuccess(`Switched to: ${data.session.title}`, this.elements.chatMessages);
            } else {
                window.Utils.showError('Failed to switch session', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error switching session:', error);
            window.Utils.showError('Failed to switch session', this.elements.chatMessages);
        }
    },

    deleteSession: async function(sessionId) {
        if (!confirm('Are you sure you want to delete this chat session? This action cannot be undone.')) {
            return;
        }

        try {
            const response = await fetch(`/api/chat/sessions/${sessionId}`, {
                method: 'DELETE',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                }
            });

            if (response.ok) {
                // Reload sessions
                await this.loadSessions();
                
                // If this was the current session, reload chat history
                if (this.currentSession && this.currentSession.id === sessionId) {
                    await this.loadChatHistory();
                }
                
                window.Utils.showSuccess('Session deleted successfully', this.elements.chatMessages);
            } else {
                const data = await response.json();
                window.Utils.showError(data.error || 'Failed to delete session', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error deleting session:', error);
            window.Utils.showError('Failed to delete session', this.elements.chatMessages);
        }
    },

    setupTextareaAutoResize: function() {
        const textarea = this.elements.messageInput;
        if (!textarea) return;
        
        textarea.style.height = 'auto';
        textarea.style.minHeight = '38px';
        textarea.style.maxHeight = '200px';
        textarea.style.overflowY = 'hidden';
        textarea.style.resize = 'none';

        textarea.addEventListener('input', () => {
            textarea.style.height = 'auto';
            const newHeight = Math.min(textarea.scrollHeight, 200);
            textarea.style.height = newHeight + 'px';
            textarea.style.overflowY = newHeight >= 200 ? 'auto' : 'hidden';
        });

        // Handle paste events to prevent consuming all characters
        textarea.addEventListener('paste', (e) => {
            setTimeout(() => {
                textarea.dispatchEvent(new Event('input'));
            }, 0);
        });
    },
    
    initWebSocket: function() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        this.ws = new WebSocket(`${protocol}//${window.location.host}/ws`);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
            this.loadChatHistory();
            this.enableInput();
        };
        
        this.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            window.Utils.showError('Connection error. Please refresh the page.', this.elements.chatMessages);
        };
        
        this.ws.onclose = () => {
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
                    this.isWaitingForResponse = false;
                    this.enableInput();
                } else {
                    this.addMessage(data.role, data.content);
                }
                break;
                
            case 'stream':
                if (!this.currentStreamMessage) {
                    this.currentStreamMessage = this.addMessage('assistant', '', false, true);
                }
                // For streaming, we need to handle code blocks carefully
                this.currentStreamMessage.streamContent = (this.currentStreamMessage.streamContent || '') + data.content;
                this.updateStreamingMessage(this.currentStreamMessage, this.currentStreamMessage.streamContent);
                this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
                break;
                
            case 'complete':
                if (this.currentStreamMessage) {
                    // Final processing of the complete message
                    this.finalizeStreamingMessage(this.currentStreamMessage);
                }
                this.currentStreamMessage = null;
                this.isWaitingForResponse = false;
                this.enableInput();
                break;
                
            case 'typing':
                this.elements.typingIndicator.style.display = data.status === 'start' ? 'block' : 'none';
                break;
                
            case 'error':
                window.Utils.showError(data.message, this.elements.chatMessages);
                this.isWaitingForResponse = false;
                this.enableInput();
                break;
        }
    },

    updateStreamingMessage: function(messageElement, content) {
        // For streaming, just show raw content until complete
        const contentDiv = messageElement.querySelector('.message-content') || messageElement;
        contentDiv.textContent = content;
    },

    finalizeStreamingMessage: function(messageElement) {
        // Process the final content with syntax highlighting
        const content = messageElement.streamContent;
        const processedContent = window.Utils.processMessageContent(content);
        const contentDiv = messageElement.querySelector('.message-content') || messageElement;
        contentDiv.innerHTML = '';
        contentDiv.appendChild(processedContent);
        
        // Apply syntax highlighting
        this.applySyntaxHighlighting();
    },

    applySyntaxHighlighting: function() {
        // Apply Prism.js syntax highlighting
        if (window.Prism) {
            window.Prism.highlightAll();
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
            
            // Apply syntax highlighting to loaded messages
            setTimeout(() => this.applySyntaxHighlighting(), 100);
        } catch (error) {
            console.error('Error loading chat history:', error);
        }
    },
    
    addMessage: function(role, content, cached = false, streaming = false) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${role === 'user' ? 'user-message' : 'assistant-message'}`;
        if (cached) messageDiv.classList.add('cached');
        
        if (streaming) {
            // For streaming messages, start with simple text content
            const contentDiv = document.createElement('div');
            contentDiv.className = 'message-content';
            messageDiv.appendChild(contentDiv);
            messageDiv.streamContent = '';
        } else {
            // For complete messages, process with syntax highlighting
            const processedContent = window.Utils.processMessageContent(content);
            messageDiv.appendChild(processedContent);
            
            // Apply syntax highlighting after a short delay
            setTimeout(() => this.applySyntaxHighlighting(), 50);
        }
        
        if (cached && role === 'assistant') {
            const cachedIndicator = document.createElement('div');
            cachedIndicator.className = 'cached-indicator';
            cachedIndicator.innerHTML = '<i class="bi bi-check-circle"></i> Cached response';
            messageDiv.appendChild(cachedIndicator);
        }
        
        this.elements.chatMessages.appendChild(messageDiv);
        this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
        return messageDiv;
    },
    
    sendMessage: function() {
        const message = this.elements.messageInput.value.trim();
        if (message && this.ws && this.ws.readyState === WebSocket.OPEN && !this.isWaitingForResponse) {
            this.isWaitingForResponse = true;
            this.disableInput();
            
            this.ws.send(JSON.stringify({
                type: 'chat',
                message: message
            }));
            
            this.elements.messageInput.value = '';
            this.elements.messageInput.style.height = 'auto'; // Reset height
            this.currentStreamMessage = null;
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

// Export for use
window.ChatPage = ChatPage;