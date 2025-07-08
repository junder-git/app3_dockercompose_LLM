// nginx/njs/utils.js - Fixed to properly use models
import database from "./database.js";
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
        // Check Redis connection
        var redisRes = await ngx.fetch("/redis-internal/PING");
        if (!redisRes.ok) {
            r.return(503, JSON.stringify({ 
                status: "unhealthy", 
                error: "Redis connection failed" 
            }));
            return;
        }

        // Check if system is initialized
        var adminExists = await database.getUserByUsername("admin");
        
        r.return(200, JSON.stringify({
            status: "healthy",
            timestamp: new Date().toISOString(),
            services: {
                redis: "connected",
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
        
        r.log('=== SYSTEM INITIALIZATION START ===');
        
        // Test Redis connection first
        var pingRes = await ngx.fetch("/redis-internal/PING");
        if (!pingRes.ok) {
            r.log('Redis connection failed during init');
            r.return(500, JSON.stringify({
                success: false,
                error: "Redis connection failed",
                results: ["Redis ping failed"]
            }));
            return;
        }
        
        var pingResponse = await pingRes.text();
        r.log('Redis PING response: ' + pingResponse);
        results.push("Redis connection verified: " + pingResponse);
        
        // Get admin credentials from environment or use defaults
        var adminUsername = "admin";  // Default fallback
        var adminPassword = "admin";  // Default fallback  
        var adminUserId = "admin_" + Date.now();    // Unique ID
        
        r.log('Checking for existing admin user: ' + adminUsername);
        var existingAdmin = await database.getUserByUsername(adminUsername);
        
        if (!existingAdmin) {
            r.log('Creating new admin user');
            
            // Create admin user using the User model
            var adminUser = new models.User({
                id: adminUserId,
                username: adminUsername,
                password_hash: adminPassword, // In production, hash this properly
                is_admin: true,
                is_approved: true,
                created_at: new Date().toISOString()
            });
            
            r.log('Admin user model created: ' + JSON.stringify(adminUser.toDict()));

            var saved = await database.saveUser(adminUser.toDict());
            if (saved) {
                results.push("Admin user '" + adminUsername + "' created successfully");
                r.log('Admin user saved successfully');
                
                // Verify the user was created by reading it back
                var verifyUser = await database.getUserByUsername(adminUsername);
                if (verifyUser) {
                    results.push("Admin user verification successful");
                    r.log('Admin user verification successful: ' + JSON.stringify(verifyUser));
                } else {
                    results.push("Warning: Admin user creation verification failed");
                    r.log('Warning: Could not verify admin user creation');
                }
            } else {
                results.push("Failed to create admin user '" + adminUsername + "'");
                r.log('Failed to save admin user to database');
            }
        } else {
            results.push("Admin user '" + adminUsername + "' already exists");
            r.log('Admin user already exists: ' + JSON.stringify(existingAdmin));
        }

        // Initialize any other required data here
        // For example, default settings, system configuration, etc.

        var success = results.some(function(result) {
            return result.indexOf('successfully') > -1 || result.indexOf('already exists') > -1;
        });

        r.return(200, JSON.stringify({
            success: success,
            message: "System initialization completed",
            results: results,
            timestamp: new Date().toISOString()
        }));

    } catch (e) {
        r.log('Initialization error: ' + e.message);
        r.log('Error stack: ' + (e.stack || 'no stack'));
        r.return(500, JSON.stringify({ 
            success: false,
            error: "System initialization failed",
            details: e.message,
            timestamp: new Date().toISOString()
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