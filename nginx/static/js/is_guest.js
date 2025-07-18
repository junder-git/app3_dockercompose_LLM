// =============================================================================
// nginx/static/js/is_guest.js - COMPLETE FIXED VERSION
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
        console.log('👤 Guest chat system initialized');
    }

    setupEventListeners() {
        // FIXED: Prevent form submission from refreshing page
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault(); // Prevent page refresh
                e.stopPropagation(); // Stop event bubbling
                this.sendMessage();
                return false; // Extra insurance
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
        
        // FIXED: Proper Enter key handling for textarea
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            // Handle input changes for character count and auto-resize
            textarea.addEventListener('input', (e) => {
                this.updateCharCount();
                this.autoResizeTextarea();
            });
            
            // CRITICAL FIX: Only keydown event for Enter handling
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    if (e.shiftKey) {
                        // Shift+Enter: Allow new line (don't prevent default)
                        return;
                    } else {
                        // Enter only: Send message and prevent new line
                        e.preventDefault();
                        e.stopPropagation();
                        
                        // Only send if there's content
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

        // FIXED: Send button click handler
        const sendButton = document.getElementById('send-button');
        if (sendButton) {
            sendButton.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                
                // Only send if there's content
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

    // =============================================================================
    // ENHANCED: Auto-resize textarea and character count
    // =============================================================================

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
            // Reset height to auto to get the correct scrollHeight
            textarea.style.height = 'auto';
            
            // Set height to scrollHeight with max height limit
            const maxHeight = 120; // 120px max height
            const newHeight = Math.min(textarea.scrollHeight, maxHeight);
            textarea.style.height = newHeight + 'px';
            
            // Add scrollbar if content exceeds max height
            textarea.style.overflowY = textarea.scrollHeight > maxHeight ? 'auto' : 'hidden';
        }
    }

    loadGuestHistory() {
        const messages = GuestChatStorage.getMessages();
        if (messages.length > 0) {
            const welcomePrompt = document.getElementById('welcome-prompt');
            if (welcomePrompt) welcomePrompt.style.display = 'none';
            
            // Clear existing messages first to prevent duplicates
            const messagesContainer = document.getElementById('chat-messages');
            if (messagesContainer) {
                messagesContainer.innerHTML = '';
            }
            
            messages.forEach(msg => {
                this.addMessage(msg.role === 'user' ? 'user' : 'ai', msg.content, false, true); // Skip storage save
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
        input.style.height = 'auto'; // Reset textarea height
        this.updateCharCount();
        this.autoResizeTextarea();
        
        // Set typing state
        this.isTyping = true;
        this.updateButtons(true);

        // Create abort controller for this request
        this.abortController = new AbortController();
        
        // Add AI message container for streaming
        const aiMessage = this.addMessage('ai', '', true); // true = isStreaming
        let accumulated = '';

        try {
            console.log('🌐 Making streaming request to /api/chat/stream');
            
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
            console.log('📡 Response headers:', Object.fromEntries(response.headers));

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // Check if response is actually SSE
            const contentType = response.headers.get('content-type') || '';
            if (!contentType.includes('text/event-stream')) {
                console.warn('⚠️ Response is not SSE, content-type:', contentType);
                
                // Fallback: treat as regular JSON response
                const text = await response.text();
                console.log('📄 Non-streaming response:', text);
                
                try {
                    const data = JSON.parse(text);
                    if (data.content || data.response) {
                        const content = data.content || data.response;
                        this.updateStreamingMessage(aiMessage, content);
                        this.finishStreaming(aiMessage, content);
                    } else {
                        throw new Error('No content in response');
                    }
                } catch (parseError) {
                    throw new Error('Invalid response format');
                }
                return;
            }

            // Handle SSE streaming
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = '';

            console.log('📺 Starting SSE stream processing');

            while (true) {
                const { done, value } = await reader.read();
                
                if (done) {
                    console.log('✅ Stream reader finished');
                    break;
                }

                // Decode chunk and add to buffer
                const chunk = decoder.decode(value, { stream: true });
                buffer += chunk;
                
                // Process complete lines
                const lines = buffer.split('\n');
                buffer = lines.pop() || ''; // Keep incomplete line in buffer

                for (const line of lines) {
                    if (line.trim() === '') continue;
                    
                    console.log('📦 Processing line:', line);
                    
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
                            
                            if (data.content) {
                                accumulated += data.content;
                                this.updateStreamingMessage(aiMessage, accumulated);
                            } else if (data.delta && data.delta.content) {
                                accumulated += data.delta.content;
                                this.updateStreamingMessage(aiMessage, accumulated);
                            } else if (data.response) {
                                accumulated += data.response;
                                this.updateStreamingMessage(aiMessage, accumulated);
                            }
                            
                            if (data.done === true) {
                                console.log('✅ Stream completed with done flag');
                                this.finishStreaming(aiMessage, accumulated);
                                return;
                            }
                        } catch (parseError) {
                            console.warn('⚠️ JSON parse error:', parseError, 'for:', jsonStr);
                        }
                    }
                }
            }

            // If we exit the loop without [DONE], finish anyway
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
            contentDiv.innerHTML = window.marked ? marked.parse(content) : content;
            
            // Save to localStorage only if not skipping storage (i.e., not loading from storage)
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

    // =============================================================================
    // ENHANCED: Better streaming message updates
    // =============================================================================

    updateStreamingMessage(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Parse markdown if available
            const parsedContent = window.marked ? marked.parse(content) : content;
            
            // Add typing cursor
            streamingEl.innerHTML = parsedContent + '<span class="cursor blink">▋</span>';
            
            // Auto-scroll to bottom
            const messagesContainer = document.getElementById('chat-messages');
            if (messagesContainer) {
                // Smooth scroll to bottom
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
            // Remove cursor and set final content
            const parsedContent = window.marked ? marked.parse(finalContent) : finalContent;
            streamingEl.innerHTML = parsedContent;
            
            // Save to storage if content exists
            if (finalContent.trim()) {
                GuestChatStorage.saveMessage('assistant', finalContent);
            }
        }
        
        // Reset typing state
        this.isTyping = false;
        this.updateButtons(false);
        
        // Final scroll to bottom
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            messagesContainer.scrollTo({
                top: messagesContainer.scrollHeight,
                behavior: 'smooth'
            });
        }
        
        // Focus back to input
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

// =============================================================================
// Guest Challenge System - Complete Client Side (No Sound)
// =============================================================================

// Guest Challenge Manager - handles challenges for existing guests
class GuestChallengeManager {
    constructor() {
        this.challengeActive = false;
        this.challengeModal = null;
        this.countdownInterval = null;
        this.init();
    }

    init() {
        this.createChallengeModal();
        this.setupEventListeners();
        this.setupChallengeListener();
        console.log('🚨 Guest Challenge Manager initialized');
    }

    createChallengeModal() {
        const modalHTML = `
            <div class="modal fade" id="guest-challenge-modal" tabindex="-1" aria-labelledby="challengeModalLabel" aria-hidden="true" data-bs-backdrop="static" data-bs-keyboard="false">
                <div class="modal-dialog modal-dialog-centered">
                    <div class="modal-content bg-dark border-warning">
                        <div class="modal-header border-warning">
                            <h5 class="modal-title text-warning" id="challengeModalLabel">
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
                                        <div id="challenge-progress" class="progress-bar bg-warning" role="progressbar" style="width: 100%;"></div>
                                    </div>
                                    <div class="mt-2">
                                        <span class="text-warning">Time remaining: </span>
                                        <span id="challenge-timer" class="text-light fw-bold" style="font-family: monospace; font-size: 1.25rem;">20</span>
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
                            <button type="button" class="btn btn-success me-2" id="challenge-accept">
                                <i class="bi bi-check-circle"></i> Continue Session
                            </button>
                            <button type="button" class="btn btn-secondary" id="challenge-reject">
                                <i class="bi bi-x-circle"></i> End Session
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        document.body.insertAdjacentHTML('beforeend', modalHTML);
        this.challengeModal = new bootstrap.Modal(document.getElementById('guest-challenge-modal'));
        console.log('📋 Challenge modal created');
    }

    setupEventListeners() {
        document.getElementById('challenge-accept').addEventListener('click', () => {
            this.respondToChallenge('accept');
        });

        document.getElementById('challenge-reject').addEventListener('click', () => {
            this.respondToChallenge('reject');
        });
    }

    setupChallengeListener() {
        // Check for challenges every 30 seconds when user is active
        setInterval(() => {
            if (this.isUserActive() && !this.challengeActive) {
                this.checkForChallenges();
            }
        }, 30000);

        // Check for challenges when user becomes active
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible' && !this.challengeActive) {
                this.checkForChallenges();
            }
        });

        // Activity tracking
        ['click', 'keypress', 'scroll', 'mousemove'].forEach(event => {
            document.addEventListener(event, () => {
                this.updateLastActivity();
            });
        });
    }

    isUserActive() {
        const lastActivity = localStorage.getItem('guest_last_activity');
        if (!lastActivity) return true;
        
        const timeSinceActivity = Date.now() - parseInt(lastActivity);
        return timeSinceActivity < 10; // 10secs
    }

    updateLastActivity() {
        localStorage.setItem('guest_last_activity', Date.now().toString());
    }

    async checkForChallenges() {
        try {
            const userInfo = await this.getCurrentUserInfo();
            if (!userInfo || userInfo.user_type !== 'is_guest') return;

            const response = await fetch(`/api/guest/challenge-status?slot=${userInfo.guest_slot_number}`, {
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
        if (this.challengeActive) return;

        console.log('🚨 Incoming challenge:', challenge);
        
        this.challengeActive = true;
        this.currentChallenge = challenge;
        
        // Show modal
        this.challengeModal.show();
        
        // Start countdown
        this.startChallengeCountdown();
        
        // Show browser notification
        this.showBrowserNotification();
    }

    startChallengeCountdown() {
        const startTime = Date.now();
        const totalTime = 15000; // 15 seconds
        
        this.countdownInterval = setInterval(() => {
            const now = Date.now();
            const elapsed = now - startTime;
            const remaining = Math.max(0, totalTime - elapsed);
            const seconds = Math.ceil(remaining / 1000);
            
            // Update timer display
            const timerEl = document.getElementById('challenge-timer');
            const progressEl = document.getElementById('challenge-progress');
            
            if (timerEl) timerEl.textContent = seconds;
            if (progressEl) {
                const percentage = (remaining / totalTime) * 100;
                progressEl.style.width = percentage + '%';
                
                // Change color as time runs out
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
        this.challengeActive = false;
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
                    slot_number: this.currentChallenge.slot_number,
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
        this.challengeActive = false;
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
                body: 'Someone wants to use your guest session. Please respond within 20 seconds.',
                icon: '/favicon.ico',
                tag: 'guest-challenge',
                requireInteraction: true
            });
        } else if (Notification.permission !== 'denied') {
            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    new Notification('Guest Session Challenge', {
                        body: 'Someone wants to use your guest session. Please respond within 20 seconds.',
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
        
        // Clear cookies
        document.cookie = 'access_token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
        document.cookie = 'guest_token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
        
        console.log('🧹 User session cleared');
    }

    showTimeoutMessage() {
        const message = 'Your guest session has been ended due to inactivity. Another user has taken your slot.';
        this.showAlert(message, 'warning', 'exclamation-triangle');
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

// Enhanced Guest Session Manager - handles creating new sessions with challenges
class EnhancedGuestSessionManager {
    constructor() {
        this.challengerCountdown = null;
        this.init();
    }

    init() {
        this.setupChallengeHandling();
        console.log('🔧 Enhanced Guest Session Manager initialized');
    }

    setupChallengeHandling() {
        // Override the original startGuestSession function
        window.startGuestSession = async () => {
            console.log('🎮 Starting enhanced guest session...');
            
            const button = document.getElementById("chatters");
            if (button) {
                button.disabled = true;
                button.innerHTML = '<i class="bi bi-hourglass-split"></i> Creating session...';
            }
            
            try {
                const response = await fetch('/api/guest/create-session', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    credentials: 'include'
                });

                const data = await response.json();
                
                if (response.status === 202 && data.challenge_required) {
                    // Challenge required
                    this.handleChallengeRequired(data);
                } else if (data.success) {
                    // Normal session creation
                    console.log('✅ Guest session created:', data.username);
                    this.showSuccessMessage(`Guest session created as ${data.username}! Redirecting...`);
                    
                    setTimeout(() => {
                        window.location.href = '/chat';
                    }, 1000);
                } else {
                    // Error
                    console.error('❌ Guest session failed:', data);
                    this.showErrorMessage(data.message || 'Failed to start guest session');
                    
                    if (data.error === 'no_slots_available') {
                        setTimeout(() => {
                            window.location.href = '/dash?guest_unavailable=1';
                        }, 2000);
                    }
                }
            } catch (error) {
                console.error('Guest session error:', error);
                this.showErrorMessage('Guest session error: ' + error.message);
            } finally {
                if (button) {
                    button.disabled = false;
                    button.innerHTML = '<i class="bi bi-chat-dots"></i> Start Chat';
                }
            }
        };
    }

    async handleChallengeRequired(challengeData) {
        console.log('🚨 Challenge required:', challengeData);
        
        this.showChallengeStatus(challengeData);
        this.pollChallengeStatus(challengeData.slot_number, challengeData.challenge_id);
    }

    showChallengeStatus(challengeData) {
        const statusHTML = `
            <div class="modal fade" id="challenge-status-modal" tabindex="-1" aria-labelledby="challengeStatusLabel" aria-hidden="true" data-bs-backdrop="static">
                <div class="modal-dialog modal-dialog-centered">
                    <div class="modal-content bg-dark border-info">
                        <div class="modal-header border-info">
                            <h5 class="modal-title text-info" id="challengeStatusLabel">
                                <i class="bi bi-hourglass-split"></i> Challenging Inactive User
                            </h5>
                        </div>
                        <div class="modal-body text-center">
                            <div class="mb-3">
                                <i class="bi bi-person-exclamation challenge-icon" style="font-size: 3rem; color: #0dcaf0;"></i>
                            </div>
                            <h6 class="text-info mb-3">Challenging inactive user in slot ${challengeData.slot_number}</h6>
                            <p class="text-light mb-3">
                                ${challengeData.message}
                            </p>
                            <div class="challenge-countdown mb-3">
                                <div class="progress bg-secondary" style="height: 12px; border-radius: 6px;">
                                    <div id="challenger-progress" class="progress-bar bg-info" role="progressbar" style="width: 100%;"></div>
                                </div>
                                <div class="mt-2">
                                    <span class="text-info">Time remaining: </span>
                                    <span id="challenger-timer" class="text-light fw-bold" style="font-family: monospace; font-size: 1.25rem;">${challengeData.timeout}</span>
                                    <span class="text-light"> seconds</span>
                                </div>
                            </div>
                            <div class="alert alert-info">
                                <small>
                                    <i class="bi bi-info-circle"></i>
                                    If they don't respond, you'll get their slot automatically.
                                </small>
                            </div>
                        </div>
                        <div class="modal-footer border-info justify-content-center">
                            <button type="button" class="btn btn-secondary" id="cancel-challenge">
                                <i class="bi bi-x-circle"></i> Cancel
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        document.body.insertAdjacentHTML('beforeend', statusHTML);
        
        const modal = new bootstrap.Modal(document.getElementById('challenge-status-modal'));
        modal.show();
        
        this.startChallengerCountdown(challengeData.timeout);
        
        document.getElementById('cancel-challenge').addEventListener('click', () => {
            modal.hide();
            this.stopChallengerCountdown();
        });
    }

    startChallengerCountdown(totalSeconds) {
        const startTime = Date.now();
        const totalTime = totalSeconds * 1000;
        
        this.challengerCountdown = setInterval(() => {
            const now = Date.now();
            const elapsed = now - startTime;
            const remaining = Math.max(0, totalTime - elapsed);
            const seconds = Math.ceil(remaining / 1000);
            
            const timerEl = document.getElementById('challenger-timer');
            const progressEl = document.getElementById('challenger-progress');
            
            if (timerEl) timerEl.textContent = seconds;
            if (progressEl) {
                const percentage = (remaining / totalTime) * 100;
                progressEl.style.width = percentage + '%';
                
                if (percentage < 30) {
                    progressEl.classList.remove('bg-info');
                    progressEl.classList.add('bg-success');
                }
            }
            
            if (remaining <= 0) {
                this.stopChallengerCountdown();
            }
        }, 100);
    }

    stopChallengerCountdown() {
        if (this.challengerCountdown) {
            clearInterval(this.challengerCountdown);
            this.challengerCountdown = null;
        }
    }

    async pollChallengeStatus(slotNumber, challengeId) {
        let pollCount = 0;
        const maxPolls = 25; // 25 seconds total
        
        const poll = async () => {
            if (pollCount >= maxPolls) {
                this.handleChallengeTimeout(slotNumber);
                return;
            }
            
            try {
                const response = await fetch(`/api/guest/challenge-status?slot=${slotNumber}`, {
                    credentials: 'include'
                });

                if (response.ok) {
                    const data = await response.json();
                    
                    if (!data.challenge_active) {
                        this.handleChallengeCompleted(slotNumber);
                        return;
                    }
                    
                    if (data.challenge && data.challenge.status !== 'pending') {
                        this.handleChallengeResponse(data.challenge, slotNumber);
                        return;
                    }
                }
                
                pollCount++;
                setTimeout(poll, 1000);
                
            } catch (error) {
                console.error('Error polling challenge status:', error);
                pollCount++;
                setTimeout(poll, 1000);
            }
        };
        
        poll();
    }

    async handleChallengeTimeout(slotNumber) {
        console.log('⏰ Challenge timeout - attempting to claim slot');
        
        try {
            const response = await fetch('/api/guest/force-claim', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({ slot_number: slotNumber })
            });

            const data = await response.json();
            
            if (data.success) {
                this.hideChallengeModal();
                this.showSuccessMessage(`Slot claimed! Previous user (${data.kicked_user}) was inactive. Redirecting...`);
                
                setTimeout(() => {
                    window.location.href = '/chat';
                }, 1500);
            } else {
                this.hideChallengeModal();
                this.showErrorMessage(data.error || 'Failed to claim slot');
            }
        } catch (error) {
            console.error('Error claiming slot:', error);
            this.hideChallengeModal();
            this.showErrorMessage('Error claiming slot: ' + error.message);
        }
    }

    handleChallengeCompleted(slotNumber) {
        console.log('✅ Challenge completed');
        this.hideChallengeModal();
        this.showInfoMessage('Challenge completed. Trying to create session...');
        
        setTimeout(() => {
            window.startGuestSession();
        }, 1000);
    }

    handleChallengeResponse(challenge, slotNumber) {
        console.log('📞 Challenge response received:', challenge.status);
        
        this.hideChallengeModal();
        
        if (challenge.status === 'rejected') {
            this.showInfoMessage('User ended their session voluntarily. Creating your session...');
            setTimeout(() => {
                window.startGuestSession();
            }, 1000);
        } else if (challenge.status === 'accepted') {
            this.showInfoMessage('User chose to continue their session. Please try again later.');
        }
    }

    hideChallengeModal() {
        this.stopChallengerCountdown();
        
        const modal = document.getElementById('challenge-status-modal');
        if (modal) {
            const bsModal = bootstrap.Modal.getInstance(modal);
            if (bsModal) {
                bsModal.hide();
            }
            setTimeout(() => {
                modal.remove();
            }, 500);
        }
    }

    showSuccessMessage(message) {
        this.showAlert(message, 'success', 'check-circle');
    }

    showErrorMessage(message) {
        this.showAlert(message, 'danger', 'exclamation-triangle');
    }

    showInfoMessage(message) {
        this.showAlert(message, 'info', 'info-circle');
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

// Initialize the systems when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Initialize enhanced guest session manager for home page
    if (window.location.pathname === '/') {
        window.enhancedGuestManager = new EnhancedGuestSessionManager();
        console.log('🚀 Enhanced Guest Session Manager loaded');
    }
    
    // Initialize challenge manager for existing guests
    fetch('/api/auth/check', { credentials: 'include' })
        .then(response => response.json())
        .then(data => {
            if (data.success && (data.user_type === 'is_guest' || data.user_type === 'is_none')) {
                if (!window.guestChallengeManager) {
                    window.guestChallengeManager = new GuestChallengeManager();
                    console.log('🎯 Challenge manager initialized for existing guest');
                }
            }
        })
        .catch(error => {
            console.warn('Could not check auth status:', error);
        });
    
    // Initialize main guest chat if on chat page
    if (window.location.pathname === '/chat') {
        window.guestChat = new GuestChat();
        console.log('💬 Guest chat initialized');
    }
});