// =============================================================================
// chat.js - MAIN CHAT PAGE LOGIC
// =============================================================================

class ChatPage {
    constructor() {
        this.chatSystem = null;
        this.userType = null;
        this.isInitialized = false;
    }

    async init() {
        if (this.isInitialized) return;
        
        console.log('🚀 Initializing chat page...');
        
        try {
            // Determine user type
            await this.determineUserType();
            
            // Initialize appropriate chat system
            await this.initializeChatSystem();
            
            // Setup page-specific UI
            this.setupChatUI();
            
            this.isInitialized = true;
            console.log('✅ Chat page initialized successfully');
            
        } catch (error) {
            console.error('❌ Failed to initialize chat page:', error);
            this.showError('Failed to initialize chat: ' + error.message);
        }
    }

    async determineUserType() {
        // Check auth status to determine user type
        try {
            const response = await fetch('/api/auth/status', { credentials: 'include' });
            const data = await response.json();
            
            if (data.success) {
                this.userType = data.user_type;
                console.log('👤 User type determined:', this.userType);
            } else {
                this.userType = 'guest';
                console.log('👤 Defaulting to guest user type');
            }
        } catch (error) {
            console.warn('Could not determine user type, defaulting to guest:', error);
            this.userType = 'guest';
        }
    }

    async initializeChatSystem() {
        switch (this.userType) {
            case 'is_admin':
                if (window.AdminChat) {
                    this.chatSystem = new window.AdminChat();
                    console.log('👑 Admin chat system loaded');
                } else {
                    throw new Error('AdminChat class not available');
                }
                break;
                
            case 'is_approved':
                if (window.ApprovedChat) {
                    this.chatSystem = new window.ApprovedChat();
                    console.log('✅ Approved chat system loaded');
                } else {
                    throw new Error('ApprovedChat class not available');
                }
                break;
                
            case 'is_guest':
            default:
                if (window.GuestChat) {
                    this.chatSystem = new window.GuestChat();
                    console.log('👤 Guest chat system loaded');
                } else {
                    throw new Error('GuestChat class not available');
                }
                break;
        }
        
        // Make chat system globally available for compatibility
        window.chatSystem = this.chatSystem;
    }

    setupChatUI() {
        // Setup form submission
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault();
                if (this.chatSystem && this.chatSystem.sendMessage) {
                    this.chatSystem.sendMessage();
                }
            });
        }

        // Setup textarea auto-resize and enter key handling
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.addEventListener('input', () => {
                this.autoResizeTextarea();
                this.updateCharCount();
            });
            
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    if (textarea.value.trim() && this.chatSystem && this.chatSystem.sendMessage) {
                        this.chatSystem.sendMessage();
                    }
                }
            });
        }

        // Setup buttons
        const sendButton = document.getElementById('send-button');
        if (sendButton) {
            sendButton.addEventListener('click', (e) => {
                e.preventDefault();
                const textarea = document.getElementById('chat-input');
                if (textarea && textarea.value.trim() && this.chatSystem && this.chatSystem.sendMessage) {
                    this.chatSystem.sendMessage();
                }
            });
        }

        const stopButton = document.getElementById('stop-button');
        if (stopButton) {
            stopButton.addEventListener('click', (e) => {
                e.preventDefault();
                if (this.chatSystem && this.chatSystem.stopGeneration) {
                    this.chatSystem.stopGeneration();
                }
            });
        }

        const clearButton = document.getElementById('clear-chat');
        if (clearButton) {
            clearButton.addEventListener('click', (e) => {
                e.preventDefault();
                if (this.chatSystem && this.chatSystem.clearChat) {
                    this.chatSystem.clearChat();
                }
            });
        }

        // Setup suggestion chips
        this.setupSuggestionChips();
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
                    this.autoResizeTextarea();
                }
            });
        });
    }

    autoResizeTextarea() {
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.style.height = 'auto';
            const maxHeight = 120;
            const newHeight = Math.min(textarea.scrollHeight, maxHeight);
            textarea.style.height = newHeight + 'px';
            textarea.style.overflowY = textarea.scrollHeight > maxHeight ? 'auto' : 'hidden';
        }
    }

    updateCharCount() {
        const textarea = document.getElementById('chat-input');
        const countEl = document.getElementById('char-count');
        
        if (textarea && countEl) {
            countEl.textContent = textarea.value.length;
        }
    }

    showError(message) {
        if (window.sharedInterface && window.sharedInterface.showError) {
            window.sharedInterface.showError(message);
        } else {
            console.error(message);
            alert(message);
        }
    }

    // Public methods for global access
    static getInstance() {
        if (!window.chatPageInstance) {
            window.chatPageInstance = new ChatPage();
        }
        return window.chatPageInstance;
    }
}

// Global functions for HTML onclick compatibility
window.clearHistory = function() {
    const chatPage = ChatPage.getInstance();
    if (chatPage.chatSystem && chatPage.chatSystem.clearChat) {
        chatPage.chatSystem.clearChat();
    }
};

window.exportChats = function() {
    const chatPage = ChatPage.getInstance();
    if (chatPage.chatSystem && chatPage.chatSystem.exportChats) {
        chatPage.chatSystem.exportChats();
    } else if (window.exportChats) {
        // Fallback to user-type specific function
        window.exportChats();
    }
};

window.downloadGuestHistory = function() {
    if (window.GuestChatStorage && window.GuestChatStorage.exportMessages) {
        const exportData = window.GuestChatStorage.exportMessages();
        const blob = new Blob([exportData], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        
        const a = document.createElement('a');
        a.href = url;
        a.download = 'guest-chat-history-' + new Date().toISOString().split('T')[0] + '.json';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', async () => {
    const chatPage = ChatPage.getInstance();
    await chatPage.init();
});

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { ChatPage };
}