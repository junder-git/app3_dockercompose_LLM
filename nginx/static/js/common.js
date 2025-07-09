// nginx/static/js/common.js - Enhanced with error handling and formatting

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

  // HTML escaping function
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

  // Basic markdown formatting
  const formatMarkdown = (text) => {
    if (!text) return '';
    
    // Escape HTML first
    let formatted = escapeHtml(text);
    
    // Basic markdown conversions
    // Bold
    formatted = formatted.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
    // Italic
    formatted = formatted.replace(/\*(.*?)\*/g, '<em>$1</em>');
    // Code blocks
    formatted = formatted.replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
    // Inline code
    formatted = formatted.replace(/`(.*?)`/g, '<code>$1</code>');
    // Line breaks
    formatted = formatted.replace(/\n/g, '<br>');
    
    return formatted;
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
    alertDiv.innerHTML = `<i class="bi ${icon}"></i> ${escapeHtml(msg)}<button type="button" class="btn-close" data-bs-dismiss="alert"></button>`;

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
    // Clear URL token
    const url = new URL(window.location);
    url.searchParams.delete('token');
    window.history.replaceState({}, '', url);
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
    if (!token) {
      console.log('No auth token found');
      return false;
    }

    // Check token expiry before making request
    if (isTokenExpired(token)) {
      console.log('Token expired');
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
        // Add timeout
        signal: AbortSignal.timeout(10000)
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
      // Don't clear token on network errors, just return false
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
        body: JSON.stringify({ username, password }),
        // Add timeout
        signal: AbortSignal.timeout(10000)
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
      let errorMessage = 'Network error';
      if (error.name === 'TimeoutError') {
        errorMessage = 'Request timeout - please try again';
      } else if (error.message) {
        errorMessage = error.message;
      }
      return { success: false, error: errorMessage };
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
        // Add timeout
        signal: AbortSignal.timeout(10000)
      });
      
      return res.json();
    } catch (error) {
      console.error('Register error:', error);
      let errorMessage = 'Network error';
      if (error.name === 'TimeoutError') {
        errorMessage = 'Request timeout - please try again';
      } else if (error.message) {
        errorMessage = error.message;
      }
      return { success: false, error: errorMessage };
    }
  };

  // Enhanced network request with retry logic
  const makeRequest = async (url, options = {}, retries = 3) => {
    for (let i = 0; i < retries; i++) {
      try {
        const response = await fetch(url, {
          ...options,
          signal: AbortSignal.timeout(options.timeout || 15000)
        });
        return response;
      } catch (error) {
        if (i === retries - 1) throw error;
        if (error.name === 'AbortError') throw error;
        
        // Wait before retry
        await new Promise(resolve => setTimeout(resolve, 1000 * (i + 1)));
      }
    }
  };

  // Initialize auth for server-side on page load
  const initAuth = () => {
    const token = getAuthToken();
    if (token && !isTokenExpired(token)) {
      setAuthForServerSide(token);
    }
  };

  // Health check function
  const checkHealth = async () => {
    try {
      const response = await fetch('/health', {
        method: 'GET',
        signal: AbortSignal.timeout(5000)
      });
      return response.ok;
    } catch (error) {
      console.error('Health check failed:', error);
      return false;
    }
  };

  // Public API
  return {
    // DOM helpers
    $, $$, val, text, html, prop, append, scrollTop,
    
    // UI helpers
    showFlashMessage, escapeHtml, formatMarkdown,
    
    // Auth functions
    getAuthToken, setAuthToken, logout, checkAuth, login, register,
    setAuthForServerSide, initAuth, isTokenExpired,
    
    // Network helpers
    makeRequest, checkHealth
  };
})();

// Global exports
window.DevstralCommon = DevstralCommon;
window.logout = DevstralCommon.logout;

// Global error handler
window.addEventListener('error', (event) => {
  console.error('Global error:', event.error);
  if (DevstralCommon.showFlashMessage) {
    DevstralCommon.showFlashMessage('An unexpected error occurred', 'error');
  }
});

// Global unhandled promise rejection handler
window.addEventListener('unhandledrejection', (event) => {
  console.error('Unhandled promise rejection:', event.reason);
  if (DevstralCommon.showFlashMessage) {
    DevstralCommon.showFlashMessage('An unexpected error occurred', 'error');
  }
});