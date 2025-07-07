import database from "./database.js";
import models from "./models.js";

async function handleInit(r) {
    // Check if admin user exists
    var adminUser = await database.getUserByUsername("admin");
    if (adminUser) {
        r.return(200, JSON.stringify({ message: "Admin user already exists" }));
        return;
    }

    // Create default admin user
    var user = new models.User({
        id: Date.now().toString(),
        username: "admin",
        password_hash: "admin", // ❗️ You might want to hash or set a secure default
        is_admin: true,
        is_approved: true,
        created_at: new Date().toISOString()
    });

    var saveResult = await database.saveUser(user.toDict());

    if (saveResult) {
        r.return(200, JSON.stringify({ message: "Admin user created" }));
    } else {
        r.return(500, JSON.stringify({ error: "Failed to create admin user" }));
    }
}

export default { handleInit };
