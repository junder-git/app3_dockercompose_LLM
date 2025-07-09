// nginx/static/js/client.js - Working version with security but no rate limiting bugs

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

  const on = (el, evt, cb) => {
    if (typeof el === 'string') el = $(el);
    el && el.addEventListener(evt, cb);
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

  const scrollTop = (el, v) => {
    if (typeof el === 'string') el = $(el);
    if (!el) return 0;
    if (v !== undefined) {
      el.scrollTop = v;
      return el;
    }
    return el.scrollTop;
  };

  // Basic input sanitization (keep it simple)
  const sanitizeInput = (input) => {
    if (typeof input !== 'string') return '';
    return input.replace(/[<>&"']/g, (match) => {
      const map = {
        '<': '&lt;',
        '>': '&gt;',
        '&': '&amp;',
        '"': '&quot;',
        "'": '&#x27;'
      };
      return map[match];
    });
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
      `<i class="bi ${icon}"></i> ${sanitizeInput(msg)}<button type="button" class="btn-close" data-bs-dismiss="alert"></button>`);
    alertDiv.setAttribute('role', 'alert');

    const container = $('#flash-messages');
    if (container) {
      append(container, alertDiv);
      setTimeout(() => remove(alertDiv), 5000);
    }
  };

  const getAuthToken = () => localStorage.getItem('auth_token') || '';
  const setAuthToken = (t) => t ? localStorage.setItem('auth_token', t) : localStorage.removeItem('auth_token');
  
  const logout = () => { 
    setAuthToken(null); 
    window.location.href = '/'; 
  };

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
      } else if (res.status === 401) {
        logout();
        return false;
      }
    } catch (e) {
      console.error('Auth check error:', e);
    }
    return false;
  };

  const login = async (username, password) => {
    // Basic input validation (not too strict)
    if (!username || !password) {
      return { success: false, error: 'Username and password are required' };
    }

    if (username.length < 3 || username.length > 50) {
      return { success: false, error: 'Username must be 3-50 characters' };
    }

    if (password.length < 6) {
      return { success: false, error: 'Password must be at least 6 characters' };
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
        return { success: true, user: data.user };
      }
      return { success: false, error: data.error || 'Login failed' };
    } catch (error) {
      console.error('Login error:', error);
      return { success: false, error: 'Network error: ' + error.message };
    }
  };

  const register = async (username, password) => {
    // Basic input validation
    if (!username || !password) {
      return { success: false, error: 'Username and password are required' };
    }

    if (username.length < 3 || username.length > 50) {
      return { success: false, error: 'Username must be 3-50 characters' };
    }

    if (password.length < 6) {
      return { success: false, error: 'Password must be at least 6 characters' };
    }

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
      window.location.href = user.is_admin ? '/admin' : '/chat';
      return;
    }

    on('#loginForm', 'submit', async (e) => {
      e.preventDefault();
      
      const username = val('#username').trim();
      const password = val('#password').trim();
      
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
        
        if (result.success) {
          showFlashMessage('Login successful!', 'success');
          setTimeout(() => {
            window.location.href = result.user.is_admin ? '/admin' : '/chat';
          }, 1000);
        } else {
          showFlashMessage(result.error, 'error');
        }
      } catch (error) {
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

    let isStreaming = false;
    let currentStreamingMessage = null;

    const sendMessage = async () => {
      const message = val(messageInput).trim();
      if (!message || isStreaming) return;

      if (message.length > 5000) {
        showFlashMessage('Message too long (max 5000 characters)', 'error');
        return;
      }

      val(messageInput, '');
      prop(sendBtn, 'disabled', true);
      isStreaming = true;

      // Add user message
      const userMsg = createElement('div', 'message user-message');
      userMsg.innerHTML = `
        <div class="message-content">
          <div class="user-text">${sanitizeInput(message)}</div>
        </div>
        <span class="message-timestamp">${new Date().toLocaleTimeString()}</span>
      `;
      append(messagesContainer, userMsg);
      scrollTop(messagesContainer, messagesContainer.scrollHeight);

      try {
        currentStreamingMessage = createElement('div', 'message assistant-message');
        currentStreamingMessage.innerHTML = `
          <div class="message-content">
            <div class="ai-response" id="streaming-content">Thinking...</div>
          </div>
          <span class="message-timestamp">${new Date().toLocaleTimeString()}</span>
        `;
        append(messagesContainer, currentStreamingMessage);

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 900000);
        
        const response = await fetch('/api/chat', {
          signal: controller.signal,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + getAuthToken(),
            'Accept': 'application/json'
          },
          body: JSON.stringify({
            model: "devstral",
            messages: [{ role: "user", content: message }],
            stream: false
          })
        });

        clearTimeout(timeoutId);

        if (!response.ok) {
          if (response.status === 401) {
            logout();
            return;
          }
          throw new Error(`HTTP ${response.status}`);
        }

        const responseData = await response.json();
        let finalResponse = '';
        
        if (responseData.message && responseData.message.content) {
          finalResponse = responseData.message.content;
        } else if (responseData.response) {
          finalResponse = responseData.response;
        } else {
          finalResponse = 'I received your message but couldn\'t process it properly.';
        }

        const streamingContent = $('#streaming-content');
        if (streamingContent) {
          streamingContent.textContent = finalResponse;
        }

      } catch (error) {
        console.error('Failed to send message:', error);
        showFlashMessage('Chat Error: ' + error.message, 'error');
        
        if (currentStreamingMessage) {
          const streamingContent = currentStreamingMessage.querySelector('#streaming-content');
          if (streamingContent) {
            streamingContent.innerHTML = `
              <div class="alert alert-danger">
                <strong>Error:</strong> ${sanitizeInput(error.message)}
              </div>
            `;
          }
        }
      } finally {
        isStreaming = false;
        currentStreamingMessage = null;
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
    showFlashMessage('Admin panel loaded successfully', 'success');
    
    // Load admin dashboard content
    loadAdminDashboard();
  };

  const loadAdminDashboard = async () => {
    try {
      const response = await fetch('/api/admin/dashboard', {
        headers: {
          'Authorization': 'Bearer ' + getAuthToken(),
          'Accept': 'text/html'
        }
      });

      if (response.ok) {
        const adminHtml = await response.text();
        html('#app-content', adminHtml);
      } else {
        showFlashMessage('Failed to load admin dashboard', 'error');
      }
    } catch (error) {
      showFlashMessage('Failed to load admin dashboard: ' + error.message, 'error');
    }
  };

  return {
    showFlashMessage,
    logout,
    checkAuth,
    autoInit
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