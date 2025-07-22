// =============================================================================
// nginx/static/js/is_guest.js - GUEST CHAT FUNCTIONALITY ONLY
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

// Guest Chat System (base class used by all user types)
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
        console.log('👤 Guest chat system initialized');
    }

    setupEventListeners() {
        // Prevent form submission from refreshing page
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.sendMessage();
                return false;
            });
        }

        const stopButton = document.getElementById('stop-button');
        if (stopButton) {
            stopButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.stopGeneration();
            });
        }

        const clearButton = document.getElementById('clear-chat');
        if (clearButton) {
            clearButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.clearChat();
            });
        }
        
        // Proper Enter key handling for textarea
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            // Handle input changes for character count and auto-resize
            textarea.addEventListener('input', (e) => {
                this.updateCharCount();
                this.autoResizeTextarea();
            });
            
            // Enter key handling
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    if (e.shiftKey) {
                        // Shift+Enter: Allow new line
                        return;
                    } else {
                        // Enter only: Send message
                        e.preventDefault();
                        e.stopPropagation();
                        
                        if (textarea.value.trim()) {
                            this.sendMessage();
                        }
                        return false;
                    }
                }
            });

            // Auto-resize on load
            this.autoResizeTextarea();
        }

        // Send button click handler
        const sendButton = document.getElementById('send-button');
        if (sendButton) {
            sendButton.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                
                const textarea = document.getElementById('chat-input');
                if (textarea && textarea.value.trim()) {
                    this.sendMessage();
                }
                return false;
            });
        }
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

    updateCharCount() {
        const textarea = document.getElementById('chat-input');
        const countEl = document.getElementById('char-count');
        
        if (textarea && countEl) {
            const count = textarea.value.length;
            countEl.textContent = count;
        }
    }

    autoResizeTextarea() {
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.style.height = 'auto';
            
            const maxHeight = 120; // 120px max height
            const newHeight = Math.min(textarea.scrollHeight, maxHeight);
            textarea.style.height = newHeight + 'px';
            
            textarea.style.overflowY = textarea.scrollHeight > maxHeight ? 'auto' : 'hidden';
        }
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
        console.log('🚀 sendMessage called');
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
        if (guestMessages.length >= 10) {
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
        let accumulated = '';

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

            // SSE Stream processing
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = '';
            let processedLines = new Set();

            console.log('📺 Starting SSE stream processing');

            while (true) {
                const { done, value } = await reader.read();
                
                if (done) {
                    console.log('✅ Stream reader finished');
                    break;
                }

                const chunk = decoder.decode(value, { stream: true });
                buffer += chunk;
                
                let newlineIndex;
                while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
                    const line = buffer.slice(0, newlineIndex).trim();
                    buffer = buffer.slice(newlineIndex + 1);
                    
                    if (line === '') continue;
                    
                    if (processedLines.has(line)) {
                        continue;
                    }
                    processedLines.add(line);
                    
                    console.log('📦 Processing SSE line:', line);
                    
                    if (line.startsWith('data: ')) {
                        const jsonStr = line.slice(6).trim();
                        
                        if (jsonStr === '[DONE]') {
                            console.log('✅ Stream completed with [DONE]');
                            this.finishStreaming(aiMessage, accumulated);
                            return;
                        }

                        try {
                            const data = JSON.parse(jsonStr);
                            console.log('📊 Parsed SSE data:', data);
                            
                            if (data.type === 'content' && data.content) {
                                accumulated += data.content;
                                this.updateStreamingMessage(aiMessage, accumulated);
                                console.log('📝 Content received:', data.content);
                            }
                            
                            if (data.type === 'complete' || data.done === true) {
                                console.log('✅ Stream completed with complete flag');
                                this.finishStreaming(aiMessage, accumulated);
                                return;
                            }
                            
                            if (data.type === 'error') {
                                console.error('❌ Stream error:', data.error);
                                this.updateStreamingMessage(aiMessage, '*Error: ' + data.error + '*');
                                this.finishStreaming(aiMessage, '*Error: ' + data.error + '*');
                                return;
                            }
                            
                        } catch (parseError) {
                            console.warn('⚠️ JSON parse error:', parseError, 'for:', jsonStr);
                        }
                    }
                }
                
                await new Promise(resolve => setTimeout(resolve, 1));
            }

            console.log('🏁 Stream ended without [DONE], finishing with accumulated content');
            this.finishStreaming(aiMessage, accumulated);

        } catch (error) {
            console.error('❌ Chat error:', error);
            
            if (error.name === 'AbortError') {
                console.log('🛑 Request was aborted by user');
                this.updateStreamingMessage(aiMessage, '*Request cancelled*');
            } else {
                const errorMessage = `*Error: ${error.message}*`;
                this.updateStreamingMessage(aiMessage, errorMessage);
            }
            
            this.finishStreaming(aiMessage, accumulated || `Error: ${error.message}`);
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
                GuestChatStorage.saveMessage('user', content);
            }
        } else {
            avatarDiv.innerHTML = '<i class="bi bi-robot"></i>';
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
                
            if (!isStreaming && content.trim() && !skipStorage) {
                GuestChatStorage.saveMessage('assistant', content);
            }
        }
        
        messageDiv.appendChild(avatarDiv);
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        console.log(`💬 Added ${sender} message:`, content.substring(0, 50) + '...');
        
        return messageDiv;
    }

    updateStreamingMessage(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const parsedContent = window.marked ? marked.parse(content) : content;
            streamingEl.innerHTML = parsedContent + '<span class="cursor blink">▋</span>';
            
            const messagesContainer = document.getElementById('chat-messages');
            if (messagesContainer) {
                messagesContainer.scrollTo({
                    top: messagesContainer.scrollHeight,
                    behavior: 'smooth'
                });
            }
        }
    }

    finishStreaming(messageDiv, finalContent) {
        console.log('🏁 Finishing stream with content length:', finalContent.length);
        
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const parsedContent = window.marked ? marked.parse(finalContent) : finalContent;
            streamingEl.innerHTML = parsedContent;
            
            if (finalContent.trim()) {
                GuestChatStorage.saveMessage('assistant', finalContent);
            }
        }
        
        this.isTyping = false;
        this.updateButtons(false);
        
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            messagesContainer.scrollTo({
                top: messagesContainer.scrollHeight,
                behavior: 'smooth'
            });
        }
        
        const input = document.getElementById('chat-input');
        if (input) {
            input.focus();
        }
    }

    stopGeneration() {
        console.log('⏹️ Stopping generation');
        if (this.abortController) {
            this.abortController.abort();
        }
        this.isTyping = false;
        this.updateButtons(false);
    }

    updateButtons(isTyping) {
        const sendButton = document.getElementById('send-button');
        const stopButton = document.getElementById('stop-button');
        const chatInput = document.getElementById('chat-input');

        if (sendButton) {
            sendButton.style.display = isTyping ? 'none' : 'inline-flex';
            sendButton.disabled = isTyping;
        }
        if (stopButton) {
            stopButton.style.display = isTyping ? 'inline-flex' : 'none';
            stopButton.disabled = !isTyping;
        }
        if (chatInput) {
            chatInput.disabled = isTyping;
        }
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
        const modalHTML = `
            <div class="modal fade" id="guest-response-modal" tabindex="-1" aria-labelledby="responseModalLabel" aria-hidden="true" data-bs-backdrop="static" data-bs-keyboard="false">
                <div class="modal-dialog modal-dialog-centered">
                    <div class="modal-content bg-dark border-warning">
                        <div class="modal-header border-warning">
                            <h5 class="modal-title text-warning" id="responseModalLabel">
                                <i class="bi bi-exclamation-triangle"></i> Guest Session Challenge
                            </h5>
                        </div>
                        <div class="modal-body">
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
                        </div>
                        <div class="modal-footer border-warning justify-content-center">
                            <button type="button" class="btn btn-success me-2" id="response-accept">
                                <i class="bi bi-check-circle"></i> Continue Session
                            </button>
                            <button type="button" class="btn btn-secondary" id="response-reject">
                                <i class="bi bi-x-circle"></i> End Session
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        document.body.insertAdjacentHTML('beforeend', modalHTML);
        this.challengeModal = new bootstrap.Modal(document.getElementById('guest-response-modal'));
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
            const userInfo = await this.getCurrentUserInfo();
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

    async getCurrentUserInfo() {
        try {
            const response = await fetch('/api/auth/check', { credentials: 'include' });
            if (response.ok) {
                const data = await response.json();
                return data;
            }
        } catch (error) {
            console.warn('Failed to get user info:', error);
        }
        return null;
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
        
        this.showTimeoutMessage();
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
            this.showErrorMessage('Failed to respond to challenge: ' + error.message);
        }
    }

    handleChallengeResponse(response, result) {
        this.stopCountdown();
        this.isListening = false;
        this.challengeModal.hide();
        
        if (response === 'accept' && result === 'accepted') {
            this.showSuccessMessage('Session continued successfully!');
            this.updateLastActivity();
        } else {
            this.showInfoMessage('Session ended. Thank you for using ai.junder.uk!');
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
        localStorage.clear();
        sessionStorage.clear();
        
        document.cookie = 'access_token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
        
        console.log('🧹 User session cleared');
    }

    showTimeoutMessage() {
        this.showAlert('Your guest session has been ended due to inactivity. Another user has taken your slot.', 'warning', 'exclamation-triangle');
    }

    showSuccessMessage(message) {
        this.showAlert(message, 'success', 'check-circle');
    }

    showInfoMessage(message) {
        this.showAlert(message, 'info', 'info-circle');
    }

    showErrorMessage(message) {
        this.showAlert(message, 'danger', 'exclamation-triangle');
    }

    showAlert(message, type, icon) {
        const alert = document.createElement('div');
        alert.className = `alert alert-${type} alert-dismissible fade show position-fixed`;
        alert.style.cssText = 'top: 20px; left: 50%; transform: translateX(-50%); z-index: 9999; max-width: 500px;';
        alert.innerHTML = `
            <i class="bi bi-${icon}"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        
        document.body.appendChild(alert);
        
        setTimeout(() => {
            if (alert.parentNode) {
                alert.remove();
            }
        }, type === 'success' ? 3000 : 5000);
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
    // Only initialize if we're actually a guest user
    fetch('/api/auth/check', { credentials: 'include' })
        .then(response => response.json())
        .then(data => {
            if (data.success && data.user_type === 'is_guest') {
                // Initialize challenge responder for existing guests
                if (!window.guestChallengeResponder) {
                    window.guestChallengeResponder = new GuestChallengeResponder();
                    console.log('🎯 Challenge responder initialized for guest user');
                }
                
                // Initialize main guest chat if on chat page
                if (window.location.pathname === '/chat') {
                    window.guestChat = new GuestChat();
                    console.log('💬 Guest chat initialized');
                }
            }
        })
        .catch(error => {
            console.warn('Could not check auth status:', error);
            
            // Fallback: initialize chat if on chat page
            if (window.location.pathname === '/chat') {
                window.guestChat = new GuestChat();
                console.log('💬 Guest chat initialized (fallback)');
            }
        });
});