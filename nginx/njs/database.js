import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

const users = {}; // Example in-memory storage
const tokens = {}; // Example in-memory token map

export async function getUserByUsername(username) {
  return users[username] || null;
}

export async function verifyPassword(inputPassword, hash) {
  return bcrypt.compare(inputPassword, hash);
}

export async function hashPassword(password) {
  return bcrypt.hash(password, 10);
}

export async function saveUser(user) {
  users[user.username] = user;
  return true;
}

export async function generateToken(user) {
  const token = jwt.sign({ id: user.id, username: user.username, is_admin: user.is_admin }, 'secret', { expiresIn: '1h' });
  tokens[token] = user;
  return token;
}

export async function getUserByToken(token) {
  try {
    const decoded = jwt.verify(token, 'secret');
    return users[decoded.username] || null;
  } catch (e) {
    return null;
  }
}
