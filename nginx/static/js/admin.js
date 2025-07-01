// static/js/admin.js - Admin Page Handler

const AdminPage = {
    elements: {},
    
    init: function() {
        this.elements = {
            userList: document.getElementById('userList'),
            chatHistory: document.getElementById('chatHistory'),
            selectedUserText: document.getElementById('selectedUser')
        };
        
        // Initialize database management
        AdminDB.init();
        this.loadUsers();
    },
    
    loadUsers: async function() {
        try {
            const response = await fetch('/api/admin/users');
            const data = await response.json();
            
            this.renderUserList(data.users);
        } catch (error) {
            console.error('Error loading users:', error);
            window.Utils.showError('Failed to load users', this.elements.userList);
        }
    },
    
    renderUserList: function(users) {
        if (!this.elements.userList) return;
        
        this.elements.userList.innerHTML = '';
        
        users.forEach(user => {
            const userDiv = document.createElement('div');
            userDiv.className = 'p-2 mb-2 bg-secondary rounded user-card';
            userDiv.innerHTML = `
                <div class="d-flex justify-content-between align-items-center">
                    <span class="user-name">${user.username}</span>
                    <div class="user-actions">
                        <span class="badge ${user.is_admin ? 'bg-danger' : 'bg-primary'} me-2">
                            ${user.is_admin ? 'Admin' : 'User'}
                        </span>
                        ${!user.is_admin ? `
                            <div class="btn-group btn-group-sm">
                                <button class="btn btn-outline-warning" onclick="AdminPage.deleteUserMessages('${user.id}')" title="Delete messages only">
                                    <i class="bi bi-chat-x"></i>
                                </button>
                                <button class="btn btn-outline-danger" onclick="AdminPage.deleteUser('${user.id}')" title="Delete user and all data">
                                    <i class="bi bi-person-x"></i>
                                </button>
                            </div>
                        ` : ''}
                    </div>
                </div>
                <small class="text-muted">
                    Joined: ${window.Utils.formatDate(user.created_at)}
                    ${user.session_count !== undefined ? `• ${user.session_count} sessions` : ''}
                    ${user.message_count !== undefined ? `• ${user.message_count} messages` : ''}
                </small>
            `;
            
            // Add click handler for viewing chat
            const userName = userDiv.querySelector('.user-name');
            userName.style.cursor = 'pointer';
            userName.addEventListener('click', () => this.loadUserChat(user.id, user.username));
            
            this.elements.userList.appendChild(userDiv);
        });
    },
    
    deleteUser: async function(userId) {
        if (!confirm('Are you sure you want to delete this user and ALL their data? This action cannot be undone!')) {
            return;
        }
        
        try {
            const response = await fetch(`/api/admin/users/${userId}`, {
                method: 'DELETE',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                }
            });
            
            const result = await response.json();
            
            if (response.ok) {
                window.Utils.showSuccess(result.message, this.elements.userList);
                // Refresh the user list
                await this.loadUsers();
                // Clear chat history if this was the selected user
                if (this.elements.chatHistory.dataset.userId === userId) {
                    this.elements.chatHistory.innerHTML = '<p class="text-muted text-center">User has been deleted</p>';
                    this.elements.selectedUserText.textContent = 'Select a user to view their chat history';
                }
            } else {
                window.Utils.showError(result.error || result.message, this.elements.userList);
            }
        } catch (error) {
            console.error('Error deleting user:', error);
            window.Utils.showError('Failed to delete user', this.elements.userList);
        }
    },
    
    deleteUserMessages: async function(userId) {
        if (!confirm('Are you sure you want to delete all messages for this user? The user account will be kept.')) {
            return;
        }
        
        try {
            const response = await fetch(`/api/admin/users/${userId}/messages`, {
                method: 'DELETE',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                }
            });
            
            const result = await response.json();
            
            if (response.ok) {
                window.Utils.showSuccess(result.message, this.elements.userList);
                // Refresh the user list to update message counts
                await this.loadUsers();
                // Clear chat history if this was the selected user
                if (this.elements.chatHistory.dataset.userId === userId) {
                    this.elements.chatHistory.innerHTML = '<p class="text-muted text-center">Messages have been deleted</p>';
                }
            } else {
                window.Utils.showError(result.error || result.message, this.elements.userList);
            }
        } catch (error) {
            console.error('Error deleting messages:', error);
            window.Utils.showError('Failed to delete messages', this.elements.userList);
        }
    },
    
    loadUserChat: async function(userId, username) {
        try {
            this.elements.selectedUserText.textContent = `Chat history for: ${username}`;
            this.elements.chatHistory.dataset.userId = userId; // Store current user ID
            
            const response = await fetch(`/api/admin/chat/${userId}`);
            const data = await response.json();
            
            this.elements.chatHistory.innerHTML = '';
            
            if (data.messages.length === 0) {
                this.elements.chatHistory.innerHTML = '<p class="text-muted text-center">No chat history found</p>';
                return;
            }
            
            data.messages.forEach(msg => {
                const messageDiv = document.createElement('div');
                messageDiv.className = `admin-message ${msg.role === 'user' ? 'admin-user-message' : 'admin-assistant-message'}`;
                
                const processedContent = window.Utils.processMessageContent(msg.content);
                messageDiv.appendChild(processedContent);
                
                const timestamp = document.createElement('small');
                timestamp.className = 'text-muted message-timestamp';
                timestamp.textContent = window.Utils.formatDate(msg.timestamp);
                messageDiv.appendChild(timestamp);
                
                this.elements.chatHistory.appendChild(messageDiv);
            });
            
            // Apply syntax highlighting to admin chat
            setTimeout(() => {
                if (window.Prism) {
                    window.Prism.highlightAll();
                }
            }, 100);
            
            this.elements.chatHistory.scrollTop = this.elements.chatHistory.scrollHeight;
        } catch (error) {
            console.error('Error loading chat history:', error);
            window.Utils.showError('Failed to load chat history', this.elements.chatHistory);
        }
    }
};

// Admin Database Management
const AdminDB = {
    currentAction: null,
    
    init: function() {
        this.loadDatabaseStats();
        this.bindEvents();
    },

    bindEvents: function() {
        // Confirmation modal events
        const confirmBtn = document.getElementById('confirmActionBtn');
        if (confirmBtn) {
            confirmBtn.addEventListener('click', this.executeCleanup.bind(this));
        }
    },
    
    loadDatabaseStats: async function() {
        try {
            const response = await fetch('/api/admin/database/stats');
            const stats = await response.json();
            
            if (stats.error) {
                this.renderStatsError(stats.error);
                return;
            }
            
            this.renderDatabaseStats(stats);
        } catch (error) {
            console.error('Error loading database stats:', error);
            this.renderStatsError(error.message);
        }
    },
    
    renderDatabaseStats: function(stats) {
        const container = document.getElementById('databaseStats');
        const statusBadge = document.getElementById('dbStatusBadge');
        const userCount = document.getElementById('userCount');
        
        if (!container) return; // Not on admin page
        
        statusBadge.textContent = 'Online';
        statusBadge.className = 'badge bg-success ms-2';
        userCount.textContent = stats.user_count || 0;
        
        container.innerHTML = `
            <div class="row text-center">
                <div class="col-6">
                    <div class="border rounded p-2 mb-2">
                        <div class="h4 text-primary mb-0">${stats.total_keys || 0}</div>
                        <small class="text-muted">Total Keys</small>
                    </div>
                </div>
                <div class="col-6">
                    <div class="border rounded p-2 mb-2">
                        <div class="h4 text-info mb-0">${stats.user_count || 0}</div>
                        <small class="text-muted">Users</small>
                    </div>
                </div>
            </div>
            <div class="mb-2">
                <small class="text-muted">Key Types:</small>
                <ul class="list-unstyled small">
                    ${Object.entries(stats.key_types || {}).map(([type, count]) => 
                        `<li>• ${type}: ${count}</li>`
                    ).join('')}
                </ul>
            </div>
            ${stats.memory_usage ? `
                <div class="mb-2">
                    <small class="text-muted">Memory: ${stats.memory_usage.used_memory}</small>
                </div>
            ` : ''}
            <div>
                <small class="text-muted">Next User ID: ${stats.next_user_id}</small>
            </div>
        `;
    },
    
    renderStatsError: function(error) {
        const container = document.getElementById('databaseStats');
        const statusBadge = document.getElementById('dbStatusBadge');
        
        if (!container) return; // Not on admin page
        
        statusBadge.textContent = 'Error';
        statusBadge.className = 'badge bg-danger ms-2';
        
        container.innerHTML = `
            <div class="alert alert-danger">
                <strong>Database Error:</strong> ${error}
            </div>
        `;
    },
    
    performCleanup: function(type) {
        const actions = {
            'clear_cache': {
                title: 'Clear Cache',
                message: 'This will clear all AI response cache and rate limiting data. Chat history will be preserved.',
                danger: false
            },
            'fix_sessions': {
                title: 'Fix Orphaned Sessions',
                message: 'This will remove chat sessions that belong to deleted users.',
                danger: false
            },
            'recreate_admin': {
                title: 'Recreate Admin User',
                message: 'This will recreate the admin user with proper settings. Current admin sessions may be affected.',
                danger: true
            },
            'fix_users': {
                title: 'Fix User Data',
                message: 'This will reset all user accounts and recreate the admin user. All user accounts will be lost, but chat data will be preserved.',
                danger: true
            },
            'complete_reset': {
                title: 'Complete Database Reset',
                message: 'This will delete ALL data from the database and recreate only the admin user. Everything will be lost!',
                danger: true
            }
        };
        
        const action = actions[type];
        if (!action) return;
        
        this.currentAction = type;
        
        document.getElementById('confirmationMessage').innerHTML = `
            <strong>${action.title}</strong><br>
            ${action.message}
        `;
        
        const confirmBtn = document.getElementById('confirmActionBtn');
        confirmBtn.className = action.danger ? 'btn btn-danger' : 'btn btn-warning';
        confirmBtn.textContent = action.danger ? 'Yes, Delete' : 'Confirm';
        
        const modal = new bootstrap.Modal(document.getElementById('confirmationModal'));
        modal.show();
    },

    executeCleanup: async function() {
        const modal = bootstrap.Modal.getInstance(document.getElementById('confirmationModal'));
        modal.hide();
        
        if (!this.currentAction) return;
        
        // Show loading modal
        const loadingModal = new bootstrap.Modal(document.getElementById('loadingModal'));
        document.getElementById('loadingMessage').textContent = 'Processing database operation...';
        loadingModal.show();
        
        try {
            const response = await fetch('/api/admin/database/cleanup', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                },
                body: JSON.stringify({ type: this.currentAction })
            });
            
            const result = await response.json();
            
            loadingModal.hide();
            
            // Show results
            const resultsDiv = document.getElementById('cleanupResults');
            const messageDiv = document.getElementById('cleanupMessage');
            
            if (result.success) {
                messageDiv.className = 'alert alert-success';
                messageDiv.innerHTML = `
                    <strong>Success!</strong> ${result.message}
                    <br><small>Completed at: ${new Date(result.timestamp).toLocaleString()}</small>
                `;
            } else {
                messageDiv.className = 'alert alert-danger';
                messageDiv.innerHTML = `<strong>Error:</strong> ${result.message}`;
            }
            
            resultsDiv.style.display = 'block';
            
            // Refresh data
            setTimeout(() => {
                this.refreshAllData();
            }, 1000);
            
        } catch (error) {
            loadingModal.hide();
            console.error('Cleanup error:', error);
            
            const resultsDiv = document.getElementById('cleanupResults');
            const messageDiv = document.getElementById('cleanupMessage');
            
            messageDiv.className = 'alert alert-danger';
            messageDiv.innerHTML = `<strong>Network Error:</strong> ${error.message}`;
            resultsDiv.style.display = 'block';
        }
        
        this.currentAction = null;
    },

    createBackup: async function() {
        const loadingModal = new bootstrap.Modal(document.getElementById('loadingModal'));
        document.getElementById('loadingMessage').textContent = 'Creating database backup...';
        loadingModal.show();
        
        try {
            const response = await fetch('/api/admin/database/backup');
            const backup = await response.json();
            
            loadingModal.hide();
            
            if (backup.error) {
                alert('Backup failed: ' + backup.error);
                return;
            }
            
            // Download backup as JSON file
            const blob = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `redis-backup-${new Date().toISOString().split('T')[0]}.json`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
        } catch (error) {
            loadingModal.hide();
            console.error('Backup error:', error);
            alert('Backup failed: ' + error.message);
        }
    },

    refreshAllData: function() {
        this.loadDatabaseStats();
        AdminPage.loadUsers();
    }
};

// Make functions globally available for onclick handlers
window.performCleanup = (type) => AdminDB.performCleanup(type);
window.createBackup = () => AdminDB.createBackup();
window.refreshAllData = () => AdminDB.refreshAllData();

// Export for use
window.AdminPage = AdminPage;
window.AdminDB = AdminDB;