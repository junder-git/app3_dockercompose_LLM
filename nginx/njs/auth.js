import database from './database.js';

export async function handleLogin(r) {
  try {
    const body = await r.readBody();
    const { username, password } = JSON.parse(body);

    if (!username || !password) {
      r.return(400, JSON.stringify({ error: 'Missing username or password' }));
      return;
    }

    const user = await database.getUserByUsername(username);
    if (!user) {
      r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
      return;
    }

    const valid = await database.verifyPassword(password, user.password_hash);
    if (!valid) {
      r.return(401, JSON.stringify({ error: 'Invalid credentials' }));
      return;
    }

    const token = await database.generateToken(user);

    r.headersOut['X-Is-Admin'] = user.is_admin ? 'true' : 'false';
    r.return(200, JSON.stringify({ token }));
  } catch (e) {
    r.error(`Login error: ${e}`);
    r.return(500, JSON.stringify({ error: 'Internal server error' }));
  }
}

export async function verifyToken(r) {
  try {
    const token = r.headersIn['Authorization'];
    if (!token) {
      r.return(401);
      return;
    }

    const user = await database.getUserByToken(token);
    if (!user) {
      r.return(401);
      return;
    }

    r.headersOut['X-User-ID'] = user.id;
    r.headersOut['X-Username'] = user.username;
    r.headersOut['X-Is-Admin'] = user.is_admin ? 'true' : 'false';

    r.return(200);
  } catch (e) {
    r.error(`Verify error: ${e}`);
    r.return(500);
  }
}

export async function handleRegister(r) {
  try {
    const body = await r.readBody();
    const { username, password } = JSON.parse(body);

    if (!username || !password) {
      r.return(400, JSON.stringify({ error: 'Missing username or password' }));
      return;
    }

    const existing = await database.getUserByUsername(username);
    if (existing) {
      r.return(409, JSON.stringify({ error: 'User already exists' }));
      return;
    }

    const hash = await database.hashPassword(password);

    const newUser = {
      id: Date.now().toString(),
      username,
      password_hash: hash,
      is_admin: username === 'admin'
    };

    await database.saveUser(newUser);

    r.return(201, JSON.stringify({ message: 'User registered', user: { username: newUser.username } }));
  } catch (e) {
    r.error(`Register error: ${e}`);
    r.return(500, JSON.stringify({ error: 'Internal server error' }));
  }
}

export function handleAdminRequest(r) {
  r.return(200, JSON.stringify({ message: 'Admin endpoint working' }));
}
