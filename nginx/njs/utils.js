// nginx/njs/utils.js - Removed database dependency
import models from "./models.js";

function sanitizeHtml(text) {
    if (!text) return "";
    return text.replace(/&/g, "&amp;")
               .replace(/</g, "&lt;")
               .replace(/>/g, "&gt;")
               .replace(/"/g, "&quot;")
               .replace(/'/g, "&#x27;");
}

function validateUsername(username) {
    if (!username) return [false, "Username is required"];
    if (username.length < 3) return [false, "Username too short"];
    if (username.length > 32) return [false, "Username too long"];
    if (!/^[a-zA-Z0-9_-]+$/.test(username)) return [false, "Invalid characters"];
    return [true, ""];
}

function validatePassword(password) {
    if (!password) return [false, "Password is required"];
    if (password.length < 6) return [false, "Password too short"];
    if (password.length > 64) return [false, "Password too long"];
    return [true, ""];
}

async function healthCheck(r) {
    try {
        // Check Redis connection via internal endpoint
        var redisRes = await ngx.fetch("/redis/get?key=health_check", {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        var redisStatus = redisRes.ok ? "connected" : "failed";

        // Check if admin user exists
        var adminRes = await ngx.fetch("/redis/hgetall?key=user:admin", {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        var adminExists = false;
        if (adminRes.ok) {
            var adminData = await adminRes.json();
            adminExists = adminData.success && adminData.data.username;
        }
        
        var status = redisStatus === "connected" ? "healthy" : "unhealthy";
        var statusCode = status === "healthy" ? 200 : 503;
        
        r.return(statusCode, JSON.stringify({
            status: status,
            timestamp: new Date().toISOString(),
            services: {
                redis: redisStatus,
                admin_user: adminExists ? "exists" : "missing"
            }
        }));
    } catch (e) {
        r.return(503, JSON.stringify({ 
            status: "unhealthy", 
            error: e.message 
        }));
    }
}

async function handleInit(r) {
    try {
        var results = [];
        
        var adminUsername = "admin";
        var adminPassword = "admin";
        var adminUserId = "admin";
        
        // Check if admin user exists
        var existingAdminRes = await ngx.fetch("/redis/hgetall?key=user:" + adminUsername, {
            headers: { 'Authorization': 'Bearer internal' }
        });
        
        var adminExists = false;
        if (existingAdminRes.ok) {
            var adminData = await existingAdminRes.json();
            adminExists = adminData.success && adminData.data.username;
        }
        
        if (!adminExists) {
            // Create admin user using Redis direct access
            var adminUser = new models.User({
                id: adminUserId,
                username: adminUsername,
                password_hash: adminPassword,
                is_admin: true,
                is_approved: true,
                created_at: new Date().toISOString()
            });

            var userDict = adminUser.toDict();
            
            // Save admin user to Redis
            var fields = [
                ['id', userDict.id],
                ['username', userDict.username],
                ['password_hash', userDict.password_hash],
                ['is_admin', 'true'],
                ['is_approved', 'true'],
                ['created_at', userDict.created_at]
            ];

            var saved = true;
            for (var i = 0; i < fields.length; i++) {
                var fieldRes = await ngx.fetch("/redis/hset", {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer internal'
                    },
                    body: JSON.stringify({
                        key: "user:" + adminUsername,
                        field: fields[i][0],
                        value: fields[i][1]
                    })
                });
                
                if (!fieldRes.ok) {
                    saved = false;
                    break;
                }
            }
            
            if (saved) {
                results.push("Admin user '" + adminUsername + "' created successfully");
            } else {
                results.push("Failed to create admin user '" + adminUsername + "'");
            }
        } else {
            results.push("Admin user '" + adminUsername + "' already exists");
        }

        r.return(200, JSON.stringify({
            success: true,
            message: "System initialization completed",
            results: results,
            timestamp: new Date().toISOString()
        }));

    } catch (e) {
        r.log('Initialization error: ' + e.message);
        r.return(500, JSON.stringify({ 
            success: false,
            error: "System initialization failed",
            details: e.message 
        }));
    }
}

export default { 
    sanitizeHtml, 
    validateUsername, 
    validatePassword,
    healthCheck,
    handleInit
};