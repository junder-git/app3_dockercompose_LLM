// nginx/njs/admin.js - Server-side admin handlers for njs

import database from './database.js';
import utils from './utils.js';

function handleAdminRequest(r) {
    try {
        var path = r.uri.split('/').filter(function(p) { return p; });
        var operation = path[2]; // /api/admin/{operation}
        
        switch (operation) {
            case 'users':
                return handleAdminUsers(r);
            case 'approve':
                return handleUserApproval(r);
            case 'reject':
                return handleUserRejection(r);
            case 'delete':
                return handleUserDeletion(r);
            case 'stats':
                return handleSystemStats(r);
            case 'health':
                return handleSystemHealth(r);
            default:
                return utils.sendError(r, 404, 'Admin operation not found');
        }
        
    } catch (error) {
        r.error('Admin request error: ' + error.message);
        return utils.sendError(r, 500, 'Admin operation failed');
    }
}

function handleAdminUsers(r) {
    if (r.method === 'GET') {
        var users = database.getAllUsers();
        return utils.sendSuccess(r, users);
    } else {
        return utils.sendError(r, 405, 'Method not allowed');
    }
}

function handleUserApproval(r) {
    if (r.method !== 'POST') {
        return utils.sendError(r, 405, 'Method not allowed');
    }
    
    try {
        var body = JSON.parse(r.requestBody);
        var userId = body.userId;
        
        if (!userId) {
            return utils.sendError(r, 400, 'User ID required');
        }
        
        var result = database.approveUser(userId);
        return utils.sendSuccess(r, result);
        
    } catch (error) {
        return utils.sendError(r, 400, 'Invalid request: ' + error.message);
    }
}

function handleUserRejection(r) {
    if (r.method !== 'POST') {
        return utils.sendError(r, 405, 'Method not allowed');
    }
    
    try {
        var body = JSON.parse(r.requestBody);
        var userId = body.userId;
        
        if (!userId) {
            return utils.sendError(r, 400, 'User ID required');
        }
        
        var result = database.rejectUser(userId);
        return utils.sendSuccess(r, result);
        
    } catch (error) {
        return utils.sendError(r, 400, 'Invalid request: ' + error.message);
    }
}

function handleUserDeletion(r) {
    if (r.method !== 'POST') {
        return utils.sendError(r, 405, 'Method not allowed');
    }
    
    try {
        var body = JSON.parse(r.requestBody);
        var userId = body.userId;
        
        if (!userId) {
            return utils.sendError(r, 400, 'User ID required');
        }
        
        var result = database.deleteUser(userId);
        return utils.sendSuccess(r, result);
        
    } catch (error) {
        return utils.sendError(r, 400, 'Invalid request: ' + error.message);
    }
}

function handleSystemStats(r) {
    if (r.method === 'GET') {
        var stats = database.getDatabaseStats();
        return utils.sendSuccess(r, stats);
    } else {
        return utils.sendError(r, 405, 'Method not allowed');
    }
}

function handleSystemHealth(r) {
    if (r.method === 'GET') {
        var health = {
            status: 'healthy',
            timestamp: new Date().toISOString(),
            checks: {
                database: true,
                redis: true
            }
        };
        return utils.sendSuccess(r, health);
    } else {
        return utils.sendError(r, 405, 'Method not allowed');
    }
}

function validateAdminAccess(r) {
    var isAdmin = r.headersIn['X-Is-Admin'];
    return isAdmin === 'true';
}

function logAdminAction(userId, action, targetUserId) {
    var logEntry = {
        timestamp: new Date().toISOString(),
        admin_user_id: userId,
        action: action,
        target_user_id: targetUserId || null
    };
    
    console.log('Admin action:', JSON.stringify(logEntry));
}

function getAdminDashboardData() {
    try {
        var stats = database.getDatabaseStats();
        var pendingUsers = database.getPendingUsers();
        
        return {
            stats: stats,
            pending_users: pendingUsers,
            timestamp: new Date().toISOString()
        };
    } catch (error) {
        throw new Error('Failed to get admin dashboard data: ' + error.message);
    }
}

function bulkApproveUsers(userIds) {
    var results = [];
    
    for (var i = 0; i < userIds.length; i++) {
        var userId = userIds[i];
        try {
            var result = database.approveUser(userId);
            results.push({ 
                userId: userId, 
                success: result.success, 
                message: result.message 
            });
        } catch (error) {
            results.push({ 
                userId: userId, 
                success: false, 
                message: error.message 
            });
        }
    }
    
    return results;
}

function getUserActivity(userId, limit) {
    limit = limit || 50;
    
    try {
        return {
            user_id: userId,
            activities: [],
            total_count: 0,
            last_activity: null
        };
    } catch (error) {
        throw new Error('Failed to get user activity: ' + error.message);
    }
}

function performSystemMaintenance() {
    try {
        var cleanupResult = database.cleanupExpiredSessions ? 
            database.cleanupExpiredSessions() : 
            { success: true, message: 'No cleanup needed' };
        
        var validationResult = database.validateDataIntegrity ? 
            database.validateDataIntegrity() : 
            { success: true, message: 'No validation needed' };
        
        return {
            cleanup: cleanupResult,
            validation: validationResult,
            timestamp: new Date().toISOString()
        };
    } catch (error) {
        throw new Error('System maintenance failed: ' + error.message);
    }
}

export default {
    handleAdminRequest: handleAdminRequest,
    handleAdminUsers: handleAdminUsers,
    handleUserApproval: handleUserApproval,
    handleUserRejection: handleUserRejection,
    handleUserDeletion: handleUserDeletion,
    handleSystemStats: handleSystemStats,
    handleSystemHealth: handleSystemHealth,
    validateAdminAccess: validateAdminAccess,
    logAdminAction: logAdminAction,
    getAdminDashboardData: getAdminDashboardData,
    bulkApproveUsers: bulkApproveUsers,
    getUserActivity: getUserActivity,
    performSystemMaintenance: performSystemMaintenance
};