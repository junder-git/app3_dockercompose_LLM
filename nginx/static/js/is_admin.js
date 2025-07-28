// =============================================================================
// nginx/static/js/is_admin.js - ADMIN CHAT WITH REDIS PERSISTENCE
// =============================================================================

class AdminChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'redis';
        this.maxTokens = 4096; // Higher limit for admins
        this.historyLoaded = false;
        console.log('👑 Admin chat initialized with Redis persistence');
    }

    // Load chat history after initialization
    async loadGuestHistory() {
        await this.loadChatHistory();
    }

    // Load chat history from Redis
    async loadChatHistory() {
        if (this.historyLoaded) return;
        
        console.log('📚 Loading admin chat history from Redis...');
        
        try {
            const response = await fetch('/api/chat/history?limit=50', {
                credentials: 'include'
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            const data = await response.json();
            
            if (data.success && data.messages && data.messages.length > 0) {
                console.log(`📚 Loaded ${data.messages.length} messages from Redis`);
                
                // Hide welcome prompt
                const welcomePrompt = document.getElementById('welcome-prompt');
                if (welcomePrompt) {
                    welcomePrompt.style.display = 'none';
                }
                
                // Display messages in chronological order
                for (const msg of data.messages) {
                    this.addMessage(msg.role === 'assistant' ? 'ai' : msg.role, msg.content, false, true);
                }
                
                // Update message count
                this.messageCount = data.messages.length;
                this.updateMessageCountDisplay();
                
                // Scroll to bottom
                setTimeout(() => {
                    this.scrollToBottom();
                }, 100);
                
                // Show success message
                if (typeof sharedInterface !== 'undefined') {
                    sharedInterface.showInfo(`Loaded ${data.messages.length} messages from Redis database`);
                }
            } else {
                console.log('📚 No chat history found in Redis');
            }
        } catch (error) {
            console.error('❌ Failed to load chat history:', error);
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showError('Failed to load chat history: ' + error.message);
            }
        } finally {
            this.historyLoaded = true;
        }
    }

    // Override saveMessage for admin-specific storage
    saveMessage(role, content) {
        console.log(`💾 Admin saving ${role} message to Redis (${content.length} chars)`);
        // Messages are now saved server-side via callbacks in the Lua streaming handler
        return true;
    }

    // Enhanced clear chat with server-side clearing
    async clearChat() {
        if (!confirm('Clear admin chat history? This will permanently delete all messages from the Redis database.')) return;
        
        console.log('🗑️ Clearing admin chat history from Redis...');
        
        try {
            const response = await fetch('/api/chat/clear', {
                method: 'POST',
                credentials: 'include'
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            const data = await response.json();
            
            if (data.success) {
                // Clear UI
                const messagesContainer = this.getMessagesContainer();
                const welcomePrompt = document.getElementById('welcome-prompt');
                
                if (messagesContainer) {
                    const messages = messagesContainer.querySelectorAll('.message');
                    messages.forEach(msg => msg.remove());
                }
                
                if (welcomePrompt) {
                    welcomePrompt.style.display = 'block';
                }
                
                this.messageCount = 0;
                this.updateMessageCountDisplay();
                this.historyLoaded = false;
                
                console.log(`✅ Cleared ${data.deleted_messages || 0} messages from Redis`);
                
                if (typeof sharedInterface !== 'undefined') {
                    sharedInterface.showSuccess(`Chat history cleared! Deleted ${data.deleted_messages || 0} messages from Redis database.`);
                }
            } else {
                throw new Error(data.error || 'Failed to clear chat history');
            }
        } catch (error) {
            console.error('❌ Failed to clear chat history:', error);
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showError('Failed to clear chat history: ' + error.message);
            }
        }
    }

    // Update message count display
    updateMessageCountDisplay() {
        const countEl = document.getElementById('message-count');
        if (countEl) {
            countEl.textContent = this.messageCount;
        }
    }

    // Admin-specific functions
    async exportChats(format = 'json') {
        console.log(`📥 Exporting admin chats as ${format}...`);
        
        try {
            const response = await fetch(`/api/chat/export?format=${format}`, {
                credentials: 'include'
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            // Get filename from Content-Disposition header
            const contentDisposition = response.headers.get('Content-Disposition');
            let filename = `admin-chat-export-${new Date().toISOString().split('T')[0]}.${format}`;
            
            if (contentDisposition) {
                const filenameMatch = contentDisposition.match(/filename="(.+)"/);
                if (filenameMatch) {
                    filename = filenameMatch[1];
                }
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
            
            console.log('📥 Admin chat export completed');
            
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showSuccess('Chat history exported successfully!');
            }
        } catch (error) {
            console.error('❌ Failed to export chats:', error);
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showError('Failed to export chat history: ' + error.message);
            }
        }
    }

    async searchHistory(query) {
        if (!query || query.trim() === '') {
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showWarning('Please enter a search query');
            }
            return;
        }

        console.log(`🔍 Searching admin chat history for: ${query}`);
        
        try {
            const response = await fetch(`/api/chat/search?q=${encodeURIComponent(query)}&limit=20`, {
                credentials: 'include'
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            const data = await response.json();
            
            if (data.success) {
                console.log(`🔍 Found ${data.result_count} search results`);
                
                // Display search results (could be implemented in a modal)
                this.displaySearchResults(data.results, query);
                
                if (typeof sharedInterface !== 'undefined') {
                    sharedInterface.showInfo(`Found ${data.result_count} messages containing "${query}"`);
                }
            } else {
                throw new Error(data.error || 'Search failed');
            }
        } catch (error) {
            console.error('❌ Search failed:', error);
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showError('Search failed: ' + error.message);
            }
        }
    }

    displaySearchResults(results, query) {
        // Simple console display for now - could be enhanced with a modal
        console.log(`🔍 Search results for "${query}":`);
        results.forEach((result, index) => {
            console.log(`${index + 1}. [${result.iso_timestamp}] ${result.role.toUpperCase()}: ${result.content.substring(0, 100)}...`);
        });
    }
}

// Global admin functions
window.exportAdminChats = function(format = 'json') {
    if (window.chatSystem && window.chatSystem.exportChats) {
        window.chatSystem.exportChats(format);
    } else {
        console.error('❌ Chat system not available for export');
    }
};

window.searchAdminHistory = function() {
    const query = prompt('Enter search query:');
    if (query && window.chatSystem && window.chatSystem.searchHistory) {
        window.chatSystem.searchHistory(query);
    }
};

window.manageUsers = function() {
    window.location.href = '/dash';
};

window.viewSystemLogs = function() {
    if (typeof sharedInterface !== 'undefined') {
        sharedInterface.showInfo('System logs feature coming soon!');
    }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', async () => {
    if (typeof SharedChatBase === 'undefined') {
        console.error('❌ SharedChatBase not found - is_shared_chat.js must be loaded first');
        return;
    }
    
    if (window.location.pathname === '/chat') {
        window.chatSystem = new AdminChat();
        
        // Load chat history after initialization
        await window.chatSystem.loadChatHistory();
        
        console.log('💬 Admin chat system initialized with Redis persistence');
    }
});