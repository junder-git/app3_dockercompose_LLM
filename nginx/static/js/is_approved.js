// =============================================================================
// nginx/static/js/is_approved.js - APPROVED USER CHAT (EXTENDS SHARED FUNCTIONALITY)
// =============================================================================

// Approved Chat System - Extends SharedChatBase with Redis features
class ApprovedChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'redis';
        this.messageLimit = 'unlimited';
        this.maxTokens = 2048;
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.loadApprovedHistory();
        this.setupSuggestionChips();
        this.setupApprovedFeatures();
        console.log('✅ Approved chat system initialized');
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
                        this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false, true);
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
        console.log('🔧 Setting up approved user features');
    }

    async sendMessage() {
        console.log('🚀 Approved sendMessage called');
        const input = document.getElementById('chat-input');
        if (!input) {
            console.error('Chat input not found');
            return;
        }
        
        const message = input.value.trim();
        
        if (!message || this.isTyping) {
            console.warn('Empty message or already typing');
            return;
        }

        console.log('📤 Sending approved message:', message);

        // Hide welcome prompt
        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt) welcomePrompt.style.display = 'none';
        
        // Add user message to UI immediately
        this.addMessage('user', message);
        
        // Clear input immediately and reset height
        input.value = '';
        input.style.height = 'auto';
        this.updateCharCount();
        this.autoResizeTextarea();
        
        // Set typing state
        this.isTyping = true;
        this.updateButtons(true);

        // Create abort controller for this request
        this.abortController = new AbortController();
        
        // Add AI message container for streaming
        const aiMessage = this.addMessage('ai', '', true);

        try {
            console.log('🌐 Making approved user SSE request');
            
            const response = await fetch('/api/chat/stream', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'Accept': 'text/event-stream',
                    'Cache-Control': 'no-cache'
                },
                credentials: 'include',
                signal: this.abortController.signal,
                body: JSON.stringify({
                    message: message,
                    include_history: true,  // Approved users get history
                    options: {
                        temperature: 0.7,
                        max_tokens: this.maxTokens  // Higher limit for approved users
                    }
                })
            });

            console.log('📡 Approved user response status:', response.status);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // Use shared SSE processing from SharedChatBase
            await this.processSSEStream(response, aiMessage);

        } catch (error) {
            console.error('❌ Approved chat error:', error);
            
            if (error.name === 'AbortError') {
                console.log('🛑 Request was aborted by user');
                this.updateStreamingMessage(aiMessage, '*Request cancelled*');
            } else {
                const errorMessage = `*Error: ${error.message}*`;
                this.updateStreamingMessage(aiMessage, errorMessage);
            }
            
            this.finishStreaming(aiMessage, `Error: ${error.message}`);
        }
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
                <span class="badge bg-success ms-2">APPROVED</span>
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
            sharedInterface.showSuccess('Chat history cleared successfully');
        } catch (error) {
            console.error('Clear chat error:', error);
            sharedInterface.showError('Failed to clear chat: ' + error.message);
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
            sharedInterface.showSuccess('Chat history exported successfully');
        } else {
            throw new Error('Failed to export chat history');
        }
    } catch (error) {
        console.error('Export error:', error);
        sharedInterface.showError('Export failed: ' + error.message);
    }
};

window.clearHistory = function() {
    if (window.chatSystem && typeof window.chatSystem.clearChat === 'function') {
        window.chatSystem.clearChat();
    }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Only initialize if we're actually an approved user
    sharedInterface.checkAuth()
        .then(data => {
            if (data.success && (data.user_type === 'is_approved' || data.user_type === 'is_admin')) {
                // Initialize main approved chat if on chat page
                if (window.location.pathname === '/chat') {
                    window.approvedChat = new ApprovedChat();
                    window.chatSystem = window.approvedChat; // For compatibility
                    console.log('💬 Approved chat initialized');
                }
            }
        })
        .catch(error => {
            console.warn('Could not check auth status for approved user:', error);
        });
});