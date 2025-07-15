// =============================================================================
// nginx/static/js/approved.js - APPROVED USER EXTENSIONS (approved + admin get this)
// =============================================================================

// Approved Chat System - extends GuestChat with Redis features
class ApprovedChat extends GuestChat {
    constructor() {
        super();
        this.storageType = 'redis';
        this.messageLimit = 'unlimited';
        console.log('✅ Approved chat system initialized');
    }

    init() {
        super.init();
        this.loadApprovedHistory();
        this.setupApprovedFeatures();
    }

    async loadApprovedHistory() {
        try {
            const response = await fetch('/api/chat/history?limit=50', { credentials: 'include' });
            if (response.ok) {
                const data = await response.json();
                if (data.success && data.messages.length > 0) {
                    const welcomePrompt = document.getElementById('welcome-prompt');
                    if (welcomePrompt) welcomePrompt.style.display = 'none';
                    
                    // Clear any existing messages first to prevent duplicates
                    const messagesContainer = document.getElementById('chat-messages');
                    if (messagesContainer) messagesContainer.innerHTML = '';
                    
                    data.messages.reverse().forEach(msg => {
                        this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false, true); // Skip storage save
                    });
                    console.log('🗄️ Loaded', data.messages.length, 'messages from Redis');
                }
            }
        } catch (error) {
            console.warn('Could not load approved history:', error);
        }
    }

    setupApprovedFeatures() {
        // Enhanced message display for approved users
        this.setupAdvancedFeatures();
    }

    setupAdvancedFeatures() {
        // Add approved-specific features
        console.log('🔧 Setting up approved user features');
    }

    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        const messagesContainer = document.getElementById('chat-messages');
        if (!messagesContainer) return;

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;
        
        const avatarDiv = document.createElement('div');
        avatarDiv.className = `message-avatar avatar-${sender}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        
        if (sender === 'user') {
            avatarDiv.innerHTML = '<i class="bi bi-person-check"></i>';
            contentDiv.innerHTML = `<div class="d-flex align-items-center mb-1">
                <i class="bi bi-person-check text-success me-2"></i>
                <strong>Approved User</strong>
            </div>` + (window.marked ? marked.parse(content) : content);
        } else {
            avatarDiv.innerHTML = '<i class="bi bi-robot"></i>';
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
        }
        
        messageDiv.appendChild(avatarDiv);
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        return messageDiv;
    }

    async sendMessage() {
        const input = document.getElementById('chat-input');
        const message = input?.value?.trim();
        
        if (!message || this.isTyping) return;

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
                    include_history: true,  // Approved users get history
                    options: {
                        temperature: 0.7,
                        max_tokens: 2048  // Higher limit for approved users
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
                console.error('Approved chat error:', error);
                this.updateStreamingMessage(aiMessage, '*Error: ' + error.message + '*');
            }
            this.finishStreaming(aiMessage, accumulated);
        }
    }

    async clearChat() {
        if (!confirm('Clear your Redis chat history? This will permanently delete your saved conversations.')) return;
        
        try {
            const response = await fetch('/api/chat/clear', {
                method: 'POST',
                credentials: 'include'
            });

            if (!response.ok) throw new Error('Failed to clear chat');
            
            const messagesContainer = document.getElementById('chat-messages');
            const welcomePrompt = document.getElementById('welcome-prompt');
            
            if (messagesContainer) messagesContainer.innerHTML = '';
            if (welcomePrompt) welcomePrompt.style.display = 'block';
            
            this.messageCount = 0;
            console.log('🗑️ Approved user chat history cleared from Redis');
        } catch (error) {
            console.error('Clear chat error:', error);
            alert('Failed to clear chat: ' + error.message);
        }
    }
}

// Approved user functions
window.exportChats = async function() {
    try {
        const response = await fetch('/api/chat/history?limit=1000', {
            credentials: 'include'
        });
        
        if (response.ok) {
            const data = await response.json();
            const exportData = {
                userType: 'approved',
                exportedAt: new Date().toISOString(),
                messageCount: data.messages.length,
                messages: data.messages,
                storage: 'Redis',
                note: 'Approved user chat history from Redis database'
            };

            const blob = new Blob([JSON.stringify(exportData, null, 2)], { 
                type: 'application/json' 
            });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'approved-chat-history-' + new Date().toISOString().split('T')[0] + '.json';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
            console.log('📤 Approved user chat history exported');
        } else {
            throw new Error('Failed to export chat history');
        }
    } catch (error) {
        console.error('Export error:', error);
        alert('Export failed: ' + error.message);
    }
};

window.clearHistory = function() {
    if (window.chatSystem && typeof window.chatSystem.clearChat === 'function') {
        window.chatSystem.clearChat();
    }
};