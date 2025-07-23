// =============================================================================
// nginx/static/js/is_guest.js - GUEST CHAT (EXTENDS SHARED FUNCTIONALITY)
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

// Guest Chat System - Extends SharedChatBase
class GuestChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'localStorage';
        this.messageLimit = 10;
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.loadGuestHistory();
        this.setupSuggestionChips();
        console.log('👤 Guest chat system initialized');
    }

    // Override saveMessage to use localStorage
    saveMessage(role, content) {
        return GuestChatStorage.saveMessage(role, content);
    }

    loadGuestHistory() {
        const messages = GuestChatStorage.getMessages();
        if (messages.length > 0) {
            const welcomePrompt = document.getElementById('welcome-prompt');
            if (welcomePrompt) welcomePrompt.style.display = 'none';
            
            const messagesContainer = document.getElementById('chat-messages');
            if (messagesContainer) {
                messagesContainer.innerHTML = '';
            }
            
            messages.forEach(msg => {
                this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false, true);
            });
            console.log('📱 Loaded', messages.length, 'messages from localStorage');
        }
    }

    async sendMessage() {
        console.log('🚀 Guest sendMessage called');
        const input = document.getElementById('chat-input');
        if (!input) {
            console.error('Chat input not found');
            return;
        }
        
        const message = input.value.trim();
        
        if (!message) {
            console.warn('Empty message - not sending');
            return;
        }

        if (this.isTyping) {
            console.warn('Already typing - ignoring send request');
            return;
        }

        console.log('📤 Sending message:', message);

        // Check guest message limits
        const guestMessages = GuestChatStorage.getMessages();
        if (guestMessages.length >= this.messageLimit) {
            alert('Guest message limit reached! Register for unlimited access.');
            return;
        }

        // Hide welcome prompt
        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt) welcomePrompt.style.display = 'none';
        
        // Add user message to UI immediately
        this.addMessage('user', message);
        
        // Clear input immediately and reset height
        input.value = '';
        input.style.height = 'auto';
        this.updateCharCount();
        this.autoResizeTextarea();
        
        // Set typing state
        this.isTyping = true;
        this.updateButtons(true);

        // Create abort controller for this request
        this.abortController = new AbortController();
        
        // Add AI message container for streaming
        const aiMessage = this.addMessage('ai', '', true);

        try {
            console.log('🌐 Making SSE request to /api/chat/stream');
            
            const response = await fetch('/api/chat/stream', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'Accept': 'text/event-stream',
                    'Cache-Control': 'no-cache'
                },
                credentials: 'include',
                signal: this.abortController.signal,
                body: JSON.stringify({
                    message: message,
                    stream: true
                })
            });

            console.log('📡 Response status:', response.status);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // Use shared SSE processing from SharedChatBase
            await this.processSSEStream(response, aiMessage);

        } catch (error) {
            console.error('❌ Chat error:', error);
            
            if (error.name === 'AbortError') {
                console.log('🛑 Request was aborted by user');
                this.updateStreamingMessage(aiMessage, '*Request cancelled*');
            } else {
                const errorMessage = `*Error: ${error.message}*`;
                this.updateStreamingMessage(aiMessage, errorMessage);
            }
            
            this.finishStreaming(aiMessage, `Error: ${error.message}`);
        }
    }

    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        const messagesContainer = document.getElementById('chat-messages');
        if (!messagesContainer) {
            console.error('Messages container not found');
            return;
        }

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;
        
        const avatarDiv = document.createElement('div');
        avatarDiv.className = `message-avatar avatar-${sender}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        
        if (sender === 'user') {
            avatarDiv.innerHTML = '<i class="bi bi-person-circle"></i>';
            contentDiv.innerHTML = `<div class="d-flex align-items-center mb-1">
                <i class="bi bi-clock-history text-warning me-2"></i>
                <strong>Guest User</strong>
                <span class="badge bg-warning ms-2">GUEST</span>
            </div>` + (window.marked ? marked.parse(content) : content);
            
            if (!skipStorage) {
                this.saveMessage('user', content);
            }
        } else {
            avatarDiv.innerHTML = '<i class="bi bi-robot"></i>';
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
                
            if (!isStreaming && content.trim() && !skipStorage) {
                this.saveMessage('assistant', content);
            }
        }
        
        messageDiv.appendChild(avatarDiv);
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        console.log(`💬 Added ${sender} message:`, content.substring(0, 50) + '...');
        
        return messageDiv;
    }

    clearChat() {
        if (!confirm('Clear guest chat history? This will only clear your browser storage.')) return;
        
        GuestChatStorage.clearMessages();
        
        const messagesContainer = document.getElementById('chat-messages');
        const welcomePrompt = document.getElementById('welcome-prompt');
        
        if (messagesContainer) messagesContainer.innerHTML = '';
        if (welcomePrompt) welcomePrompt.style.display = 'block';
        
        this.messageCount = 0;
        console.log('🗑️ Guest chat history cleared');
    }
}

// Guest Challenge Response System (for active guests who get challenged)
class GuestChallengeResponder {
    constructor() {
        this.challengeModal = null;
        this.countdownInterval = null;
        this.isListening = false;
        this.init();
    }

    init() {
        this.createChallengeModal();
        this.setupEventListeners();
        this.startChallengeListener();
        console.log('🚨 Guest Challenge Responder initialized');
    }

    createChallengeModal() {
        this.challengeModal = SharedModalUtils.createModal(
            'guest-response-modal',
            '<i class="bi bi-exclamation-triangle"></i> Guest Session Challenge',
            `
            <div class="text-center">
                <div class="mb-3">
                    <i class="bi bi-person-x challenge-icon" style="font-size: 3rem; color: #ffc107;"></i>
                </div>
                <h6 class="text-warning mb-3">Someone wants to use your guest session!</h6>
                <p class="text-light mb-3">
                    Another user is requesting access to your guest slot. 
                    You appear to be inactive. Do you want to continue your session?
                </p>
                <div class="challenge-countdown mb-3">
                    <div class="progress bg-secondary" style="height: 12px; border-radius: 6px;">
                        <div id="response-progress" class="progress-bar bg-warning" role="progressbar" style="width: 100%;"></div>
                    </div>
                    <div class="mt-2">
                        <span class="text-warning">Time remaining: </span>
                        <span id="response-timer" class="text-light fw-bold" style="font-family: monospace; font-size: 1.25rem;">8</span>
                        <span class="text-light"> seconds</span>
                    </div>
                </div>
                <div class="alert alert-warning">
                    <small>
                        <i class="bi bi-info-circle"></i>
                        If you don't respond, you'll be disconnected and the other user will get access.
                    </small>
                </div>
            </div>
            `,
            [
                { id: 'response-accept', type: 'success', text: '<i class="bi bi-check-circle"></i> Continue Session' },
                { id: 'response-reject', type: 'secondary', text: '<i class="bi bi-x-circle"></i> End Session' }
            ]
        );
        
        console.log('📋 Challenge response modal created');
    }

    setupEventListeners() {
        document.getElementById('response-accept').addEventListener('click', () => {
            this.respondToChallenge('accept');
        });

        document.getElementById('response-reject').addEventListener('click', () => {
            this.respondToChallenge('reject');
        });

        // Activity tracking
        ['click', 'keypress', 'scroll', 'mousemove'].forEach(event => {
            document.addEventListener(event, () => {
                this.updateLastActivity();
            });
        });

        // Page visibility changes
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible' && !this.isListening) {
                this.checkForChallenges();
            }
        });
    }

    startChallengeListener() {
        // Check for challenges every 10 seconds when user is active
        setInterval(() => {
            if (this.isUserActive() && !this.isListening) {
                this.checkForChallenges();
            }
        }, 10000);
    }

    isUserActive() {
        const lastActivity = localStorage.getItem('guest_last_activity');
        if (!lastActivity) return true;
        
        const timeSinceActivity = Date.now() - parseInt(lastActivity);
        return timeSinceActivity < 30000; // 30 seconds
    }

    updateLastActivity() {
        localStorage.setItem('guest_last_activity', Date.now().toString());
    }

    async checkForChallenges() {
        try {
            const userInfo = await sharedInterface.checkAuth();
            if (!userInfo || userInfo.user_type !== 'is_guest') return;

            const response = await fetch(`/api/guest/challenge-status?username=${userInfo.username}`, {
                credentials: 'include'
            });

            if (response.ok) {
                const data = await response.json();
                if (data.success && data.challenge_active) {
                    this.handleIncomingChallenge(data.challenge);
                }
            }
        } catch (error) {
            console.warn('Failed to check for challenges:', error);
        }
    }

    handleIncomingChallenge(challenge) {
        if (this.isListening) return;

        console.log('🚨 Incoming challenge:', challenge);
        
        this.isListening = true;
        this.currentChallenge = challenge;
        
        this.challengeModal.show();
        this.startChallengeCountdown(8); // 8 second timeout
        this.showBrowserNotification();
    }

    startChallengeCountdown(totalSeconds) {
        const startTime = Date.now();
        const totalTime = totalSeconds * 1000;
        
        this.countdownInterval = setInterval(() => {
            const now = Date.now();
            const elapsed = now - startTime;
            const remaining = Math.max(0, totalTime - elapsed);
            const seconds = Math.ceil(remaining / 1000);
            
            const timerEl = document.getElementById('response-timer');
            const progressEl = document.getElementById('response-progress');
            
            if (timerEl) timerEl.textContent = seconds;
            if (progressEl) {
                const percentage = (remaining / totalTime) * 100;
                progressEl.style.width = percentage + '%';
                
                if (percentage < 30) {
                    progressEl.classList.remove('bg-warning');
                    progressEl.classList.add('bg-danger');
                } else if (percentage < 60) {
                    progressEl.classList.remove('bg-success');
                    progressEl.classList.add('bg-warning');
                }
            }
            
            if (remaining <= 0) {
                this.handleChallengeTimeout();
            }
        }, 100);
    }

    stopCountdown() {
        if (this.countdownInterval) {
            clearInterval(this.countdownInterval);
            this.countdownInterval = null;
        }
    }

    async handleChallengeTimeout() {
        console.log('⏰ Challenge timeout - user will be disconnected');
        
        this.stopCountdown();
        this.isListening = false;
        this.challengeModal.hide();
        
        sharedInterface.showWarning('Your guest session has been ended due to inactivity. Another user has taken your slot.');
        this.clearUserSession();
        
        setTimeout(() => {
            window.location.href = '/';
        }, 3000);
    }

    async respondToChallenge(response) {
        if (!this.currentChallenge) return;

        console.log('📞 Responding to challenge:', response);
        
        try {
            const apiResponse = await fetch('/api/guest/challenge-response', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({
                    username: this.currentChallenge.username,
                    response: response
                })
            });

            const data = await apiResponse.json();
            
            if (data.success) {
                this.handleChallengeResponse(response, data.challenge_result);
            } else {
                throw new Error(data.error || 'Failed to respond to challenge');
            }
        } catch (error) {
            console.error('Challenge response error:', error);
            sharedInterface.showError('Failed to respond to challenge: ' + error.message);
        }
    }

    handleChallengeResponse(response, result) {
        this.stopCountdown();
        this.isListening = false;
        this.challengeModal.hide();
        
        if (response === 'accept' && result === 'accepted') {
            sharedInterface.showSuccess('Session continued successfully!');
            this.updateLastActivity();
        } else {
            sharedInterface.showInfo('Session ended. Thank you for using ai.junder.uk!');
            this.clearUserSession();
            
            setTimeout(() => {
                window.location.href = '/';
            }, 2000);
        }
    }

    showBrowserNotification() {
        if (!('Notification' in window)) return;
        
        if (Notification.permission === 'granted') {
            new Notification('Guest Session Challenge', {
                body: 'Someone wants to use your guest session. Please respond within 8 seconds.',
                icon: '/favicon.ico',
                tag: 'guest-challenge',
                requireInteraction: true
            });
        } else if (Notification.permission !== 'denied') {
            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    new Notification('Guest Session Challenge', {
                        body: 'Someone wants to use your guest session. Please respond within 8 seconds.',
                        icon: '/favicon.ico',
                        tag: 'guest-challenge',
                        requireInteraction: true
                    });
                }
            });
        }
    }

    clearUserSession() {
        sharedInterface.clearClientData();
        console.log('🧹 Guest session cleared');
    }
}

// Global guest functions
window.downloadGuestHistory = function() {
    const exportData = GuestChatStorage.exportMessages();
    const blob = new Blob([exportData], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = 'guest-chat-history-' + new Date().toISOString().split('T')[0] + '.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    
    console.log('📥 Guest chat history downloaded');
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Always initialize guest functionality on chat page
    if (window.location.pathname === '/chat') {
        // Initialize challenge responder for guest users (server will determine if needed)
        if (!window.guestChallengeResponder) {
            window.guestChallengeResponder = new GuestChallengeResponder();
            console.log('🎯 Challenge responder initialized');
        }
        
        // Initialize main guest chat
        window.guestChat = new GuestChat();
        window.chatSystem = window.guestChat; // For compatibility
        console.log('💬 Guest chat initialized');
    }
});