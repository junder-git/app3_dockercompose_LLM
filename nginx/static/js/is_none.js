// =============================================================================
// nginx/static/js/is_none.js - GUEST SESSION CREATION AND CHALLENGE SYSTEM
// =============================================================================

// Global variables for challenge handling
let challengeCheckInterval;
let challengeTimeoutId;

// Main Guest Session Manager for is_none users
class GuestSessionManager {
    constructor() {
        this.challengeModal = null;
        this.countdownInterval = null;
        this.isCreatingSession = false;
        this.init();
    }

    init() {
        this.setupStartGuestFunction();
        this.createChallengeModal();
        console.log('🚀 Guest Session Manager initialized');
    }

    setupStartGuestFunction() {
        // Override the global startGuestSession function
        window.startGuestSession = async () => {
            if (this.isCreatingSession) {
                console.log('⚠️ Session creation already in progress');
                return;
            }

            console.log('🎮 Starting guest session...');
            
            const button = document.getElementById("chatters");
            if (button) {
                button.disabled = true;
                button.innerHTML = '<i class="bi bi-hourglass-split"></i> Creating session...';
            }
            
            this.isCreatingSession = true;
            
            try {
                const response = await fetch('/api/guest/create-session', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    credentials: 'include'
                });

                const data = await response.json();
                
                if (response.status === 202 && data.challenge_required) {
                    // Challenge required - another user is inactive
                    this.handleChallengeRequired(data);
                } else if (data.success) {
                    // Normal session creation - slot was available
                    console.log('✅ Guest session created:', data.username);
                    this.showSuccessMessage(`Guest session created as ${data.username}! Redirecting...`);
                    
                    setTimeout(() => {
                        window.location.href = data.redirect || '/chat';
                    }, 1000);
                } else if (data.error === 'all_slots_busy') {
                    // All slots busy with active challenges
                    this.showErrorMessage('All guest sessions are busy with active users. Please try again in a few moments.');
                } else {
                    // Other errors
                    console.error('❌ Guest session failed:', data);
                    this.showErrorMessage(data.message || 'Failed to start guest session');
                }
            } catch (error) {
                console.error('Guest session error:', error);
                this.showErrorMessage('Guest session error: ' + error.message);
            } finally {
                this.isCreatingSession = false;
                if (button) {
                    button.disabled = false;
                    button.innerHTML = '<i class="bi bi-chat-dots"></i> Start Chat';
                }
            }
        };
    }

    createChallengeModal() {
        const modalHTML = `
            <div class="modal fade" id="guest-challenge-modal" tabindex="-1" aria-labelledby="challengeModalLabel" aria-hidden="true" data-bs-backdrop="static" data-bs-keyboard="false">
                <div class="modal-dialog modal-dialog-centered">
                    <div class="modal-content bg-dark border-info">
                        <div class="modal-header border-info">
                            <h5 class="modal-title text-info" id="challengeModalLabel">
                                <i class="bi bi-hourglass-split"></i> Challenging Inactive User
                            </h5>
                        </div>
                        <div class="modal-body">
                            <div class="text-center">
                                <div class="mb-3">
                                    <i class="bi bi-person-exclamation challenge-icon" style="font-size: 3rem; color: #0dcaf0;"></i>
                                </div>
                                <h6 class="text-info mb-3" id="challenge-title">Challenging inactive user...</h6>
                                <p class="text-light mb-3" id="challenge-message">
                                    An inactive user is occupying a guest slot. We're challenging them to respond.
                                </p>
                                <div class="challenge-countdown mb-3">
                                    <div class="progress bg-secondary" style="height: 12px; border-radius: 6px;">
                                        <div id="challenge-progress" class="progress-bar bg-info" role="progressbar" style="width: 100%;"></div>
                                    </div>
                                    <div class="mt-2">
                                        <span class="text-info">Time remaining: </span>
                                        <span id="challenge-timer" class="text-light fw-bold" style="font-family: monospace; font-size: 1.25rem;">8</span>
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

        document.body.insertAdjacentHTML('beforeend', modalHTML);
        this.challengeModal = new bootstrap.Modal(document.getElementById('guest-challenge-modal'));

        // Setup cancel button
        document.getElementById('cancel-challenge').addEventListener('click', () => {
            this.cancelChallenge();
        });

        console.log('📋 Challenge modal created');
    }

    handleChallengeRequired(challengeData) {
        console.log('🚨 Challenge required:', challengeData);
        
        // Update modal content
        document.getElementById('challenge-title').textContent = `Challenging ${challengeData.username}`;
        document.getElementById('challenge-message').textContent = challengeData.message;
        document.getElementById('challenge-timer').textContent = challengeData.timeout;
        
        // Show modal
        this.challengeModal.show();
        
        // Start countdown
        this.startChallengeCountdown(challengeData.timeout);
        
        // Start polling for challenge status
        this.pollChallengeStatus(challengeData.username, challengeData.challenge_id);
    }

    startChallengeCountdown(totalSeconds) {
        const startTime = Date.now();
        const totalTime = totalSeconds * 1000;
        
        this.countdownInterval = setInterval(() => {
            const now = Date.now();
            const elapsed = now - startTime;
            const remaining = Math.max(0, totalTime - elapsed);
            const seconds = Math.ceil(remaining / 1000);
            
            const timerEl = document.getElementById('challenge-timer');
            const progressEl = document.getElementById('challenge-progress');
            
            if (timerEl) timerEl.textContent = seconds;
            if (progressEl) {
                const percentage = (remaining / totalTime) * 100;
                progressEl.style.width = percentage + '%';
                
                if (percentage < 30) {
                    progressEl.classList.remove('bg-info');
                    progressEl.classList.add('bg-success');
                } else if (percentage < 60) {
                    progressEl.classList.remove('bg-success');
                    progressEl.classList.add('bg-warning');
                }
            }
            
            if (remaining <= 0) {
                this.stopCountdown();
            }
        }, 100);
    }

    stopCountdown() {
        if (this.countdownInterval) {
            clearInterval(this.countdownInterval);
            this.countdownInterval = null;
        }
    }

    async pollChallengeStatus(username, challengeId) {
        let pollCount = 0;
        const maxPolls = 10; // 10 seconds total (8 second timeout + 2 second buffer)
        
        const poll = async () => {
            if (pollCount >= maxPolls) {
                this.handleChallengeTimeout(username);
                return;
            }
            
            try {
                const response = await fetch(`/api/guest/challenge-status?username=${username}`, {
                    credentials: 'include'
                });

                if (response.ok) {
                    const data = await response.json();
                    
                    if (!data.challenge_active) {
                        // Challenge completed - slot is free
                        this.handleChallengeCompleted(username);
                        return;
                    }
                    
                    if (data.challenge && data.challenge.status !== 'pending') {
                        // User responded to challenge
                        this.handleChallengeResponse(data.challenge, username);
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

    async handleChallengeTimeout(username) {
        console.log('⏰ Challenge timeout - attempting to claim slot');
        
        try {
            const response = await fetch('/api/guest/force-claim', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({ username: username })
            });

            const data = await response.json();
            
            if (data.success) {
                this.hideChallengeModal();
                this.showSuccessMessage(`Slot claimed! Inactive user was disconnected. Redirecting...`);
                
                setTimeout(() => {
                    window.location.href = data.redirect || '/chat';
                }, 1500);
            } else {
                this.hideChallengeModal();
                this.showErrorMessage(data.message || 'Failed to claim slot');
            }
        } catch (error) {
            console.error('Error claiming slot:', error);
            this.hideChallengeModal();
            this.showErrorMessage('Error claiming slot: ' + error.message);
        }
    }

    handleChallengeCompleted(username) {
        console.log('✅ Challenge completed - slot freed');
        this.hideChallengeModal();
        this.showInfoMessage('Slot freed! Creating your session...');
        
        // Retry session creation
        setTimeout(() => {
            window.startGuestSession();
        }, 1000);
    }

    handleChallengeResponse(challenge, username) {
        console.log('📞 Challenge response received:', challenge.status);
        
        this.hideChallengeModal();
        
        if (challenge.status === 'rejected') {
            this.showInfoMessage('User ended their session. Creating your session...');
            setTimeout(() => {
                window.startGuestSession();
            }, 1000);
        } else if (challenge.status === 'accepted') {
            this.showInfoMessage('User chose to continue their session. Please try again later.');
        }
    }

    cancelChallenge() {
        console.log('❌ Challenge cancelled by user');
        this.stopCountdown();
        this.hideChallengeModal();
        
        // Clear any polling intervals
        if (challengeCheckInterval) {
            clearInterval(challengeCheckInterval);
            challengeCheckInterval = null;
        }
        
        if (challengeTimeoutId) {
            clearTimeout(challengeTimeoutId);
            challengeTimeoutId = null;
        }
    }

    hideChallengeModal() {
        this.stopCountdown();
        
        if (this.challengeModal) {
            this.challengeModal.hide();
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

// Guest Stats Display for Dashboard
class GuestStatsDisplay {
    constructor() {
        this.statsContainer = null;
        this.init();
    }

    init() {
        this.statsContainer = document.getElementById('guest-stats-container');
        if (this.statsContainer) {
            this.loadAndDisplayStats();
            // Update stats every 30 seconds
            setInterval(() => {
                this.loadAndDisplayStats();
            }, 30000);
        }
        console.log('📊 Guest Stats Display initialized');
    }

    async loadAndDisplayStats() {
        try {
            const response = await fetch('/api/guest/stats', {
                credentials: 'include'
            });
            
            if (response.ok) {
                const data = await response.json();
                if (data.success) {
                    this.displayStats(data.stats);
                }
            }
        } catch (error) {
            console.warn('Failed to load guest stats:', error);
        }
    }

    displayStats(stats) {
        if (!this.statsContainer) return;
        
        const available = stats.available_slots > 0;
        const buttonClass = available ? 'btn-success' : 'btn-secondary';
        const buttonText = available ? 'Start Guest Chat' : 'Guest Chat Full';
        const buttonDisabled = available ? '' : 'disabled';
        
        this.statsContainer.innerHTML = `
            <div class="card bg-dark border-primary mb-4">
                <div class="card-body">
                    <h5 class="card-title text-primary">
                        <i class="bi bi-chat-dots"></i> Guest Chat Status
                    </h5>
                    <div class="row">
                        <div class="col-md-6">
                            <p><strong>Active Sessions:</strong> ${stats.active_sessions}/${stats.max_sessions}</p>
                            <p><strong>Available Slots:</strong> ${stats.available_slots}</p>
                        </div>
                        <div class="col-md-6">
                            <p><strong>Session Duration:</strong> 10 minutes</p>
                            <p><strong>Message Limit:</strong> 10 messages</p>
                            <p><strong>Active Challenges:</strong> ${stats.challenges_active}</p>
                        </div>
                    </div>
                    
                    <div class="mt-3">
                        <button class="btn ${buttonClass}" onclick="startGuestSession()" ${buttonDisabled}>
                            <i class="bi bi-chat-square-dots"></i> ${buttonText}
                        </button>
                        ${!available ? '<small class="text-muted ms-2">Try again in a few minutes</small>' : ''}
                    </div>
                </div>
            </div>
        `;
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Only initialize on relevant pages for is_none users
    if (window.location.pathname === '/' || window.location.pathname === '/dash') {
        window.guestSessionManager = new GuestSessionManager();
        window.guestStatsDisplay = new GuestStatsDisplay();
        console.log('🚀 Guest session management loaded for is_none user');
    }
});