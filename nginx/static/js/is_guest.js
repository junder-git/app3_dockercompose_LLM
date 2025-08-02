// =============================================================================
// SIMPLIFIED is_guest.js - Remove challenge system complexity
// =============================================================================

class GuestChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'localStorage';
        this.maxTokens = 1024;
        console.log('👤 Guest chat initialized');
    }

    // Simple guest storage override
    saveMessage(role, content) {
        console.log(`💾 Guest message saved to localStorage (${content.length} chars)`);
        // Server handles the actual saving via callbacks
    }

    clearChat() {
        if (!confirm('Clear guest chat history?')) return;
        
        const messagesContainer = this.getMessagesContainer();
        const welcomePrompt = document.getElementById('welcome-prompt');
        
        if (messagesContainer) {
            messagesContainer.querySelectorAll('.message').forEach(msg => msg.remove());
        }
        if (welcomePrompt) welcomePrompt.style.display = 'block';
        
        console.log('🗑️ Guest chat cleared');
    }
}

// Simple guest download function
window.downloadGuestHistory = () => {
    const messages = Array.from(document.querySelectorAll('.message')).map(msg => ({
        role: msg.classList.contains('message-user') ? 'user' : 'assistant',
        content: msg.querySelector('.message-content').textContent
    }));
    
    const data = {
        export_type: 'guest_chat',
        exported_at: new Date().toISOString(),
        message_count: messages.length,
        messages
    };
    
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = `guest-chat-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
};

// Initialize guest chat
document.addEventListener('DOMContentLoaded', () => {
    if (window.location.pathname === '/chat' && typeof SharedChatBase !== 'undefined') {
        window.chatSystem = new GuestChat();
        console.log('💬 Guest chat system initialized');
    }
});