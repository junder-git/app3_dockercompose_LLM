// =============================================================================
// SIMPLIFIED is_pending.js - Basic pending status
// =============================================================================

// Simple pending user info - no complex status checking
document.addEventListener('DOMContentLoaded', () => {
    console.log('⏳ Pending user page loaded');
    
    // Just show helpful info, no complex polling
    const infoContainer = document.getElementById('pending-info');
    if (infoContainer) {
        infoContainer.innerHTML = `
            <div class="alert alert-warning">
                <h6><i class="bi bi-info-circle"></i> Your account is pending approval</h6>
                <p>You'll receive full access once an administrator approves your account.</p>
                <p>Try our <a href="/">guest chat</a> for immediate access with limited features.</p>
            </div>
        `;
    }
});

window.tryGuestChat = () => window.location.href = '/';