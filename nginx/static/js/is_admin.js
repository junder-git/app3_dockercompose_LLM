// =============================================================================
// nginx/static/js/admin.js - ADMIN CHAT (EXTENDS SharedChatBase)
// =============================================================================

class AdminChat extends SharedChatBase {
    constructor() {
        super();
        console.log('👑 Admin chat initialized');
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    if (typeof SharedChatBase === 'undefined') {
        console.error('❌ SharedChatBase not found - shared_chat.js must be loaded first');
        return;
    }
    
    if (window.location.pathname === '/chat') {
        window.chatSystem = new AdminChat();
        console.log('💬 Admin chat system initialized');
    }
});