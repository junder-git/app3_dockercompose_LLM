// =============================================================================
// nginx/static/js/is_pending.js - PENDING USER FUNCTIONALITY
// =============================================================================

// Pending User Status Checker
class PendingUserStatus {
    constructor() {
        this.checkInterval = null;
        this.init();
    }

    init() {
        this.setupStatusCheck();
        this.displayPendingInfo();
        console.log('⏳ Pending user status checker initialized');
    }

    setupStatusCheck() {
        // Check status every 30 seconds
        this.checkInterval = setInterval(() => {
            this.checkApprovalStatus();
        }, 30000);

        // Initial check
        this.checkApprovalStatus();
    }

    async checkApprovalStatus() {
        try {
            const response = await fetch('/api/pending/status', {
                credentials: 'include'
            });

            if (response.ok) {
                const data = await response.json();
                
                if (data.success) {
                    // Still pending
                    this.updateStatusDisplay(data);
                } else if (response.status === 403) {
                    // User might have been approved or rejected
                    window.location.reload();
                }
            }
        } catch (error) {
            console.warn('Could not check approval status:', error);
        }
    }

    updateStatusDisplay(statusData) {
        const statusElement = document.getElementById('approval-status');
        if (statusElement) {
            const queueInfo = statusData.queue_info || {};
            statusElement.innerHTML = `
                <div class="alert alert-info">
                    <h6><i class="bi bi-clock-history"></i> Status Update</h6>
                    <p><strong>Position:</strong> ${queueInfo.position_in_queue || 'Unknown'} of ${queueInfo.total_pending || 0}</p>
                    <p><strong>Estimated Wait:</strong> ${statusData.estimated_wait_time || '24-48 hours'}</p>
                    <small class="text-muted">Last checked: ${new Date().toLocaleTimeString()}</small>
                </div>
            `;
        }
    }

    displayPendingInfo() {
        // Show helpful information to pending users
        const pendingInfo = `
            <div class="alert alert-warning">
                <h6><i class="bi bi-info-circle"></i> While You Wait</h6>
                <ul class="mb-0">
                    <li>Your account is being reviewed by our administrators</li>
                    <li>You'll receive full access once approved</li>
                    <li>Try our guest chat for immediate access with limited features</li>
                </ul>
            </div>
        `;

        const infoContainer = document.getElementById('pending-info');
        if (infoContainer) {
            infoContainer.innerHTML = pendingInfo;
        }
    }

    destroy() {
        if (this.checkInterval) {
            clearInterval(this.checkInterval);
        }
    }
}

// Global pending user functions
window.checkStatusNow = async function() {
    if (window.pendingUserStatus) {
        await window.pendingUserStatus.checkApprovalStatus();
        sharedInterface.showInfo('Status checked - you\'ll be notified of any changes');
    }
};

window.tryGuestChat = function() {
    window.location.href = '/';
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Only initialize if we're actually a pending user
    sharedInterface.checkAuth()
        .then(data => {
            if (data.success && data.user_type === 'is_pending') {
                // Initialize pending user status checker
                window.pendingUserStatus = new PendingUserStatus();
                console.log('📋 Pending user functionality initialized');
            }
        })
        .catch(error => {
            console.warn('Could not check auth status for pending user:', error);
        });
});