// nginx/static/js/common.js - Shared functions for all pages

const DevstralCommon = (() => {
  'use strict';

  // Helper functions
  const $ = (selector) => document.querySelector(selector);
  const $$ = (selector) => document.querySelectorAll(selector);

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

  const append = (parent, child) => {
    if (typeof parent === 'string') parent = $(parent);
    if (typeof child === 'string') {
      const temp = document.createElement('div');
      temp.innerHTML = child;
      child = temp.firstChild;
    }
    parent && child && parent.appendChild(child);
  };

  const scrollTop = (el, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return 0;
    if (v !== undefined) { el.scrollTop = v; return el; }
    return el.scrollTop;
  };

  const showFlashMessage = (msg, type = 'info') => {
    const alertClass = {
      success: 'alert-success',
      error: 'alert-danger', 
      warning: 'alert-warning',
      info: 'alert-info'
    }[type] || 'alert-info';

    const icon = {
      success: 'bi-check-circle',
      error: 'bi-exclamation-triangle',
      warning: 'bi-exclamation-triangle',
      info: 'bi-info-circle'
    }[type] || 'bi-info-circle';

    const alertDiv = document.createElement('div');
    alertDiv.className = `alert ${alertClass} alert-dismissible fade show`;
    alertDiv.setAttribute('role', 'alert');
    alertDiv.innerHTML = `<i class="bi ${icon}"></i> ${msg}<button type="button" class="btn-close" data-bs-dismiss="alert"></button>`;

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

  // Authentication functions
  const getAuthToken = () => localStorage.getItem('auth_token') || '';
  const setAuthToken = (t) => t ? localStorage.setItem('auth_token', t) : localStorage.removeItem('auth_token');
  
  const logout = () => { 
    setAuthToken(null);
    // Clear cookie
    document.cookie = `auth_token=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT`;
    window.location.href = '/'; 
  };

  const setAuthForServerSide = (token) => {
    if (token) {
      document.cookie = `auth_token=${token}; path=/; max-age=604800; secure=false; samesite=lax`;
      
      const url = new URL(window.location);
      url.searchParams.set('token', token);
      window.history.replaceState({}, '', url);
    } else {
      document.cookie = `auth_token=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT`;
      
      const url = new URL(window.location);
      url.searchParams.delete('token');
      window.history.replaceState({}, '', url);
    }
  };

  const checkAuth = async () => {
    const token = getAuthToken();
    if (!token) {
      console.log('No auth token found');
      return false;
    }

    try {
      const payload = JSON.parse(atob(token));
      if (!payload.exp || payload.exp < Date.now() / 1000) {
        console.log('Token expired');
        setAuthToken(null);
        return false;
      }
    } catch (e) {
      console.log('Invalid token format');
      setAuthToken(null);
      return false;
    }

    try {
      const res = await fetch('/api/auth/verify', { 
        headers: { 
          Authorization: `Bearer ${token}`,
          'Accept': 'application/json'
        } 
      });
      
      if (res.ok) {
        const data = await res.json();
        console.log('Auth check successful:', data.user);
        return data.user;
      } else {
        console.log('Auth check failed:', res.status);
        if (res.status === 401) {
          setAuthToken(null);
        }
        return false;
      }
    } catch (e) {
      console.error('Auth check error:', e);
      return false;
    }
  };

  const login = async (username, password) => {
    if (!username || !password) {
      return { success: false, error: 'Username and password are required' };
    }

    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ username, password })
      });
      
      const data = await res.json();
      
      if (data.success && data.token) {
        setAuthToken(data.token);
        setAuthForServerSide(data.token);
        return { success: true, user: data.user };
      }
      return { success: false, error: data.error || 'Login failed' };
    } catch (error) {
      console.error('Login error:', error);
      return { success: false, error: 'Network error: ' + error.message };
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
        body: JSON.stringify({ username, password })
      });
      
      return res.json();
    } catch (error) {
      console.error('Register error:', error);
      return { success: false, error: 'Network error: ' + error.message };
    }
  };

  // Initialize auth for server-side on page load
  const initAuth = () => {
    const token = getAuthToken();
    if (token) {
      setAuthForServerSide(token);
    }
  };

  // Public API
  return {
    // DOM helpers
    $, $$, val, text, html, prop, append, scrollTop,
    
    // UI helpers
    showFlashMessage,
    
    // Auth functions
    getAuthToken, setAuthToken, logout, checkAuth, login, register,
    setAuthForServerSide, initAuth
  };
})();

// Global exports
window.DevstralCommon = DevstralCommon;
window.logout = DevstralCommon.logout;