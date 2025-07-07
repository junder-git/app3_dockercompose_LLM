// admin.js - Admin Module

class AdminModule {
    constructor(app) {
        this.app = app;
        this.currentUser = null;
        this.systemStats = null;
        this.refreshInterval = null;
        
        console.log('👑 AdminModule created');
    }

    async loadAdminPage() {
        try {
            // Verify admin access
            this.currentUser = await this.app.modules.auth.getCurrentUser();
            if (!this.currentUser || !this.currentUser.is_admin) {
                throw new Error('Admin access required');
            }

            const html = `
                <div class="container-fluid">
                    <div class="row">
                        <div class="col-12">
                            <div class="d-flex justify-content-between align-items-center mb-4">
                                <h2><i class="bi bi-shield-lock"></i> Admin Dashboard</h2>
                                <div class="btn-group">
                                    <button class="btn btn-outline-primary btn-sm" onclick="window.DevstralApp.modules.admin.refreshStats()">
                                        <i class="bi bi-arrow-clockwise"></i> Refresh
                                    </button>
                                    <button class="btn btn-outline-secondary btn-sm" onclick="window.DevstralApp.modules.admin.exportSystemData()">
                                        <i class="bi bi-download"></i> Export Data
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>

                    <!-- System Stats Cards -->
                    <div class="row mb-4" id="admin-stats-cards">
                        <!-- Will be populated by loadSystemStats -->
                    </div>

                    <!-- Navigation Tabs -->
                    <ul class="nav nav-tabs mb-4" id="admin-tabs">
                        <li class="nav-item">
                            <button class="nav-link active" data-bs-toggle="tab" data-bs-target="#users-tab">
                                <i class="bi bi-people"></i> User Management
                            </button>
                        </li>
                        <li class="nav-item">
                            <button class="nav-link" data-bs-toggle="tab" data-bs-target="#system-tab">
                                <i class="bi bi-gear"></i> System Info
                            </button>
                        </li>
                        <li class="nav-item">
                            <button class="nav-link" data-bs-toggle="tab" data-bs-target="#database-tab">
                                <i class="bi bi-database"></i> Database
                            </button>
                        </li>
                    </ul>

                    <!-- Tab Content -->
                    <div class="tab-content">
                        <!-- Users Tab -->
                        <div class="tab-pane fade show active" id="users-tab">
                            <div class="row">
                                <div class="col-lg-8">
                                    <div class="card">
                                        <div class="card-header">
                                            <h5><i class="bi bi-people"></i> All Users</h5>
                                        </div>
                                        <div class="card-body">
                                            <div id="users-list">
                                                <!-- Will be populated by loadUsers -->
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-lg-4">
                                    <div class="card">
                                        <div class="card-header">
                                            <h5><i class="bi bi-person-plus"></i> Pending Approvals</h5>
                                        </div>
                                        <div class="card-body">
                                            <div id="pending-users">
                                                <!-- Will be populated by loadPendingUsers -->
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- System Tab -->
                        <div class="tab-pane fade" id="system-tab">
                            <div class="row">
                                <div class="col-lg-6">
                                    <div class="card">
                                        <div class="card-header">
                                            <h5><i class="bi bi-cpu"></i> System Health</h5>
                                        </div>
                                        <div class="card-body">
                                            <div id="system-health">
                                                <!-- Will be populated by loadSystemHealth -->
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-lg-6">
                                    <div class="card">
                                        <div class="card-header">
                                            <h5><i class="bi bi-graph-up"></i> Performance Metrics</h5>
                                        </div>
                                        <div class="card-body">
                                            <div id="performance-metrics">
                                                <!-- Will be populated by loadPerformanceMetrics -->
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- Database Tab -->
                        <div class="tab-pane fade" id="database-tab">
                            <div class="row">
                                <div class="col-lg-8">
                                    <div class="card">
                                        <div class="card-header">
                                            <h5><i class="bi bi-database"></i> Database Statistics</h5>
                                        </div>
                                        <div class="card-body">
                                            <div id="database-stats">
                                                <!-- Will be populated by loadDatabaseStats -->
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-lg-4">
                                    <div class="card">
                                        <div class="card-header">
                                            <h5><i class="bi bi-tools"></i> Database Tools</h5>
                                        </div>
                                        <div class="card-body">
                                            <div id="database-tools">
                                                <button class="btn btn-outline-warning btn-sm w-100 mb-2" onclick="window.DevstralApp.modules.admin.validateDataIntegrity()">
                                                    <i class="bi bi-shield-check"></i> Validate Integrity
                                                </button>
                                                <button class="btn btn-outline-info btn-sm w-100 mb-2" onclick="window.DevstralApp.modules.admin.cleanupExpiredData()">
                                                    <i class="bi bi-trash"></i> Cleanup Expired Data
                                                </button>
                                                <button class="btn btn-outline-danger btn-sm w-100" onclick="window.DevstralApp.modules.admin.showResetSystemDialog()">
                                                    <i class="bi bi-exclamation-triangle"></i> Reset System
                                                </button>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            `;

            $('#app-content').html(html);
            
            // Load initial data
            await this.loadAllData();
            
            // Set up auto-refresh
            this.startAutoRefresh();

        } catch (error) {
            console.error('❌ Error loading admin page:', error);
            this.app.showError('Failed to load admin page', error.message);
        }
    }

    async loadAllData() {
        try {
            await Promise.all([
                this.loadSystemStats(),
                this.loadUsers(),
                this.loadPendingUsers(),
                this.loadSystemHealth(),
                this.loadDatabaseStats()
            ]);
        } catch (error) {
            console.error('❌ Error loading admin data:', error);
            this.app.showFlashMessage('Some data failed to load', 'warning');
        }
    }

    async loadSystemStats() {
        try {
            const stats = await window.Database.getDatabaseStats();
            this.systemStats = stats;

            const html = `
                <div class="col-md-3">
                    <div class="card border-primary">
                        <div class="card-body text-center">
                            <i class="bi bi-people text-primary" style="font-size: 2rem;"></i>
                            <h3 class="mt-2">${stats.user_count}</h3>
                            <p class="text-muted">Total Users</p>
                        </div>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card border-warning">
                        <div class="card-body text-center">
                            <i class="bi bi-hourglass text-warning" style="font-size: 2rem;"></i>
                            <h3 class="mt-2">${stats.pending_count}</h3>
                            <p class="text-muted">Pending Approval</p>
                        </div>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card border-success">
                        <div class="card-body text-center">
                            <i class="bi bi-check-circle text-success" style="font-size: 2rem;"></i>
                            <h3 class="mt-2">${stats.approved_count}</h3>
                            <p class="text-muted">Approved Users</p>
                        </div>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card border-info">
                        <div class="card-body text-center">
                            <i class="bi bi-database text-info" style="font-size: 2rem;"></i>
                            <h3 class="mt-2">${stats.total_keys}</h3>
                            <p class="text-muted">Database Keys</p>
                        </div>
                    </div>
                </div>
            `;

            $('#admin-stats-cards').html(html);
        } catch (error) {
            console.error('❌ Error loading system stats:', error);
        }
    }

    async loadUsers() {
        try {
            const users = await window.Database.getAllUsers();
            
            if (users.length === 0) {
                $('#users-list').html('<p class="text-muted">No users found.</p>');
                return;
            }

            const userRows = users.map(user => `
                <div class="user-card" data-user-id="${user.id}">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h6 class="mb-1">
                                ${user.username}
                                ${user.is_admin ? '<span class="badge bg-warning text-dark ms-2">Admin</span>' : ''}
                                ${user.is_approved ? '<span class="badge bg-success ms-1">Approved</span>' : '<span class="badge bg-secondary ms-1">Pending</span>'}
                            </h6>
                            <small class="text-muted">
                                <i class="bi bi-calendar"></i> Created: ${Utils.formatRelativeTime(user.created_at)}
                                <br>
                                <i class="bi bi-person-badge"></i> ID: ${user.id}
                            </small>
                        </div>
                        <div class="btn-group btn-group-sm">
                            <button class="btn btn-outline-primary" onclick="window.DevstralApp.modules.admin.viewUserDetail('${user.id}')">
                                <i class="bi bi-eye"></i>
                            </button>
                            ${!user.is_admin ? `
                                <button class="btn btn-outline-danger" onclick="window.DevstralApp.modules.admin.deleteUser('${user.id}', '${user.username}')">
                                    <i class="bi bi-trash"></i>
                                </button>
                            ` : ''}
                        </div>
                    </div>
                </div>
            `).join('');

            $('#users-list').html(userRows);
        } catch (error) {
            console.error('❌ Error loading users:', error);
            $('#users-list').html('<p class="text-danger">Failed to load users.</p>');
        }
    }

    async loadPendingUsers() {
        try {
            const pendingUsers = await window.Database.getPendingUsers();
            
            if (pendingUsers.length === 0) {
                $('#pending-users').html('<p class="text-muted">No pending approvals.</p>');
                return;
            }

            const pendingRows = pendingUsers.map(user => `
                <div class="card mb-2 border-warning">
                    <div class="card-body p-3">
                        <h6 class="card-title mb-1">${user.username}</h6>
                        <small class="text-muted d-block mb-2">
                            Registered ${Utils.formatRelativeTime(user.created_at)}
                        </small>
                        <div class="btn-group btn-group-sm w-100">
                            <button class="btn btn-success" onclick="window.DevstralApp.modules.admin.approveUser('${user.id}', '${user.username}')">
                                <i class="bi bi-check"></i> Approve
                            </button>
                            <button class="btn btn-danger" onclick="window.DevstralApp.modules.admin.rejectUser('${user.id}', '${user.username}')">
                                <i class="bi bi-x"></i> Reject
                            </button>
                        </div>
                    </div>
                </div>
            `).join('');

            $('#pending-users').html(pendingRows);
        } catch (error) {
            console.error('❌ Error loading pending users:', error);
            $('#pending-users').html('<p class="text-danger">Failed to load pending users.</p>');
        }
    }

    async loadSystemHealth() {
        try {
            const health = await window.AppInit.performHealthCheck();
            
            const statusColor = {
                'healthy': 'success',
                'degraded': 'warning',
                'unhealthy': 'danger',
                'error': 'danger'
            }[health.status] || 'secondary';

            const checksHtml = Object.entries(health.checks || {}).map(([check, status]) => `
                <div class="d-flex justify-content-between">
                    <span>${Utils.capitalizeFirst(check.replace('_', ' '))}:</span>
                    <span class="badge bg-${status ? 'success' : 'danger'}">
                        ${status ? 'OK' : 'FAIL'}
                    </span>
                </div>
            `).join('');

            const html = `
                <div class="mb-3">
                    <h6>Overall Status: <span class="badge bg-${statusColor}">${health.status.toUpperCase()}</span></h6>
                    <small class="text-muted">Last checked: ${Utils.formatTimestamp(health.timestamp)}</small>
                </div>
                <div class="border-top pt-3">
                    <h6>Health Checks:</h6>
                    ${checksHtml}
                </div>
                ${health.details && Object.keys(health.details).length > 0 ? `
                    <div class="border-top pt-3 mt-3">
                        <h6>Details:</h6>
                        <pre class="small">${JSON.stringify(health.details, null, 2)}</pre>
                    </div>
                ` : ''}
            `;

            $('#system-health').html(html);
        } catch (error) {
            console.error('❌ Error loading system health:', error);
            $('#system-health').html('<p class="text-danger">Failed to load system health.</p>');
        }
    }

    async loadDatabaseStats() {
        try {
            const stats = await window.Database.getDatabaseStats();
            
            const keyTypesHtml = Object.entries(stats.key_types || {}).map(([type, count]) => `
                <tr>
                    <td>${type}</td>
                    <td>${count}</td>
                </tr>
            `).join('');

            const html = `
                <div class="row">
                    <div class="col-md-6">
                        <h6>Key Statistics:</h6>
                        <table class="table table-sm">
                            <thead>
                                <tr>
                                    <th>Key Type</th>
                                    <th>Count</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${keyTypesHtml}
                            </tbody>
                        </table>
                    </div>
                    <div class="col-md-6">
                        <h6>Summary:</h6>
                        <ul class="list-unstyled">
                            <li><strong>Total Keys:</strong> ${stats.total_keys}</li>
                            <li><strong>Total Users:</strong> ${stats.user_count}</li>
                            <li><strong>Pending Users:</strong> ${stats.pending_count}</li>
                            <li><strong>Approved Users:</strong> ${stats.approved_count}</li>
                        </ul>
                    </div>
                </div>
            `;

            $('#database-stats').html(html);
        } catch (error) {
            console.error('❌ Error loading database stats:', error);
            $('#database-stats').html('<p class="text-danger">Failed to load database stats.</p>');
        }
    }

    async viewUserDetail(userId) {
        this.app.navigate(`user-detail/${userId}`);
    }

    async loadUserDetailPage(userId) {
        try {
            const user = await window.Database.getUserById(userId);
            if (!user) {
                throw new Error('User not found');
            }

            const sessions = await window.Database.getUserChatSessions(userId);
            const messages = await window.Database.getUserMessages(userId, 50);

            const html = `
                <div class="container-fluid">
                    <div class="row">
                        <div class="col-12">
                            <div class="d-flex justify-content-between align-items-center mb-4">
                                <h2>
                                    <button class="btn btn-outline-secondary me-3" onclick="window.DevstralApp.navigate('admin')">
                                        <i class="bi bi-arrow-left"></i>
                                    </button>
                                    User Details: ${user.username}
                                </h2>
                                <div class="btn-group">
                                    ${!user.is_admin ? `
                                        <button class="btn btn-outline-warning" onclick="window.DevstralApp.modules.admin.clearUserData('${userId}', '${user.username}')">
                                            <i class="bi bi-trash"></i> Clear Data
                                        </button>
                                        <button class="btn btn-outline-danger" onclick="window.DevstralApp.modules.admin.deleteUser('${userId}', '${user.username}')">
                                            <i class="bi bi-person-x"></i> Delete User
                                        </button>
                                    ` : ''}
                                    <button class="btn btn-outline-primary" onclick="window.DevstralApp.modules.admin.exportUserData('${userId}')">
                                        <i class="bi bi-download"></i> Export Data
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="row">
                        <div class="col-lg-4">
                            <div class="card">
                                <div class="card-header">
                                    <h5><i class="bi bi-person"></i> User Information</h5>
                                </div>
                                <div class="card-body">
                                    <table class="table table-borderless">
                                        <tr>
                                            <td><strong>Username:</strong></td>
                                            <td>${user.username}</td>
                                        </tr>
                                        <tr>
                                            <td><strong>User ID:</strong></td>
                                            <td>${user.id}</td>
                                        </tr>
                                        <tr>
                                            <td><strong>Status:</strong></td>
                                            <td>
                                                ${user.is_admin ? '<span class="badge bg-warning text-dark">Admin</span>' : ''}
                                                ${user.is_approved ? '<span class="badge bg-success">Approved</span>' : '<span class="badge bg-secondary">Pending</span>'}
                                            </td>
                                        </tr>
                                        <tr>
                                            <td><strong>Created:</strong></td>
                                            <td>${Utils.formatTimestamp(user.created_at)}</td>
                                        </tr>
                                        <tr>
                                            <td><strong>Sessions:</strong></td>
                                            <td>${sessions.length}</td>
                                        </tr>
                                        <tr>
                                            <td><strong>Messages:</strong></td>
                                            <td>${messages.length}</td>
                                        </tr>
                                    </table>
                                </div>
                            </div>
                        </div>

                        <div class="col-lg-8">
                            <div class="card">
                                <div class="card-header">
                                    <h5><i class="bi bi-chat"></i> Recent Activity</h5>
                                </div>
                                <div class="card-body">
                                    <div class="chat-history" style="max-height: 500px; overflow-y: auto;">
                                        ${this.renderUserMessages(messages)}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            `;

            $('#app-content').html(html);

        } catch (error) {
            console.error('❌ Error loading user detail:', error);
            this.app.showError('Failed to load user details', error.message);
        }
    }

    renderUserMessages(messages) {
        if (messages.length === 0) {
            return '<p class="text-muted">No messages found.</p>';
        }

        return messages.map(msg => `
            <div class="message-item mb-3 p-3 border rounded">
                <div class="d-flex justify-content-between align-items-start mb-2">
                    <span class="badge bg-${msg.role === 'user' ? 'primary' : 'secondary'}">${msg.role}</span>
                    <small class="text-muted">${Utils.formatTimestamp(msg.timestamp)}</small>
                </div>
                <div class="message-content">
                    ${Utils.escapeHtml(msg.content.substring(0, 200))}${msg.content.length > 200 ? '...' : ''}
                </div>
            </div>
        `).join('');
    }

    async approveUser(userId, username) {
        try {
            const result = await window.Database.approveUser(userId);
            if (result.success) {
                this.app.showFlashMessage(`User ${username} approved successfully`, 'success');
                await this.loadAllData();
            } else {
                throw new Error(result.message);
            }
        } catch (error) {
            console.error('❌ Error approving user:', error);
            this.app.showFlashMessage(`Failed to approve user: ${error.message}`, 'error');
        }
    }

    async rejectUser(userId, username) {
        Utils.confirmDialog(
            'Reject User',
            `Are you sure you want to reject and delete user "${username}"? This action cannot be undone.`,
            async () => {
                try {
                    const result = await window.Database.rejectUser(userId);
                    if (result.success) {
                        this.app.showFlashMessage(`User ${username} rejected and deleted`, 'success');
                        await this.loadAllData();
                    } else {
                        throw new Error(result.message);
                    }
                } catch (error) {
                    console.error('❌ Error rejecting user:', error);
                    this.app.showFlashMessage(`Failed to reject user: ${error.message}`, 'error');
                }
            }
        );
    }

    async deleteUser(userId, username) {
        Utils.confirmDialog(
            'Delete User',
            `Are you sure you want to permanently delete user "${username}" and all their data? This action cannot be undone.`,
            async () => {
                try {
                    const result = await window.Database.deleteUser(userId);
                    if (result.success) {
                        this.app.showFlashMessage(result.message, 'success');
                        await this.loadAllData();
                    } else {
                        throw new Error(result.message);
                    }
                } catch (error) {
                    console.error('❌ Error deleting user:', error);
                    this.app.showFlashMessage(`Failed to delete user: ${error.message}`, 'error');
                }
            }
        );
    }

    async clearUserData(userId, username) {
        Utils.confirmDialog(
            'Clear User Data',
            `Are you sure you want to clear all chat data for user "${username}"? This will delete all their messages and sessions but keep the user account.`,
            async () => {
                try {
                    const result = await window.Database.clearAllUserData(userId);
                    if (result.success) {
                        this.app.showFlashMessage(result.message, 'success');
                        await this.loadAllData();
                    } else {
                        throw new Error(result.message);
                    }
                } catch (error) {
                    console.error('❌ Error clearing user data:', error);
                    this.app.showFlashMessage(`Failed to clear user data: ${error.message}`, 'error');
                }
            }
        );
    }

    async exportUserData(userId) {
        try {
            const result = await window.Database.exportUserData(userId);
            if (result.success) {
                const user = await window.Database.getUserById(userId);
                const filename = `user_${user.username}_${new Date().toISOString().split('T')[0]}.json`;
                Utils.downloadJSON(result.data, filename);
                this.app.showFlashMessage('User data exported successfully', 'success');
            } else {
                throw new Error(result.message);
            }
        } catch (error) {
            console.error('❌ Error exporting user data:', error);
            this.app.showFlashMessage(`Failed to export user data: ${error.message}`, 'error');
        }
    }

    async exportSystemData() {
        try {
            const stats = await window.Database.getDatabaseStats();
            const health = await window.AppInit.getSystemInfo();
            
            const systemData = {
                export_timestamp: new Date().toISOString(),
                database_stats: stats,
                system_info: health,
                users: stats.users
            };

            const filename = `system_export_${new Date().toISOString().split('T')[0]}.json`;
            Utils.downloadJSON(systemData, filename);
            this.app.showFlashMessage('System data exported successfully', 'success');
        } catch (error) {
            console.error('❌ Error exporting system data:', error);
            this.app.showFlashMessage(`Failed to export system data: ${error.message}`, 'error');
        }
    }

    async validateDataIntegrity() {
        try {
            Utils.showLoadingSpinner('#database-tools button:first-child', 'Validating...');
            
            const result = await window.Database.validateDataIntegrity();
            
            if (result.success) {
                const message = result.issues_found > 0 
                    ? `Found ${result.issues_found} integrity issues. Check console for details.`
                    : 'Data integrity validation passed - no issues found.';
                
                const type = result.issues_found > 0 ? 'warning' : 'success';
                this.app.showFlashMessage(message, type);
                
                if (result.issues_found > 0) {
                    console.log('Data integrity issues:', result.issues);
                }
            } else {
                throw new Error('Validation failed');
            }
        } catch (error) {
            console.error('❌ Error validating data integrity:', error);
            this.app.showFlashMessage(`Failed to validate data integrity: ${error.message}`, 'error');
        } finally {
            Utils.hideLoadingSpinner('#database-tools button:first-child');
        }
    }

    async cleanupExpiredData() {
        try {
            Utils.showLoadingSpinner('#database-tools button:nth-child(2)', 'Cleaning...');
            
            const result = await window.Database.cleanupExpiredSessions();
            
            if (result.success) {
                const message = result.cleaned_sessions > 0 
                    ? `Cleaned up ${result.cleaned_sessions} expired sessions.`
                    : 'No expired data found to clean up.';
                
                this.app.showFlashMessage(message, 'success');
                await this.loadAllData();
            } else {
                throw new Error('Cleanup failed');
            }
        } catch (error) {
            console.error('❌ Error cleaning up data:', error);
            this.app.showFlashMessage(`Failed to cleanup data: ${error.message}`, 'error');
        } finally {
            Utils.hideLoadingSpinner('#database-tools button:nth-child(2)');
        }
    }

    showResetSystemDialog() {
        const modalContent = `
            <div class="alert alert-danger">
                <i class="bi bi-exclamation-triangle"></i>
                <strong>WARNING:</strong> This will permanently delete ALL data including users, messages, and system settings. This action cannot be undone!
            </div>
            <p>To confirm, type <strong>RESET_ALL_DATA</strong> in the field below:</p>
            <input type="text" id="reset-confirmation" class="form-control" placeholder="Type RESET_ALL_DATA to confirm">
        `;

        Utils.showModal('Reset System', modalContent, [
            {
                text: 'Cancel',
                type: 'secondary',
                dismiss: true
            },
            {
                text: 'RESET SYSTEM',
                type: 'danger',
                onclick: `window.DevstralApp.modules.admin.executeSystemReset()`
            }
        ]);
    }

    async executeSystemReset() {
        const confirmation = $('#reset-confirmation').val();
        
        if (confirmation !== 'RESET_ALL_DATA') {
            this.app.showFlashMessage('Invalid confirmation text', 'error');
            return;
        }

        try {
            const result = await window.AppInit.resetSystem(confirmation);
            if (result.success) {
                this.app.showFlashMessage('System reset successfully. Reloading...', 'success');
                setTimeout(() => {
                    window.location.reload();
                }, 2000);
            } else {
                throw new Error(result.message || 'Reset failed');
            }
        } catch (error) {
            console.error('❌ Error resetting system:', error);
            this.app.showFlashMessage(`Failed to reset system: ${error.message}`, 'error');
        }
    }

    async refreshStats() {
        try {
            await this.loadAllData();
            this.app.showFlashMessage('Data refreshed successfully', 'success', 2000);
        } catch (error) {
            console.error('❌ Error refreshing stats:', error);
            this.app.showFlashMessage('Failed to refresh data', 'error');
        }
    }

    startAutoRefresh() {
        // Refresh every 30 seconds
        this.refreshInterval = setInterval(() => {
            this.loadSystemStats();
            this.loadSystemHealth();
        }, 30000);
    }

    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
    }

    // Cleanup when leaving admin page
    cleanup() {
        this.stopAutoRefresh();
    }
}

// Make available globally
window.AdminModule = AdminModule;

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AdminModule;
}