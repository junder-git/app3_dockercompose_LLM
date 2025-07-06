V// admin.js - Admin Module

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
            $('#database-stats').html('<p class="text-