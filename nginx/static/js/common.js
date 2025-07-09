// nginx/static/js/common.js - Core functions only

const DevstralCommon = (() => {
  'use strict';

  // Helper functions
  const $ = (selector) => document.querySelector(selector);
  const val = (el, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return '';
    if (v !== undefined) { el.value = v; return el; }
    return el.value || '';
  };

  const text = (el, t) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return '';
    if (t !== undefined) { el.textContent = t; return el; }
    return el.textContent || '';
  };

  const html = (el, h) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return '';
    if (h !== undefined) { el.innerHTML = h; return el; }
    return el.innerHTML || '';
  };

  const prop = (el, p, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return;
    if (v !== undefined) { el[p] = v; return el; }
    return el[p];
  };

  // HTML escaping
  const escapeHtml = (text) => {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, (m) => map[m]);
  };

  // Only show error flash messages
  const showFlashMessage = (msg, type = 'error') => {
    if (type !== 'error') return; // Only show errors
    
    const alertDiv = document.createElement('div');
    alertDiv.className = 'alert alert-danger alert-dismissible fade show';
    alertDiv.setAttribute('role', 'alert');
    alertDiv.innerHTML = `<i class="bi bi-exclamation-triangle"></i> ${escapeHtml(msg)}<button type="button" class="btn-close" data-bs-dismiss="alert"></button>`;

    const container = $('#flash-messages');
    if (container) {
      container.appendChild(alertDiv);
      setTimeout(() => {
        if (alertDiv.parentNode) {
          alertDiv.parentNode.removeChild(alertDiv);
        }
      }, 5000);
    }
  };

  // Auth functions
  const getAuthToken = () => localStorage.getItem('auth_token') || '';
  const setAuthToken = (t) => t ? localStorage.setItem('auth_token', t) : localStorage.removeItem('auth_token');
  
  const logout = () => { 
    setAuthToken(null);
    document.cookie = `auth_token=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT`;
    window.location.href = '/'; 
  };

  const isTokenExpired = (token) => {
    try {
      const payload = JSON.parse(atob(token));
      return !payload.exp || payload.exp < Date.now() / 1000;
    } catch (e) {
      return true;
    }
  };

  const checkAuth = async () => {
    const token = getAuthToken();
    if (!token || isTokenExpired(token)) {
      setAuthToken(null);
      return false;
    }

    try {
      const res = await fetch('/api/auth/verify', { 
        method: 'GET',
        headers: { 
          'Authorization': `Bearer ${token}`,
          'Accept': 'application/json'
        },
        signal: AbortSignal.timeout(10000)
      });
      
      if (res.ok) {
        const data = await res.json();
        return data.user;
      } else {
        if (res.status === 401) {
          setAuthToken(null);
        }
        return false;
      }
    } catch (e) {
      return false;
    }
  };

  const login = async (username, password) => {
    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ username, password }),
        signal: AbortSignal.timeout(10000)
      });
      
      const data = await res.json();
      
      if (data.success && data.token) {
        setAuthToken(data.token);
        return { success: true, user: data.user };
      }
      return { success: false, error: data.error || 'Login failed' };
    } catch (error) {
      return { success: false, error: 'Network error' };
    }
  };

  const register = async (username, password) => {
    try {
      const res = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ username, password }),
        signal: AbortSignal.timeout(10000)
      });
      
      return res.json();
    } catch (error) {
      return { success: false, error: 'Network error' };
    }
  };

  // Public API
  return {
    $, val, text, html, prop,
    showFlashMessage, escapeHtml,
    getAuthToken, setAuthToken, logout, checkAuth, login, register,
    isTokenExpired
  };
})();

window.DevstralCommon = DevstralCommon;
window.logout = DevstralCommon.logout;