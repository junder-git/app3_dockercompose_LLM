// =============================================================================
// nginx/static/js/is_approved.js - APPROVED USER CHAT WITH REDIS PERSISTENCE
// =============================================================================

class ApprovedChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'redis';
        this.maxTokens = 2048; // Good limit for approved users
        this.historyLoaded = false;
        console.log('✅ Approved chat initialized with Redis persistence');
    }

    // Load chat history after initialization
    async loadGuestHistory() {
        await this.loadChatHistory();
    }

    // Load chat history from Redis
    async loadChatHistory() {
        if (this.historyLoaded) return;
        
        console.log('📚 Loading approved user chat history from Redis...');
        
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

    // Override saveMessage for approved user storage
    saveMessage(role, content) {
        console.log(`💾 Approved user saving ${role} message to Redis (${content.length} chars)`);
        // Messages are now saved server-side via callbacks in the Lua streaming handler
        return true;
    }

    // Enhanced clear chat with server-side clearing
    async clearChat() {
        if (!confirm('Clear chat history? This will permanently delete all messages from the Redis database.')) return;
        
        console.log('🗑️ Clearing approved user chat history from Redis...');
        
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

    // Approved user functions
    async exportChats(format = 'json') {
        console.log(`📥 Exporting approved user chats as ${format}...`);
        
        try {
            const response = await fetch(`/api/chat/export?format=${format}`, {
                credentials: 'include'
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            // Get filename from Content-Disposition header
            const contentDisposition = response.headers.get('Content-Disposition');
            let filename = `chat-export-${new Date().toISOString().split('T')[0]}.${format}`;
            
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
            
            console.log('📥 Approved user chat export completed');
            
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

        console.log(`🔍 Searching approved user chat history for: ${query}`);
        
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

    async getChatStats() {
        try {
            const response = await fetch('/api/chat/stats', {
                credentials: 'include'
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            const data = await response.json();
            
            if (data.success) {
                console.log('📊 Chat statistics:', data.stats);
                return data.stats;
            } else {
                throw new Error(data.error || 'Failed to get chat stats');
            }
        } catch (error) {
            console.error('❌ Failed to get chat stats:', error);
            return null;
        }
    }
}

// Global approved user functions
window.exportChats = function(format = 'json') {
    if (window.chatSystem && window.chatSystem.exportChats) {
        window.chatSystem.exportChats(format);
    } else {
        console.error('❌ Chat system not available for export');
    }
};

window.clearHistory = function() {
    if (window.chatSystem && window.chatSystem.clearChat) {
        window.chatSystem.clearChat();
    } else {
        console.error('❌ Chat system not available for clearing');
    }
};

window.searchHistory = function() {
    const query = prompt('Enter search query:');
    if (query && window.chatSystem && window.chatSystem.searchHistory) {
        window.chatSystem.searchHistory(query);
    }
};

window.viewChatStats = async function() {
    if (window.chatSystem && window.chatSystem.getChatStats) {
        const stats = await window.chatSystem.getChatStats();
        if (stats) {
            const message = `Chat Statistics:\n- Total messages: ${stats.message_count}\n- Last activity: ${stats.last_message_time ? new Date(stats.last_message_time * 1000).toLocaleString() : 'N/A'}\n- Storage: Redis database`;
            alert(message);
        }
    }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', async () => {
    if (typeof SharedChatBase === 'undefined') {
        console.error('❌ SharedChatBase not found - is_shared_chat.js must be loaded first');
        return;
    }
    
    if (window.location.pathname === '/chat') {
        window.chatSystem = new ApprovedChat();
        
        // Load chat history after initialization
        await window.chatSystem.loadChatHistory();
        
        console.log('💬 Approved user chat system initialized with Redis persistence');
    }
});