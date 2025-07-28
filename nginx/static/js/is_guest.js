// =============================================================================
// nginx/static/js/is_guest.js - COMPLETE GUEST CHAT WITH CHALLENGES AND LOCALSTORAGE
// =============================================================================
// =============================================================================
// GUEST CHAT CLASS - EXTENDS SharedChatBase
// =============================================================================

class GuestChat extends SharedChatBase {
    constructor() {
        super();
        this.storageType = 'localStorage';
        this.maxTokens = 1024; // Limited for guests
        console.log('👤 Guest chat initialized');
        
        // Load guest history after initialization
        this.loadGuestHistory();
    }

    // Override saveMessage to use localStorage
    saveMessage(role, content) {
        console.log(`💾 Guest saving ${role} message to localStorage (${content.length} chars)`);
    }

    // Override clearChat to also clear localStorage
    clearChat() {
        if (!confirm('Clear guest chat history? This will only clear your browser storage.')) return;
        
        const messagesContainer = this.getMessagesContainer();
        const welcomePrompt = document.getElementById('welcome-prompt');
        
        if (messagesContainer) {
            const messages = messagesContainer.querySelectorAll('.message');
            messages.forEach(msg => msg.remove());
        }
        
        if (welcomePrompt) {
            welcomePrompt.style.display = 'block';
        }
        
        this.messageCount = 0;
        console.log('🗑️ Guest chat history cleared from localStorage');
    }
}

// =============================================================================
// GUEST CHALLENGE RESPONSE SYSTEM
// =============================================================================

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
        // Check if SharedModalUtils is available
        if (typeof SharedModalUtils !== 'undefined') {
            this.challengeModal = SharedModalUtils.createModal(
                'guest-response-modal',
                '<i class="bi bi-exclamation-triangle"></i> Guest Session Challenge',
                `<div class="text-center">
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
                </div>`,
                [
                    { id: 'response-accept', type: 'success', text: '<i class="bi bi-check-circle"></i> Continue Session' },
                    { id: 'response-reject', type: 'secondary', text: '<i class="bi bi-x-circle"></i> End Session' }
                ]
            );
        } else {
            console.warn('SharedModalUtils not available - challenge modals will not work');
        }
    }

    setupEventListeners() {
        // Set up challenge response buttons
        const acceptBtn = document.getElementById('response-accept');
        const rejectBtn = document.getElementById('response-reject');
        
        if (acceptBtn) {
            acceptBtn.addEventListener('click', () => {
                this.respondToChallenge('accept');
            });
        }

        if (rejectBtn) {
            rejectBtn.addEventListener('click', () => {
                this.respondToChallenge('reject');
            });
        }

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
            // Check if sharedInterface is available
            if (typeof sharedInterface === 'undefined') {
                console.warn('sharedInterface not available for auth check');
                return;
            }

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
        
        if (this.challengeModal) {
            this.challengeModal.show();
            this.startChallengeCountdown(8); // 8 second timeout
            this.showBrowserNotification();
        }
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
        
        if (this.challengeModal) {
            this.challengeModal.hide();
        }
        
        if (typeof sharedInterface !== 'undefined') {
            sharedInterface.showWarning('Your guest session has been ended due to inactivity. Another user has taken your slot.');
        }
        
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
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showError('Failed to respond to challenge: ' + error.message);
            }
        }
    }

    handleChallengeResponse(response, result) {
        this.stopCountdown();
        this.isListening = false;
        
        if (this.challengeModal) {
            this.challengeModal.hide();
        }
        
        if (response === 'accept' && result === 'accepted') {
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showSuccess('Session continued successfully!');
            }
            this.updateLastActivity();
        } else {
            if (typeof sharedInterface !== 'undefined') {
                sharedInterface.showInfo('Session ended. Thank you for using ai.junder.uk!');
            }
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
        if (typeof sharedInterface !== 'undefined') {
            sharedInterface.clearClientData();
        }
        console.log('🧹 Guest session cleared');
    }
}

// =============================================================================
// GLOBAL GUEST FUNCTIONS
// =============================================================================

window.downloadGuestHistory = function() {
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
// INITIALIZATION
// =============================================================================

document.addEventListener('DOMContentLoaded', () => {
    if (typeof SharedChatBase === 'undefined') {
        console.error('❌ SharedChatBase not found - is_shared_chat.js must be loaded first');
        return;
    }
    
    if (window.location.pathname === '/chat') {
        // Initialize challenge responder for guest users (server will determine if needed)
        if (!window.guestChallengeResponder) {
            window.guestChallengeResponder = new GuestChallengeResponder();
            console.log('🎯 Challenge responder initialized');
        }
        
        // Initialize main guest chat
        window.chatSystem = new GuestChat();
        console.log('💬 Guest chat system initialized and ready');
    }
});