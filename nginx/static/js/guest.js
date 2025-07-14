// =============================================================================
// nginx/static/js/guest.js - BASE FUNCTIONALITY (always loaded)
// =============================================================================

// Guest Chat Storage - localStorage only
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
            console.warn('Failed to save guest message:', error);
            return false;
        }
    },

    getMessages() {
        try {
            const stored = localStorage.getItem(this.STORAGE_KEY);
            return stored ? JSON.parse(stored) : [];
        } catch (error) {
            console.warn('Failed to load guest messages:', error);
            return [];
        }
    },

    clearMessages() {
        try {
            localStorage.removeItem(this.STORAGE_KEY);
            return true;
        } catch (error) {
            console.warn('Failed to clear guest messages:', error);
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
            note: 'Guest session - stored in browser localStorage only'
        };
        return JSON.stringify(exportData, null, 2);
    }
};

// Base Chat System (used by all user types)
class GuestChat {
    constructor() {
        this.isTyping = false;
        this.abortController = null;
        this.messageCount = 0;
        this.storageType = 'localStorage';
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.loadGuestHistory();
        this.setupSuggestionChips();
        console.log('👤 Guest chat system initialized');
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

    loadGuestHistory() {
        const messages = GuestChatStorage.getMessages();
        if (messages.length > 0) {
            const welcomePrompt = document.getElementById('welcome-prompt');
            if (welcomePrompt) welcomePrompt.style.display = 'none';
            
            messages.forEach(msg => {
                this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false);
            });
            console.log('📱 Loaded', messages.length, 'messages from localStorage');
        }
    }

    async sendMessage() {
        const input = document.getElementById('chat-input');
        const message = input?.value?.trim();
        
        if (!message || this.isTyping) return;

        // Check guest message limits
        const guestMessages = GuestChatStorage.getMessages();
        if (guestMessages.length >= 10) {
            alert('Guest message limit reached! Register for unlimited access.');
            return;
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
            const response = await fetch('/api/chat/stream', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                signal: this.abortController.signal,
                body: JSON.stringify({
                    message: message,
                    options: {
                        temperature: 0.7,
                        max_tokens: 1024  // Limited for guests
                    }
                })
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
                console.error('Guest chat error:', error);
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
            contentDiv.innerHTML = `<div class="d-flex align-items-center mb-1">
                <i class="bi bi-person-circle text-warning me-2"></i>
                <strong>Guest User</strong>
            </div>` + (window.marked ? marked.parse(content) : content);
            
            GuestChatStorage.saveMessage('user', content);
        } else {
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
                
            if (!isStreaming && content.trim()) {
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
            
            if (finalContent.trim()) {
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

    clearChat() {
        if (!confirm('Clear guest chat history? This will only clear your browser storage.')) return;
        
        GuestChatStorage.clearMessages();
        
        const messagesContainer = document.getElementById('chat-messages');
        const welcomePrompt = document.getElementById('welcome-prompt');
        
        if (messagesContainer) messagesContainer.innerHTML = '';
        if (welcomePrompt) welcomePrompt.style.display = 'block';
        
        this.messageCount = 0;
        console.log('🗑️ Guest chat history cleared');
    }
}

// Global guest functions
window.downloadGuestHistory = function() {
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

window.logout = function() {
    // Clear guest session
    GuestChatStorage.clearMessages();
    
    // Clear cookies
    const cookies = ['access_token', 'guest_token', 'session'];
    cookies.forEach(name => {
        document.cookie = name + '=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
    });
    
    // Clear storage
    localStorage.clear();
    sessionStorage.clear();
    
    window.location.href = '/';
};