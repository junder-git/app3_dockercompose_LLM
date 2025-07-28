// =============================================================================
// nginx/static/js/approved.js - APPROVED USER CHAT (EXTENDS SharedChatBase)
// =============================================================================

class ApprovedChat extends SharedChatBase {
    constructor() {
        super();
        console.log('✅ Approved chat initialized');
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    if (typeof SharedChatBase === 'undefined') {
        console.error('❌ SharedChatBase not found - shared_chat.js must be loaded first');
        return;
    }
    
    if (window.location.pathname === '/chat') {
        window.chatSystem = new ApprovedChat();
        console.log('💬 Approved chat system initialized');
    }
});