// nginx/static/js/client.js - Complete ES6+ Version

const DevstralClient = (() => {
  'use strict';

  // Helper functions
  const $ = (selector) => document.querySelector(selector);
  const $$ = (selector) => document.querySelectorAll(selector);

  const createElement = (tag, className, innerHTML) => {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (innerHTML) el.innerHTML = innerHTML;
    return el;
  };

  const addClass = (el, cls) => el && el.classList.add(cls);
  const removeClass = (el, cls) => el && el.classList.remove(cls);
  const hasClass = (el, cls) => el ? el.classList.contains(cls) : false;
  const on = (el, evt, cb) => {
    if (typeof el === 'string') el = $(el);
    el && el.addEventListener(evt, cb);
  };
  const off = (el, evt, cb) => {
    if (typeof el === 'string') el = $(el);
    el && el.removeEventListener(evt, cb);
  };

  const val = (el, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return '';
    if (v !== undefined) {
      el.value = v;
      return el;
    }
    return el.value || '';
  };

  const text = (el, t) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return '';
    if (t !== undefined) {
      el.textContent = t;
      return el;
    }
    return el.textContent || '';
  };

  const html = (el, h) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return '';
    if (h !== undefined) {
      el.innerHTML = h;
      return el;
    }
    return el.innerHTML || '';
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

  const remove = (el) => {
    if (typeof el === 'string') el = $(el);
    el?.parentNode?.removeChild(el);
  };

  const prop = (el, p, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return;
    if (v !== undefined) {
      el[p] = v;
      return el;
    }
    return el[p];
  };

  const attr = (el, a, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return;
    if (v !== undefined) {
      el.setAttribute(a, v);
      return el;
    }
    return el.getAttribute(a);
  };

  const scrollTop = (el, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return 0;
    if (v !== undefined) {
      el.scrollTop = v;
      return el;
    }
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

    const alertDiv = createElement('div', `alert ${alertClass} alert-dismissible fade show`,
      `<i class="bi ${icon}"></i> ${escapeHtml(msg)}<button type="button" class="btn-close" data-bs-dismiss="alert"></button>`);
    attr(alertDiv, 'role', 'alert');

    const container = $('#flash-messages');
    if (container) {
      append(container, alertDiv);
      setTimeout(() => remove(alertDiv), 5000);
    }
  };

  const escapeHtml = (t) => {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#x27;'
    };
    return String(t).replace(/[&<>"']/g, (m) => map[m]);
  };

  const getAuthToken = () => localStorage.getItem('auth_token') || '';
  const setAuthToken = (t) => t ? localStorage.setItem('auth_token', t) : localStorage.removeItem('auth_token');
  const logout = () => { setAuthToken(null); window.location.href = '/'; };

  const checkAuth = async () => {
    const token = getAuthToken();
    if (!token) return false;

    try {
      const res = await fetch('/api/auth/verify', { 
        headers: { 
          Authorization: `Bearer ${token}`,
          'Accept': 'application/json'
        } 
      });
      if (res.ok) {
        const data = await res.json();
        return data.user;
      }
    } catch (e) {
      console.error('Auth check error:', e);
    }
    return false;
  };

  const login = async (username, password) => {
    try {
      console.log('Attempting login for username:', username);
      
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ username, password })
      });
      
      console.log('Login response status:', res.status);
      
      const data = await res.json();
      console.log('Login response data:', data);
      
      if (data.success && data.token) {
        setAuthToken(data.token);
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

  const autoInit = () => {
    const path = window.location.pathname;
    console.log('Auto-initializing for path:', path);
    
    if (path === '/') initIndex();
    else if (path === '/login') initLogin();
    else if (path === '/register') initRegister();
    else if (path === '/chat') initChat();
    else if (path === '/admin') initAdmin();
    else console.log('No specific init for:', path);
  };

  const initIndex = async () => {
    console.log('Initializing index page');
    const user = await checkAuth();
    if (user) {
      html('#nav-links', '<a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Chat</a><a class="nav-link" href="#" onclick="DevstralClient.logout()"><i class="bi bi-box-arrow-right"></i> Logout</a>');
      const actions = document.querySelector('.text-center:last-child');
      if (actions) html(actions, '<a href="/chat" class="btn btn-primary btn-lg"><i class="bi bi-chat-dots"></i> Continue Chatting</a>');
    }
  };

  const initLogin = async () => {
    console.log('Initializing login page');
    const user = await checkAuth();
    if (user) {
      console.log('User already authenticated, redirecting');
      window.location.href = user.is_admin ? '/admin' : '/chat';
      return;
    }

    on('#loginForm', 'submit', async (e) => {
      e.preventDefault();
      console.log('Login form submitted');
      
      const username = val('#username').trim();
      const password = val('#password').trim();
      
      console.log('Login attempt - Username:', username, 'Password length:', password.length);
      
      if (!username || !password) {
        showFlashMessage('Please enter both username and password', 'error');
        return;
      }

      const btn = $('#login-btn');
      const originalText = text(btn);
      text(btn, 'Logging in...');
      prop(btn, 'disabled', true);

      try {
        const result = await login(username, password);
        console.log('Login result:', result);
        
        if (result.success) {
          showFlashMessage('Login successful!', 'success');
          setTimeout(() => {
            window.location.href = result.user.is_admin ? '/admin' : '/chat';
          }, 1000);
        } else {
          showFlashMessage(result.error, 'error');
        }
      } catch (error) {
        console.error('Login exception:', error);
        showFlashMessage('Login failed: ' + error.message, 'error');
      } finally {
        text(btn, originalText);
        prop(btn, 'disabled', false);
      }
    });
  };

  const initRegister = async () => {
    console.log('Initializing register page');
    const user = await checkAuth();
    if (user) {
      window.location.href = user.is_admin ? '/admin' : '/chat';
      return;
    }

    // Show registration form by default
    const form = $('#registerForm');
    if (form) form.style.display = 'block';

    on('#registerForm', 'submit', async (e) => {
      e.preventDefault();
      const username = val('#username').trim();
      const password = val('#password').trim();
      const confirmPassword = val('#confirmPassword').trim();
      
      if (!username || !password || !confirmPassword) {
        showFlashMessage('Please fill in all fields', 'error');
        return;
      }

      if (password !== confirmPassword) {
        showFlashMessage('Passwords do not match', 'error');
        return;
      }

      const btn = $('#register-btn');
      const originalText = text(btn);
      text(btn, 'Creating account...');
      prop(btn, 'disabled', true);

      try {
        const result = await register(username, password);
        if (result.success) {
          showFlashMessage('Account created! Pending admin approval.', 'success');
          const form = $('#registerForm');
          if (form) form.style.display = 'none';
          html('#registration-info', `
            <div class="alert alert-info">
              <i class="bi bi-info-circle"></i> 
              Account created successfully! Your account is pending admin approval.
            </div>
          `);
        } else {
          showFlashMessage(result.error, 'error');
        }
      } catch (error) {
        showFlashMessage('Registration failed: ' + error.message, 'error');
      } finally {
        text(btn, originalText);
        prop(btn, 'disabled', false);
      }
    });
  };

  const initChat = async () => {
    console.log('Initializing chat page');
    const user = await checkAuth();
    if (!user) {
      window.location.href = '/login';
      return;
    }

    text('#username-display', user.username);

    const messagesContainer = $('#chat-messages');
    const messageInput = $('#message-input');
    const sendBtn = $('#send-btn');

    const sendMessage = async () => {
      const message = val(messageInput).trim();
      if (!message) return;

      val(messageInput, '');
      prop(sendBtn, 'disabled', true);

      // Add user message to chat
      const userMsg = createElement('div', 'message user-message');
      userMsg.innerHTML = `
        <div class="message-content">
          <div class="user-text">${escapeHtml(message)}</div>
        </div>
        <span class="message-timestamp">${new Date().toLocaleTimeString()}</span>
      `;
      append(messagesContainer, userMsg);
      scrollTop(messagesContainer, messagesContainer.scrollHeight);

      try {
        const res = await fetch('/api/chat/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + getAuthToken(),
            'Accept': 'application/json'
          },
          body: JSON.stringify({ message })
        });

        const data = await res.json();
        if (data.success) {
          // Add assistant response
          const assistantMsg = createElement('div', 'message assistant-message');
          assistantMsg.innerHTML = `
            <div class="message-content">
              <div class="ai-response">${escapeHtml(data.response)}</div>
            </div>
            <span class="message-timestamp">${new Date().toLocaleTimeString()}</span>
          `;
          append(messagesContainer, assistantMsg);
        } else {
          showFlashMessage('Failed to send message: ' + data.error, 'error');
        }
      } catch (error) {
        showFlashMessage('Failed to send message: ' + error.message, 'error');
      } finally {
        prop(sendBtn, 'disabled', false);
        scrollTop(messagesContainer, messagesContainer.scrollHeight);
      }
    };

    on(sendBtn, 'click', sendMessage);
    on(messageInput, 'keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
      }
    });
  };

  const initAdmin = async () => {
    console.log('Initializing admin page');
    const user = await checkAuth();
    if (!user) {
      window.location.href = '/login';
      return;
    }

    if (!user.is_admin) {
      window.location.href = '/unauthorised';
      return;
    }

    text('#username-display', user.username);
    loadAdminDashboard();
  };

  const loadAdminDashboard = async () => {
    try {
      const [usersRes, statsRes] = await Promise.all([
        fetch('/api/admin/users', {
          headers: { 
            'Authorization': 'Bearer ' + getAuthToken(),
            'Accept': 'application/json'
          }
        }),
        fetch('/api/admin/stats', {
          headers: { 
            'Authorization': 'Bearer ' + getAuthToken(),
            'Accept': 'application/json'
          }
        })
      ]);

      const users = await usersRes.json();
      const stats = await statsRes.json();

      if (users.success && stats.success) {
        renderAdminDashboard(users.users, stats.stats);
      } else {
        showFlashMessage('Failed to load admin data', 'error');
      }
    } catch (error) {
      showFlashMessage('Failed to load admin dashboard: ' + error.message, 'error');
    }
  };

  const renderAdminDashboard = (users, stats) => {
    const content = `
      <div class="row mb-4">
        <div class="col-12">
          <h2><i class="bi bi-speedometer2"></i> Admin Dashboard</h2>
        </div>
      </div>
      
      <div class="row mb-4">
        <div class="col-md-3">
          <div class="card">
            <div class="card-body text-center">
              <h5 class="card-title">Total Users</h5>
              <h3 class="text-primary">${stats.total_users}</h3>
            </div>
          </div>
        </div>
        <div class="col-md-3">
          <div class="card">
            <div class="card-body text-center">
              <h5 class="card-title">Approved</h5>
              <h3 class="text-success">${stats.approved_users}</h3>
            </div>
          </div>
        </div>
        <div class="col-md-3">
          <div class="card">
            <div class="card-body text-center">
              <h5 class="card-title">Pending</h5>
              <h3 class="text-warning">${stats.pending_users}</h3>
            </div>
          </div>
        </div>
        <div class="col-md-3">
          <div class="card">
            <div class="card-body text-center">
              <h5 class="card-title">Admins</h5>
              <h3 class="text-info">${stats.admin_users}</h3>
            </div>
          </div>
        </div>
      </div>

      <div class="row">
        <div class="col-12">
          <div class="card">
            <div class="card-header">
              <h5 class="mb-0"><i class="bi bi-people"></i> User Management</h5>
            </div>
            <div class="card-body">
              <div class="user-list">
                ${users.map(user => renderUserCard(user)).join('')}
              </div>
            </div>
          </div>
        </div>
      </div>
    `;

    html('#app-content', content);

    // Add event listeners for user actions
    users.forEach(user => {
      if (!user.is_approved && !user.is_admin) {
        on(`#approve-${user.id}`, 'click', () => approveUser(user.id));
        on(`#reject-${user.id}`, 'click', () => rejectUser(user.id));
      }
    });
  };

  const renderUserCard = (user) => {
    const statusBadge = user.is_admin ? 
      '<span class="badge bg-info">Admin</span>' :
      user.is_approved ? 
        '<span class="badge bg-success">Approved</span>' : 
        '<span class="badge bg-warning">Pending</span>';

    const actions = (!user.is_approved && !user.is_admin) ? `
      <button class="btn btn-sm btn-success me-2" id="approve-${user.id}">
        <i class="bi bi-check"></i> Approve
      </button>
      <button class="btn btn-sm btn-outline-danger" id="reject-${user.id}">
        <i class="bi bi-x"></i> Reject
      </button>
    ` : '';

    return `
      <div class="user-card">
        <div class="d-flex justify-content-between align-items-center">
          <div>
            <h6 class="mb-1">${escapeHtml(user.username)}</h6>
            <small class="text-muted">ID: ${user.id}</small>
          </div>
          <div>
            ${statusBadge}
            ${actions}
          </div>
        </div>
      </div>
    `;
  };

  const approveUser = async (userId) => {
    try {
      const res = await fetch('/api/admin/users/approve', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + getAuthToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ user_id: userId })
      });

      const data = await res.json();
      if (data.success) {
        showFlashMessage('User approved successfully', 'success');
        loadAdminDashboard();
      } else {
        showFlashMessage('Failed to approve user: ' + data.error, 'error');
      }
    } catch (error) {
      showFlashMessage('Failed to approve user: ' + error.message, 'error');
    }
  };

  const rejectUser = async (userId) => {
    if (!confirm('Are you sure you want to reject and delete this user?')) {
      return;
    }

    try {
      const res = await fetch('/api/admin/users/reject', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + getAuthToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ user_id: userId })
      });

      const data = await res.json();
      if (data.success) {
        showFlashMessage('User rejected and deleted', 'success');
        loadAdminDashboard();
      } else {
        showFlashMessage('Failed to reject user: ' + data.error, 'error');
      }
    } catch (error) {
      showFlashMessage('Failed to reject user: ' + error.message, 'error');
    }
  };

  return {
    showFlashMessage,
    logout,
    initIndex,
    initLogin,
    initRegister,
    initChat,
    initAdmin,
    checkAuth,
    login,
    register,
    autoInit,
    loadAdminDashboard,
    renderAdminDashboard,
    renderUserCard,
    approveUser,
    rejectUser
  };
})();

// Global exports
window.DevstralClient = DevstralClient;
window.logout = DevstralClient.logout;

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  console.log('DOM loaded, auto-initializing DevstralClient');
  DevstralClient.autoInit();
});