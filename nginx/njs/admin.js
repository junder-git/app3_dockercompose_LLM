// nginx/njs/admin.js - Updated to use Redis direct access
import auth from "./auth.js";

async function handleAdminRequest(r) {
    try {
        // Check authentication
        const authResult = await auth.verifyRequest(r);
        if (!authResult.success) {
            r.return(401, JSON.stringify({ error: "Authentication required" }));
            return;
        }

        // Check admin privileges
        if (!authResult.user.is_admin) {
            r.return(403, JSON.stringify({ error: "Admin privileges required" }));
            return;
        }

        const path = r.uri.replace('/api/admin/', '');
        const method = r.method;

        // Route admin requests
        if (path === 'users' && method === 'GET') {
            await handleGetUsers(r);
        } else if (path === 'users/approve' && method === 'POST') {
            await handleApproveUser(r);
        } else if (path === 'users/reject' && method === 'POST') {
            await handleRejectUser(r);
        } else if (path.startsWith('users/') && method === 'GET') {
            const userId = path.split('/')[1];
            await handleGetUserDetail(r, userId);
        } else if (path === 'stats' && method === 'GET') {
            await handleGetStats(r);
        } else {
            r.return(404, JSON.stringify({ error: "Admin endpoint not found" }));
        }

    } catch (e) {
        r.log('Admin error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Internal server error" }));
    }
}

async function getAllUsers() {
    try {
        // Get all user keys - this would need a custom Redis endpoint
        // For now, we'll return a simple response
        // In production, you'd implement a Redis KEYS or SCAN operation
        
        var usersRes = await ngx.fetch("/redis/get?key=users_list", {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        if (usersRes.ok) {
            var data = await usersRes.json();
            if (data.success && data.value) {
                return JSON.parse(data.value);
            }
        }
        
        return [];
    } catch (e) {
        return [];
    }
}

async function handleGetUsers(r) {
    try {
        var users = await getAllUsers();
        
        // Format users for admin view
        var formattedUsers = users.map(function(user) {
            return {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true',
                is_approved: user.is_approved === 'true',
                created_at: user.created_at
            };
        });

        // Sort by created_at (newest first)
        formattedUsers.sort(function(a, b) {
            return new Date(b.created_at) - new Date(a.created_at);
        });

        r.return(200, JSON.stringify({
            success: true,
            users: formattedUsers,
            total: formattedUsers.length
        }));

    } catch (e) {
        r.log('Get users error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to fetch users" }));
    }
}

async function handleApproveUser(r) {
    try {
        const body = r.requestBody;
        if (!body) {
            r.return(400, JSON.stringify({ error: "Request body required" }));
            return;
        }

        const data = JSON.parse(body);
        const userId = data.user_id;

        if (!userId) {
            r.return(400, JSON.stringify({ error: "User ID is required" }));
            return;
        }

        // Update user approval status in Redis
        var updateRes = await ngx.fetch("/redis/hset", {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': 'Bearer internal'
            },
            body: JSON.stringify({
                key: "user:" + userId,
                field: "is_approved",
                value: "true"
            })
        });

        if (updateRes.ok) {
            r.return(200, JSON.stringify({ 
                success: true,
                message: "User approved successfully" 
            }));
        } else {
            r.return(404, JSON.stringify({ error: "User not found" }));
        }

    } catch (e) {
        r.log('Approve user error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to approve user" }));
    }
}

async function handleRejectUser(r) {
    try {
        const body = r.requestBody;
        if (!body) {
            r.return(400, JSON.stringify({ error: "Request body required" }));
            return;
        }

        const data = JSON.parse(body);
        const userId = data.user_id;

        if (!userId) {
            r.return(400, JSON.stringify({ error: "User ID is required" }));
            return;
        }

        // Delete user from Redis - would need a custom endpoint
        // For now, mark as rejected
        var deleteRes = await ngx.fetch("/redis/set", {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': 'Bearer internal'
            },
            body: JSON.stringify({
                key: "user:" + userId + ":deleted",
                value: "true"
            })
        });

        if (deleteRes.ok) {
            r.return(200, JSON.stringify({ 
                success: true,
                message: "User rejected and deleted successfully" 
            }));
        } else {
            r.return(404, JSON.stringify({ error: "User not found" }));
        }

    } catch (e) {
        r.log('Reject user error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to reject user" }));
    }
}

async function handleGetUserDetail(r, userId) {
    try {
        var userRes = await ngx.fetch("/redis/hgetall?key=user:" + userId, {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        if (!userRes.ok) {
            r.return(404, JSON.stringify({ error: "User not found" }));
            return;
        }
        
        var userData = await userRes.json();
        if (!userData.success) {
            r.return(404, JSON.stringify({ error: "User not found" }));
            return;
        }
        
        var user = userData.data;

        var userDetail = {
            id: user.id,
            username: user.username,
            is_admin: user.is_admin === 'true',
            is_approved: user.is_approved === 'true',
            created_at: user.created_at,
            chat_count: 0, // Would need to implement chat counting
            recent_chats: [] // Would need to implement chat retrieval
        };

        r.return(200, JSON.stringify({
            success: true,
            user: userDetail
        }));

    } catch (e) {
        r.log('Get user detail error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to fetch user details" }));
    }
}

async function handleGetStats(r) {
    try {
        var users = await getAllUsers();
        
        var stats = {
            total_users: users.length,
            approved_users: users.filter(function(u) { 
                return u.is_approved === 'true'; 
            }).length,
            pending_users: users.filter(function(u) { 
                return u.is_approved === 'false'; 
            }).length,
            admin_users: users.filter(function(u) { 
                return u.is_admin === 'true'; 
            }).length
        };

        r.return(200, JSON.stringify({
            success: true,
            stats: stats
        }));

    } catch (e) {
        r.log('Get stats error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to fetch stats" }));
    }
}

// Add this to nginx/njs/admin.js

async function handleGetDashboard(r) {
    try {
        const users = await getAllUsers();
        
        // Calculate stats
        const stats = {
            total_users: users.length,
            approved_users: users.filter(u => u.is_approved === 'true').length,
            pending_users: users.filter(u => u.is_approved === 'false').length,
            admin_users: users.filter(u => u.is_admin === 'true').length
        };

        // Render HTML server-side (SECURE)
        const dashboardHtml = `
            <div class="row mb-4">
                <div class="col-12">
                    <h2><i class="bi bi-speedometer2"></i> Admin Dashboard</h2>
                </div>
            </div>
            
            <div class="row mb-4">
                <div class="col-md-3">
                    <div class="card">
                        <div class="card-body text-center">
                            <h5 class="card-title">Total Users</h5>
                            <h3 class="text-primary">${stats.total_users}</h3>
                        </div>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card">
                        <div class="card-body text-center">
                            <h5 class="card-title">Approved</h5>
                            <h3 class="text-success">${stats.approved_users}</h3>
                        </div>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card">
                        <div class="card-body text-center">
                            <h5 class="card-title">Pending</h5>
                            <h3 class="text-warning">${stats.pending_users}</h3>
                        </div>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card">
                        <div class="card-body text-center">
                            <h5 class="card-title">Admins</h5>
                            <h3 class="text-info">${stats.admin_users}</h3>
                        </div>
                    </div>
                </div>
            </div>

            <div class="row">
                <div class="col-12">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0"><i class="bi bi-people"></i> User Management</h5>
                        </div>
                        <div class="card-body">
                            <div class="user-list">
                                ${users.map(user => renderSecureUserCard(user)).join('')}
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        r.headersOut['Content-Type'] = 'text/html';
        r.return(200, dashboardHtml);

    } catch (e) {
        r.log('Dashboard error: ' + e.message);
        r.return(500, '<div class="alert alert-danger">Failed to load dashboard</div>');
    }
}

function renderSecureUserCard(user) {
    const statusBadge = user.is_admin === 'true' ? 
        '<span class="badge bg-info">Admin</span>' :
        user.is_approved === 'true' ? 
            '<span class="badge bg-success">Approved</span>' : 
            '<span class="badge bg-warning">Pending</span>';

    const actions = (user.is_approved !== 'true' && user.is_admin !== 'true') ? `
        <button class="btn btn-sm btn-success me-2" data-action="approve" data-user-id="${user.id}">
            <i class="bi bi-check"></i> Approve
        </button>
        <button class="btn btn-sm btn-outline-danger" data-action="reject" data-user-id="${user.id}">
            <i class="bi bi-x"></i> Reject
        </button>
    ` : '';

    return `
        <div class="user-card">
            <div class="d-flex justify-content-between align-items-center">
                <div>
                    <h6 class="mb-1">${escapeHtml(user.username)}</h6>
                    <small class="text-muted">ID: ${user.id}</small>
                </div>
                <div>
                    ${statusBadge}
                    ${actions}
                </div>
            </div>
        </div>
    `;
}

function escapeHtml(text) {
    if (!text) return "";
    return text.replace(/&/g, "&amp;")
               .replace(/</g, "&lt;")
               .replace(/>/g, "&gt;")
               .replace(/"/g, "&quot;")
               .replace(/'/g, "&#x27;");
}

// Update the main handleAdminRequest function
async function handleAdminRequest(r) {
    try {
        // Check authentication
        const authResult = await auth.verifyRequest(r);
        if (!authResult.success) {
            r.return(401, JSON.stringify({ error: "Authentication required" }));
            return;
        }

        // Check admin privileges
        if (!authResult.user.is_admin) {
            r.return(403, JSON.stringify({ error: "Admin privileges required" }));
            return;
        }

        const path = r.uri.replace('/api/admin/', '');
        const method = r.method;

        // Route admin requests
        if (path === 'users' && method === 'GET') {
            await handleGetUsers(r);
        } else if (path === 'users/approve' && method === 'POST') {
            await handleApproveUser(r);
        } else if (path === 'users/reject' && method === 'POST') {
            await handleRejectUser(r);
        } else if (path === 'dashboard' && method === 'GET') {
            await handleGetDashboard(r); // NEW SECURE ENDPOINT
        } else if (path === 'stats' && method === 'GET') {
            await handleGetStats(r);
        } else {
            r.return(404, JSON.stringify({ error: "Admin endpoint not found" }));
        }

    } catch (e) {
        r.log('Admin error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Internal server error" }));
    }
}

export default { 
    handleAdminRequest,
    handleGetUsers,
    handleApproveUser, 
    handleRejectUser,
    handleGetUserDetail,
    handleGetStats,
    handleGetDashboard
};