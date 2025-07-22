// =============================================================================
// nginx/static/js/is_admin.js - ADMIN CHAT (EXTENDS APPROVED FUNCTIONALITY)
// =============================================================================

// Admin Chat System - extends ApprovedChat with admin features
class AdminChat extends ApprovedChat {
    constructor() {
        super();
        this.isAdmin = true;
        this.messageLimit = 'unlimited';
        this.maxTokens = 4096; // Highest limit for admins
        this.setupAdminFeatures();
        console.log('👑 Admin chat system initialized');
    }

    init() {
        super.init();
        this.loadAdminData();
    }

    setupAdminFeatures() {
        console.log('🛠️ Setting up admin features');
        this.addAdminInfo();
        this.setupSystemMonitoring();
    }

    addAdminInfo() {
        const chatContainer = document.querySelector('.chat-container');
        if (chatContainer) {
            const adminInfo = document.createElement('div');
            adminInfo.className = 'admin-info';
            adminInfo.innerHTML = `
                <div class="alert alert-info">
                    <i class="bi bi-shield-check"></i> 
                    <strong>Admin Mode:</strong> Full system access enabled
                </div>
            `;
            chatContainer.insertBefore(adminInfo, chatContainer.firstChild);
        }
    }

    setupSystemMonitoring() {
        // Monitor system stats every 30 seconds
        setInterval(() => {
            this.updateSystemStats();
        }, 30000);
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
        // Display stats in admin interface if needed
    }

    async updateSystemStats() {
        try {
            const response = await fetch('/api/admin/stats', { credentials: 'include' });
            if (response.ok) {
                const data = await response.json();
                console.log('🔄 System stats updated');
            }
        } catch (error) {
            console.warn('Stats update failed:', error);
        }
    }

    // Override sendMessage to include admin-specific options
    async sendMessage() {
        console.log('🚀 Admin sendMessage called');
        const input = document.getElementById('chat-input');
        if (!input) {
            console.error('Chat input not found');
            return;
        }
        
        const message = input.value.trim();
        
        if (!message || this.isTyping) {
            console.warn('Empty message or already typing');
            return;
        }

        console.log('📤 Sending admin message:', message);

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
            console.log('🌐 Making admin SSE request');
            
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
                    include_history: true,  // Admin gets full history
                    options: {
                        temperature: 0.7,
                        max_tokens: this.maxTokens  // Highest limit for admins
                    }
                })
            });

            console.log('📡 Admin response status:', response.status);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // Use shared SSE processing from SharedChatBase
            await this.processSSEStream(response, aiMessage);

        } catch (error) {
            console.error('❌ Admin chat error:', error);
            
            if (error.name === 'AbortError') {
                console.log('🛑 Admin request was aborted');
                this.updateStreamingMessage(aiMessage, '*Request cancelled*');
            } else {
                const errorMessage = `*Admin Error: ${error.message}*`;
                this.updateStreamingMessage(aiMessage, errorMessage);
            }
            
            this.finishStreaming(aiMessage, `Admin Error: ${error.message}`);
        }
    }

    // Override addMessage to show admin styling
    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        const messagesContainer = document.getElementById('chat-messages');
        if (!messagesContainer) return;

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;
        
        const avatarDiv = document.createElement('div');
        avatarDiv.className = `message-avatar avatar-${sender}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        
        if (sender === 'user') {
            avatarDiv.innerHTML = '<i class="bi bi-shield-check"></i>';
            contentDiv.innerHTML = `<div class="d-flex align-items-center mb-1">
                <i class="bi bi-shield-check text-danger me-2"></i>
                <strong>Admin User</strong>
                <span class="badge bg-danger ms-2">ADMIN</span>
            </div>` + (window.marked ? marked.parse(content) : content);
        } else {
            avatarDiv.innerHTML = '<i class="bi bi-robot"></i>';
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
        }
        
        messageDiv.appendChild(avatarDiv);
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
        
        return messageDiv;
    }
}

// =============================================================================
// ADMIN-SPECIFIC FUNCTIONS
// =============================================================================

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
        sharedInterface.showError('Failed to load system logs: ' + error.message);
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
            sharedInterface.showSuccess('Admin chat history exported successfully');
        } else {
            throw new Error('Failed to export admin chat history');
        }
    } catch (error) {
        console.error('Admin export error:', error);
        sharedInterface.showError('Admin export failed: ' + error.message);
    }
};

// =============================================================================
// ADMIN USER MANAGEMENT FUNCTIONS
// =============================================================================

window.loadPendingUsers = async function() {
    try {
        const response = await fetch('/api/admin/users/pending', { credentials: 'include' });
        const data = await response.json();
        
        if (data.success) {
            displayPendingUsers(data.pending_users, data.count, data.max_pending);
        } else {
            throw new Error(data.error || 'Failed to load pending users');
        }
    } catch (error) {
        console.error('Failed to load pending users:', error);
        showUserManagementError('Failed to load pending users: ' + error.message);
    }
};

window.loadAllUsers = async function() {
    try {
        const response = await fetch('/api/admin/users', { credentials: 'include' });
        const data = await response.json();
        
        if (data.success) {
            displayAllUsers(data.users, data.stats);
        } else {
            throw new Error(data.error || 'Failed to load users');
        }
    } catch (error) {
        console.error('Failed to load users:', error);
        showUserManagementError('Failed to load users: ' + error.message);
    }
};

window.approveUser = async function(username) {
    if (!confirm(`Approve user "${username}"?`)) return;
    
    try {
        const response = await fetch('/api/admin/users/approve', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include',
            body: JSON.stringify({ username: username })
        });
        
        const data = await response.json();
        
        if (data.success) {
            showUserManagementSuccess(`User "${username}" approved successfully`);
            loadPendingUsers(); // Refresh the list
        } else {
            throw new Error(data.error || 'Failed to approve user');
        }
    } catch (error) {
        console.error('Failed to approve user:', error);
        showUserManagementError('Failed to approve user: ' + error.message);
    }
};

window.rejectUser = async function(username) {
    const reason = prompt(`Reject user "${username}"?\nReason (optional):`) || 'No reason provided';
    if (reason === null) return; // User cancelled
    
    if (!confirm(`Are you sure you want to reject and delete user "${username}"?`)) return;
    
    try {
        const response = await fetch('/api/admin/users/reject', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include',
            body: JSON.stringify({ username: username, reason: reason })
        });
        
        const data = await response.json();
        
        if (data.success) {
            showUserManagementSuccess(`User "${username}" rejected and deleted`);
            loadPendingUsers(); // Refresh the list
        } else {
            throw new Error(data.error || 'Failed to reject user');
        }
    } catch (error) {
        console.error('Failed to reject user:', error);
        showUserManagementError('Failed to reject user: ' + error.message);
    }
};

window.refreshSystemStats = async function() {
    try {
        const response = await fetch('/api/admin/stats', { credentials: 'include' });
        const data = await response.json();
        
        if (data.success) {
            displaySystemStats(data.stats);
        } else {
            throw new Error(data.error || 'Failed to load stats');
        }
    } catch (error) {
        console.error('Failed to refresh stats:', error);
        showUserManagementError('Failed to refresh stats: ' + error.message);
    }
};

window.clearGuestSessions = async function() {
    if (!confirm('Clear all guest sessions? This will disconnect all guest users.')) return;
    
    try {
        const response = await fetch('/api/admin/clear-guest-sessions', {
            method: 'POST',
            credentials: 'include'
        });
        
        const data = await response.json();
        
        if (data.success) {
            showUserManagementSuccess('Guest sessions cleared successfully');
            refreshSystemStats(); // Refresh stats
        } else {
            throw new Error(data.error || 'Failed to clear guest sessions');
        }
    } catch (error) {
        console.error('Failed to clear guest sessions:', error);
        showUserManagementError('Failed to clear guest sessions: ' + error.message);
    }
};

// =============================================================================
// ADMIN UI DISPLAY FUNCTIONS - Using shared alert system
// =============================================================================

function displayPendingUsers(users, count, maxPending) {
    const container = document.getElementById('user-management-content');
    if (!container) return;
    
    if (users.length === 0) {
        container.innerHTML = `
            <div class="alert alert-info">
                <i class="bi bi-info-circle"></i> No pending users (${count}/${maxPending})
            </div>
        `;
        return;
    }
    
    let html = `
        <div class="alert alert-warning">
            <i class="bi bi-clock-history"></i> ${count} pending user${count !== 1 ? 's' : ''} (${count}/${maxPending})
        </div>
        <div class="table-responsive">
            <table class="table table-dark table-striped">
                <thead>
                    <tr>
                        <th>Username</th>
                        <th>Created</th>
                        <th>IP Address</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
    `;
    
    users.forEach(user => {
        const createdDate = new Date(user.created_at).toLocaleString();
        html += `
            <tr>
                <td><strong>${user.username}</strong></td>
                <td>${createdDate}</td>
                <td><small class="text-muted">${user.created_ip || 'unknown'}</small></td>
                <td>
                    <button class="btn btn-success btn-sm me-2" onclick="approveUser('${user.username}')">
                        <i class="bi bi-check-circle"></i> Approve
                    </button>
                    <button class="btn btn-danger btn-sm" onclick="rejectUser('${user.username}')">
                        <i class="bi bi-x-circle"></i> Reject
                    </button>
                </td>
            </tr>
        `;
    });
    
    html += `
                </tbody>
            </table>
        </div>
    `;
    
    container.innerHTML = html;
}

function displayAllUsers(users, stats) {
    const container = document.getElementById('user-management-content');
    if (!container) return;
    
    let html = `
        <div class="row mb-3">
            <div class="col-md-3">
                <div class="card bg-primary">
                    <div class="card-body text-center">
                        <h5>${stats.total}</h5>
                        <small>Total Users</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card bg-success">
                    <div class="card-body text-center">
                        <h5>${stats.approved}</h5>
                        <small>Approved</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card bg-warning">
                    <div class="card-body text-center">
                        <h5>${stats.pending}</h5>
                        <small>Pending</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card bg-danger">
                    <div class="card-body text-center">
                        <h5>${stats.admin}</h5>
                        <small>Admin</small>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="table-responsive">
            <table class="table table-dark table-striped">
                <thead>
                    <tr>
                        <th>Username</th>
                        <th>Status</th>
                        <th>Created</th>
                        <th>Last Active</th>
                        <th>IP Address</th>
                    </tr>
                </thead>
                <tbody>
    `;
    
    users.forEach(user => {
        const createdDate = new Date(user.created_at).toLocaleString();
        const lastActive = user.last_active ? new Date(user.last_active).toLocaleString() : 'Never';
        
        let statusBadge = '';
        if (user.is_admin === 'true') {
            statusBadge = '<span class="badge bg-danger">Admin</span>';
        } else if (user.is_approved === 'true') {
            statusBadge = '<span class="badge bg-success">Approved</span>';
        } else {
            statusBadge = '<span class="badge bg-warning">Pending</span>';
        }
        
        html += `
            <tr>
                <td><strong>${user.username}</strong></td>
                <td>${statusBadge}</td>
                <td>${createdDate}</td>
                <td>${lastActive}</td>
                <td><small class="text-muted">${user.created_ip || 'unknown'}</small></td>
            </tr>
        `;
    });
    
    html += `
                </tbody>
            </table>
        </div>
    `;
    
    container.innerHTML = html;
}

function displaySystemStats(stats) {
    const container = document.getElementById('system-stats');
    if (!container) return;
    
    const html = `
        <div class="row">
            <div class="col-md-6">
                <h6 class="text-primary">Guest Sessions</h6>
                <p>Active: ${stats.guest_sessions.active_sessions}/${stats.guest_sessions.max_sessions}<br>
                Available: ${stats.guest_sessions.available_slots}</p>
                
                <h6 class="text-primary">SSE Sessions</h6>
                <p>Active: ${stats.sse_sessions.total_sessions}/${stats.sse_sessions.max_sessions}<br>
                Available: ${stats.sse_sessions.available_slots}</p>
            </div>
            <div class="col-md-6">
                <h6 class="text-primary">Users</h6>
                <p>Total: ${stats.user_counts.total}<br>
                Approved: ${stats.user_counts.approved}<br>
                Pending: ${stats.user_counts.pending}<br>
                Admin: ${stats.user_counts.admin}</p>
                
                <h6 class="text-primary">Registration</h6>
                <p>Status: ${stats.registration.registration_health.status}<br>
                Pending Ratio: ${(stats.registration.registration_health.pending_ratio * 100).toFixed(1)}%</p>
            </div>
        </div>
        
        <div class="mt-3">
            <small class="text-muted">
                Last updated: ${new Date().toLocaleString()}<br>
                <strong>AI Engine:</strong> Ollama (${stats.ai_engine || 'Devstral'})
            </small>
        </div>
    `;
    
    container.innerHTML = html;
}

function showUserManagementError(message) {
    sharedInterface.showError(message);
    const container = document.getElementById('user-management-content');
    if (container) {
        container.innerHTML = `
            <div class="alert alert-danger">
                <i class="bi bi-exclamation-triangle"></i> ${message}
            </div>
        `;
    }
}

function showUserManagementSuccess(message) {
    sharedInterface.showSuccess(message);
    const container = document.getElementById('user-management-content');
    if (container) {
        const existingAlert = container.querySelector('.alert-success');
        if (existingAlert) existingAlert.remove();
        
        const alert = document.createElement('div');
        alert.className = 'alert alert-success';
        alert.innerHTML = `<i class="bi bi-check-circle"></i> ${message}`;
        container.insertBefore(alert, container.firstChild);
        
        setTimeout(() => {
            if (alert.parentNode) alert.remove();
        }, 3000);
    }
}

// Auto-load system stats when page loads
document.addEventListener('DOMContentLoaded', () => {
    if (document.getElementById('system-stats')) {
        refreshSystemStats();
    }
    
    // Only initialize if we're actually an admin user
    sharedInterface.checkAuth()
        .then(data => {
            if (data.success && data.user_type === 'is_admin') {
                // Initialize main admin chat if on chat page
                if (window.location.pathname === '/chat') {
                    window.adminChat = new AdminChat();
                    window.chatSystem = window.adminChat; // For compatibility
                    console.log('💬 Admin chat initialized');
                }
            }
        })
        .catch(error => {
            console.warn('Could not check auth status for admin user:', error);
        });
});