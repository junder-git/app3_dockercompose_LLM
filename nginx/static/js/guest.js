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