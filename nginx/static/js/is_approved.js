// =============================================================================
// SIMPLIFIED is_approved.js - Same pattern
// =============================================================================

class ApprovedChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'redis';
        this.maxTokens = 2048;
        console.log('✅ Approved chat initialized');
    }

    // Same methods as AdminChat but with approved user limits
    async loadGuestHistory() {
        await this.loadChatHistory();
    }

    async loadChatHistory() {
        // Same as admin but different endpoint behavior
        try {
            const response = await fetch('/api/chat/history?limit=50', { credentials: 'include' });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const data = await response.json();
            if (data.success && data.messages?.length > 0) {
                const welcomePrompt = document.getElementById('welcome-prompt');
                if (welcomePrompt) welcomePrompt.style.display = 'none';
                
                for (const msg of data.messages) {
                    this.addMessage(msg.role === 'assistant' ? 'ai' : msg.role, msg.content, false, true);
                }
                
                setTimeout(() => this.scrollToBottom(), 100);
            }
        } catch (error) {
            console.error('❌ Failed to load chat history:', error);
        }
    }

    async clearChat() {
        if (!confirm('Clear chat history?')) return;
        
        try {
            const response = await fetch('/api/chat/clear', { method: 'POST', credentials: 'include' });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const data = await response.json();
            if (data.success) {
                const messagesContainer = this.getMessagesContainer();
                const welcomePrompt = document.getElementById('welcome-prompt');
                
                if (messagesContainer) {
                    messagesContainer.querySelectorAll('.message').forEach(msg => msg.remove());
                }
                if (welcomePrompt) welcomePrompt.style.display = 'block';
            }
        } catch (error) {
            console.error('❌ Failed to clear chat history:', error);
        }
    }

    async exportChats(format = 'json') {
        // Same as admin export
        try {
            const response = await fetch(`/api/chat/export?format=${format}`, { credentials: 'include' });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const blob = await response.blob();
            const url = URL.createObjectURL(blob);
            
            const a = document.createElement('a');
            a.href = url;
            a.download = `chat-export-${new Date().toISOString().split('T')[0]}.${format}`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        } catch (error) {
            console.error('❌ Export failed:', error);
        }
    }
}

// Global functions for approved users
window.exportChats = (format = 'json') => {
    if (window.chatSystem?.exportChats) {
        window.chatSystem.exportChats(format);
    }
};

window.clearHistory = () => {
    if (window.chatSystem?.clearChat) {
        window.chatSystem.clearChat();
    }
};

// Initialize approved chat
document.addEventListener('DOMContentLoaded', async () => {
    if (window.location.pathname === '/chat' && typeof SharedChatBase !== 'undefined') {
        window.chatSystem = new ApprovedChat();
        await window.chatSystem.loadChatHistory();
        console.log('💬 Approved user chat system initialized');
    }
});