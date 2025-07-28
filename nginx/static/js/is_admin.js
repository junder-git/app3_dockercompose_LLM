// =============================================================================
// nginx/static/js/is_admin.js - ADMIN CHAT (EXTENDS SharedChatBase)
// =============================================================================

class AdminChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'redis';
        this.maxTokens = 4096; // Higher limit for admins
        console.log('👑 Admin chat initialized');
    }

    // Override saveMessage for admin-specific storage if needed
    saveMessage(role, content) {
        console.log(`💾 Admin saving ${role} message to Redis (${content.length} chars)`);
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
        window.chatSystem = new AdminChat();
        console.log('💬 Admin chat system initialized and ready');
    }
});