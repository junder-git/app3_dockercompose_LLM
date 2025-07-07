// nginx/njs/admin.js - Complete admin functionality
import database from "./database.js";
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

async function handleGetUsers(r) {
    try {
        const users = await database.getAllUsers();
        
        // Format users for admin view
        const formattedUsers = users.map(function(user) {
            return {
                id: user.id,
                username: user.username,
                is_admin: user.is_admin === 'true' || user.is_admin === true,
                is_approved: user.is_approved === 'true' || user.is_approved === true,
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

        const success = await database.approveUser(userId);
        if (!success) {
            r.return(404, JSON.stringify({ error: "User not found" }));
            return;
        }

        r.return(200, JSON.stringify({ 
            success: true,
            message: "User approved successfully" 
        }));

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

        const success = await database.rejectUser(userId);
        if (!success) {
            r.return(404, JSON.stringify({ error: "User not found" }));
            return;
        }

        r.return(200, JSON.stringify({ 
            success: true,
            message: "User rejected and deleted successfully" 
        }));

    } catch (e) {
        r.log('Reject user error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to reject user" }));
    }
}

async function handleGetUserDetail(r, userId) {
    try {
        const user = await database.getUserById(userId);
        if (!user) {
            r.return(404, JSON.stringify({ error: "User not found" }));
            return;
        }

        // Get user's chat history
        const chats = await database.getUserChats(userId);

        const userDetail = {
            id: user.id,
            username: user.username,
            is_admin: user.is_admin === 'true' || user.is_admin === true,
            is_approved: user.is_approved === 'true' || user.is_approved === true,
            created_at: user.created_at,
            chat_count: chats.length,
            recent_chats: chats.slice(0, 10) // Last 10 chats
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
        const users = await database.getAllUsers();
        
        const stats = {
            total_users: users.length,
            approved_users: users.filter(function(u) { 
                return u.is_approved === 'true' || u.is_approved === true; 
            }).length,
            pending_users: users.filter(function(u) { 
                return u.is_approved === 'false' || u.is_approved === false; 
            }).length,
            admin_users: users.filter(function(u) { 
                return u.is_admin === 'true' || u.is_admin === true; 
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

export default { 
    handleAdminRequest,
    handleGetUsers,
    handleApproveUser, 
    handleRejectUser,
    handleGetUserDetail,
    handleGetStats
};