// =============================================================================
// SIMPLIFIED is_admin.js - Remove redundant auth checks
// =============================================================================

class AdminChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'redis';
        this.maxTokens = 4096;
        console.log('👑 Admin chat initialized');
    }

    async loadGuestHistory() {
        // Load from Redis via server
        await this.loadChatHistory();
    }

    async loadChatHistory() {
        try {
            const response = await fetch('/api/chat/history?limit=50', {
                credentials: 'include'
            });
            
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const data = await response.json();
            
            if (data.success && data.messages?.length > 0) {
                console.log(`📚 Loaded ${data.messages.length} messages from Redis`);
                
                const welcomePrompt = document.getElementById('welcome-prompt');
                if (welcomePrompt) welcomePrompt.style.display = 'none';
                
                for (const msg of data.messages) {
                    this.addMessage(msg.role === 'assistant' ? 'ai' : msg.role, msg.content, false, true);
                }
                
                setTimeout(() => this.scrollToBottom(), 100);
                
                if (window.sharedInterface) {
                    sharedInterface.showInfo(`Loaded ${data.messages.length} messages from Redis`);
                }
            }
        } catch (error) {
            console.error('❌ Failed to load chat history:', error);
        }
    }

    async clearChat() {
        if (!confirm('Clear admin chat history? This will permanently delete all messages from Redis.')) return;
        
        try {
            const response = await fetch('/api/chat/clear', {
                method: 'POST',
                credentials: 'include'
            });
            
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const data = await response.json();
            
            if (data.success) {
                const messagesContainer = this.getMessagesContainer();
                const welcomePrompt = document.getElementById('welcome-prompt');
                
                if (messagesContainer) {
                    messagesContainer.querySelectorAll('.message').forEach(msg => msg.remove());
                }
                if (welcomePrompt) welcomePrompt.style.display = 'block';
                
                if (window.sharedInterface) {
                    sharedInterface.showSuccess(`Chat history cleared! Deleted ${data.deleted_messages || 0} messages.`);
                }
            }
        } catch (error) {
            console.error('❌ Failed to clear chat history:', error);
        }
    }

    async exportChats(format = 'json') {
        try {
            const response = await fetch(`/api/chat/export?format=${format}`, {
                credentials: 'include'
            });
            
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            
            const contentDisposition = response.headers.get('Content-Disposition');
            let filename = `admin-chat-export-${new Date().toISOString().split('T')[0]}.${format}`;
            
            if (contentDisposition) {
                const match = contentDisposition.match(/filename="(.+)"/);
                if (match) filename = match[1];
            }
            
            const blob = await response.blob();
            const url = URL.createObjectURL(blob);
            
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
            if (window.sharedInterface) {
                sharedInterface.showSuccess('Chat history exported successfully!');
            }
        } catch (error) {
            console.error('❌ Export failed:', error);
        }
    }
}

// Global functions
window.exportAdminChats = (format = 'json') => {
    if (window.chatSystem?.exportChats) {
        window.chatSystem.exportChats(format);
    }
};

window.manageUsers = () => window.location.href = '/dash';

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    if (window.location.pathname === '/chat' && typeof SharedChatBase !== 'undefined') {
        window.chatSystem = new AdminChat();
        await window.chatSystem.loadChatHistory();
        console.log('💬 Admin chat system initialized');
    }
});