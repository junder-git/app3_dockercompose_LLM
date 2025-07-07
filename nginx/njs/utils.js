// nginx/njs/utils.js - Updated with initialization logic
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
        const redisRes = await ngx.fetch("/redis-internal/ping");
        if (!redisRes.ok) {
            r.return(503, JSON.stringify({ 
                status: "unhealthy", 
                error: "Redis connection failed" 
            }));
            return;
        }

        // Check if system is initialized
        const adminExists = await database.getUserByUsername(process.env.ADMIN_USERNAME || "admin");
        
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
        const results = [];
        
        // Initialize admin user if it doesn't exist
        const adminUsername = process.env.ADMIN_USERNAME || "admin";
        const adminPassword = process.env.ADMIN_PASSWORD || "admin";
        const adminUserId = process.env.ADMIN_USER_ID || "admin";
        
        const existingAdmin = await database.getUserByUsername(adminUsername);
        
        if (!existingAdmin) {
            const adminUser = new models.User({
                id: adminUserId,
                username: adminUsername,
                password_hash: adminPassword, // In production, hash this properly
                is_admin: true,
                is_approved: true,
                created_at: new Date().toISOString()
            });

            const saved = await database.saveUser(adminUser.toDict());
            if (saved) {
                results.push(`Admin user '${adminUsername}' created successfully`);
            } else {
                results.push(`Failed to create admin user '${adminUsername}'`);
            }
        } else {
            results.push(`Admin user '${adminUsername}' already exists`);
        }

        // Initialize any other required data here
        // For example, default settings, system configuration, etc.

        r.return(200, JSON.stringify({
            success: true,
            message: "System initialization completed",
            results: results,
            timestamp: new Date().toISOString()
        }));

    } catch (e) {
        r.log(`Initialization error: ${e.message}`);
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