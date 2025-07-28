// =============================================================================
// nginx/static/js/is_approved.js - APPROVED USER CHAT (EXTENDS SharedChatBase)
// =============================================================================

class ApprovedChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'redis';
        this.maxTokens = 2048; // Good limit for approved users
        console.log('✅ Approved chat initialized');
    }

    // Override saveMessage for approved user storage if needed
    saveMessage(role, content) {
        console.log(`💾 Approved user saving ${role} message to Redis (${content.length} chars)`);
        // Could implement Redis storage here in the future
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    if (typeof SharedChatBase === 'undefined') {
        console.error('❌ SharedChatBase not found - is_shared_chat.js must be loaded first');
        return;
    }
    
    if (window.location.pathname === '/chat') {
        window.chatSystem = new ApprovedChat();
        console.log('💬 Approved chat system initialized and ready');
    }
});