import database from './database.js';

export async function handleInitEndpoint(r) {
  try {
    // Example initialization logic
    const adminExists = await database.getUserByUsername('admin');

    if (!adminExists) {
      const hash = await database.hashPassword('adminpassword');
      const adminUser = {
        id: Date.now().toString(),
        username: 'admin',
        password_hash: hash,
        is_admin: true
      };

      await database.saveUser(adminUser);
    }

    r.return(200, JSON.stringify({ message: 'Initialization completed' }));
  } catch (e) {
    r.error(`Init error: ${e}`);
    r.return(500, JSON.stringify({ error: 'Initialization failed' }));
  }
}
