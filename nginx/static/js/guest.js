// =============================================================================
// nginx/static/js/guest.js - BASE FUNCTIONALITY (always loaded) - FIXED
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
        // FIXED: Prevent form submission from refreshing page
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault(); // Prevent page refresh
                e.stopPropagation(); // Stop event bubbling
                this.sendMessage();
                return false; // Extra insurance
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
        
        // FIXED: Better Enter key handling
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.addEventListener('input', (e) => this.updateCharCount());
            
            // FIXED: Proper Enter key handling
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    if (e.shiftKey) {
                        // Shift+Enter: Allow new line (don't prevent default)
                        return;
                    } else {
                        // Enter only: Send message
                        e.preventDefault();
                        e.stopPropagation();
                        this.sendMessage();
                        return false;
                    }
                }
            });

            // FIXED: Prevent form submission on Enter
            textarea.addEventListener('keypress', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    return false;
                }
            });
        }

        // FIXED: Prevent any button clicks from submitting forms
        const sendButton = document.getElementById('send-button');
        if (sendButton) {
            sendButton.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.sendMessage();
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
            
            // Clear existing messages first to prevent duplicates
            const messagesContainer = document.getElementById('chat-messages');
            if (messagesContainer) {
                messagesContainer.innerHTML = '';
            }
            
            messages.forEach(msg => {
                this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false, true); // Skip storage save
            });
            console.log('📱 Loaded', messages.length, 'messages from localStorage');
        }
    }

    async sendMessage() {
        console.log('🚀 sendMessage called');
        
        const input = document.getElementById('chat-input');
        if (!input) {
            console.error('Chat input not found');
            return;
        }

        const message = input.value.trim();
        
        if (!message) {
            console.warn('Empty message');
            return;
        }

        if (this.isTyping) {
            console.warn('Already typing');
            return;
        }

        console.log('📤 Sending message:', message);

        // Check guest message limits
        const guestMessages = GuestChatStorage.getMessages();
        if (guestMessages.length >= 10) {
            alert('Guest message limit reached! Register for unlimited access.');
            return;
        }

        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt) welcomePrompt.style.display = 'none';
        
        // Add user message to UI
        this.addMessage('user', message);
        
        // Clear input
        input.value = '';
        this.updateCharCount();
        
        // Set typing state
        this.isTyping = true;
        this.updateButtons(true);

        this.abortController = new AbortController();
        const aiMessage = this.addMessage('ai', '', true);
        let accumulated = '';

        try {
            // FIXED: Simplified fetch for testing
            const response = await fetch('/api/chat/stream', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'Accept': 'text/event-stream'
                },
                credentials: 'include',
                signal: this.abortController.signal,
                body: JSON.stringify({
                    message: message,
                    options: {
                        temperature: 0.7,
                        max_tokens: 1024
                    }
                })
            });

            console.log('📡 Response status:', response.status);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // FIXED: Handle streaming response
            const reader = response.body.getReader();
            const decoder = new TextDecoder();

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                const chunk = decoder.decode(value, { stream: true });
                console.log('📦 Chunk received:', chunk);
                
                const lines = chunk.split('\n');

                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        const jsonStr = line.slice(6);
                        if (jsonStr === '[DONE]') {
                            console.log('✅ Stream completed');
                            this.finishStreaming(aiMessage, accumulated);
                            return;
                        }

                        try {
                            const data = JSON.parse(jsonStr);
                            if (data.content) {
                                accumulated += data.content;
                                this.updateStreamingMessage(aiMessage, accumulated);
                            }
                        } catch (e) {
                            console.warn('JSON parse error:', e);
                        }
                    }
                }
            }

            // If we get here, stream ended without [DONE]
            this.finishStreaming(aiMessage, accumulated);

        } catch (error) {
            console.error('❌ Chat error:', error);
            
            if (error.name !== 'AbortError') {
                const errorMessage = `*Error: ${error.message}*`;
                this.updateStreamingMessage(aiMessage, errorMessage);
            }
            
            this.finishStreaming(aiMessage, accumulated || `Error: ${error.message}`);
        }
    }

    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        const messagesContainer = document.getElementById('chat-messages');
        if (!messagesContainer) {
            console.error('Messages container not found');
            return;
        }

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;
        
        const avatarDiv = document.createElement('div');
        avatarDiv.className = `message-avatar avatar-${sender}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        
        if (sender === 'user') {
            avatarDiv.innerHTML = '<i class="bi bi-person-circle"></i>';
            contentDiv.innerHTML = window.marked ? marked.parse(content) : content;
            
            // Save to localStorage only if not skipping storage (i.e., not loading from storage)
            if (!skipStorage) {
                GuestChatStorage.saveMessage('user', content);
            }
        } else {
            avatarDiv.innerHTML = '<i class="bi bi-robot"></i>';
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
                
            if (!isStreaming && content.trim() && !skipStorage) {
                GuestChatStorage.saveMessage('assistant', content);
            }
        }
        
        messageDiv.appendChild(avatarDiv);
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        console.log(`💬 Added ${sender} message:`, content.substring(0, 50) + '...');
        
        return messageDiv;
    }

    updateStreamingMessage(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const parsedContent = window.marked ? marked.parse(content) : content;
            streamingEl.innerHTML = parsedContent + '<span class="cursor">▋</span>';
            
            // Auto-scroll
            const messagesContainer = document.getElementById('chat-messages');
            if (messagesContainer) {
                messagesContainer.scrollTop = messagesContainer.scrollHeight;
            }
        }
    }

    finishStreaming(messageDiv, finalContent) {
        console.log('🏁 Finishing stream with content:', finalContent.substring(0, 50) + '...');
        
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const parsedContent = window.marked ? marked.parse(finalContent) : finalContent;
            streamingEl.innerHTML = parsedContent;
            
            // Only save if content exists and we're not loading from storage
            if (finalContent.trim()) {
                GuestChatStorage.saveMessage('assistant', finalContent);
            }
        }
        
        this.isTyping = false;
        this.updateButtons(false);
        
        // Final scroll
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            messagesContainer.scrollTop = messagesContainer.scrollHeight;
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

// FIXED: Auto-initialize chat system when page loads
document.addEventListener('DOMContentLoaded', () => {
    // Only initialize if we're on a chat page
    if (document.getElementById('chat-messages') || document.getElementById('chat-form')) {
        console.log('🎯 Initializing chat system');
        window.chatSystem = new GuestChat();
    }
});