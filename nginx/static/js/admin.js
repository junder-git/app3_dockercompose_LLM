// =============================================================================
// nginx/static/js/admin.js - ADMIN EXTENSIONS (only admins get this)
// =============================================================================

// Admin Chat System - extends ApprovedChat with admin features
class AdminChat extends ApprovedChat {
    constructor() {
        super();
        this.isAdmin = true;
        this.messageLimit = 'unlimited';
        console.log('👑 Admin chat system initialized');
    }

    init() {
        super.init();
        this.setupAdminFeatures();
        this.loadAdminData();
    }

    setupAdminFeatures() {
        console.log('🛠️ Setting up admin features');
        
        // Add admin-specific event listeners
        this.setupAdminControls();
        this.setupSystemMonitoring();
    }

    setupAdminControls() {
        // Admin can see system information
        this.addAdminInfo();
    }

    setupSystemMonitoring() {
        // Monitor system stats
        setInterval(() => {
            this.updateSystemStats();
        }, 30000); // Update every 30 seconds
    }

    addAdminInfo() {
        const chatContainer = document.querySelector('.chat-container');
        if (chatContainer) {
            const adminInfo = document.createElement('div');
            adminInfo.className = 'admin-info';
            adminInfo.innerHTML = `
                <div class="alert alert-info">
                    <i class="bi bi-info-circle"></i> 
                    <strong>Admin Mode:</strong> Full system access enabled
                </div>
            `;
            chatContainer.insertBefore(adminInfo, chatContainer.firstChild);
        }
    }

    async loadAdminData() {
        try {
            const response = await fetch('/api/admin/stats', { credentials: 'include' });
            if (response.ok) {
                const data = await response.json();
                this.displayAdminStats(data);
            }
        } catch (error) {
            console.warn('Could not load admin data:', error);
        }
    }

    displayAdminStats(stats) {
        console.log('📊 Admin stats loaded:', stats);
        // Display stats in admin interface
    }

    async updateSystemStats() {
        try {
            const response = await fetch('/api/admin/stats', { credentials: 'include' });
            if (response.ok) {
                const data = await response.json();
                // Update system stats display
                console.log('🔄 System stats updated');
            }
        } catch (error) {
            console.warn('Stats update failed:', error);
        }
    }

    addMessage(sender, content, isStreaming = false) {
        const messagesContainer = document.getElementById('chat-messages');
        if (!messagesContainer) return;

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        
        if (sender === 'user') {
            // Show as admin user
            contentDiv.innerHTML = `<div class="d-flex align-items-center mb-1">
                <i class="bi bi-shield-check text-danger me-2"></i>
                <strong>Admin User</strong>
                <span class="badge bg-danger ms-2">ADMIN</span>
            </div>` + (window.marked ? marked.parse(content) : content);
        } else {
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
        }
        
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        return messageDiv;
    }

    async sendMessage() {
        const input = document.getElementById('chat-input');
        const message = input?.value?.trim();
        
        if (!message || this.isTyping) return;

        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt) welcomePrompt.style.display = 'none';
        
        this.addMessage('user', message);
        input.value = '';
        this.updateCharCount();
        
        this.isTyping = true;
        this.updateButtons(true);

        this.abortController = new AbortController();
        const aiMessage = this.addMessage('ai', '', true);
        let accumulated = '';

        try {
            const response = await fetch('/api/chat/stream', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                signal: this.abortController.signal,
                body: JSON.stringify({
                    message: message,
                    include_history: true,  // Admin gets full history
                    options: {
                        temperature: 0.7,
                        max_tokens: 4096  // Highest limit for admins
                    }
                })
            });

            if (!response.ok) throw new Error('HTTP ' + response.status);

            const reader = response.body.getReader();
            const decoder = new TextDecoder();

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                const chunk = decoder.decode(value, { stream: true });
                const lines = chunk.split('\n');

                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        const jsonStr = line.slice(6);
                        if (jsonStr === '[DONE]') {
                            this.finishStreaming(aiMessage, accumulated);
                            return;
                        }

                        try {
                            const data = JSON.parse(jsonStr);
                            if (data.content) {
                                accumulated += data.content;
                                this.updateStreamingMessage(aiMessage, accumulated);
                            }
                        } catch (e) {}
                    }
                }
            }
        } catch (error) {
            if (error.name !== 'AbortError') {
                console.error('Admin chat error:', error);
                this.updateStreamingMessage(aiMessage, '*Admin Error: ' + error.message + '*');
            }
            this.finishStreaming(aiMessage, accumulated);
        }
    }
}

// Admin-specific functions
window.manageUsers = function() {
    window.open('/admin', '_blank');
};

window.viewSystemLogs = async function() {
    try {
        const response = await fetch('/api/admin/logs', { credentials: 'include' });
        if (response.ok) {
            const data = await response.json();
            console.log('📜 System logs:', data);
            // Show logs in modal or new window
        }
    } catch (error) {
        console.error('Failed to load system logs:', error);
    }
};

window.exportAdminChats = async function() {
    try {
        const response = await fetch('/api/chat/history?limit=10000', {
            credentials: 'include'
        });
        
        if (response.ok) {
            const data = await response.json();
            const exportData = {
                userType: 'admin',
                exportedAt: new Date().toISOString(),
                messageCount: data.messages.length,
                messages: data.messages,
                storage: 'Redis',
                adminFeatures: true,
                note: 'Admin user chat history with full system access'
            };

            const blob = new Blob([JSON.stringify(exportData, null, 2)], { 
                type: 'application/json' 
            });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'admin-chat-history-' + new Date().toISOString().split('T')[0] + '.json';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
            console.log('👑 Admin chat history exported');
        } else {
            throw new Error('Failed to export admin chat history');
        }
    } catch (error) {
        console.error('Admin export error:', error);
        alert('Admin export failed: ' + error.message);
    }
};

