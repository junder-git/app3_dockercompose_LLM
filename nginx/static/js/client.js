// nginx/static/js/client.js - SECURE VERSION (Fixed syntax errors)

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
    alertDiv.setAttribute('role', 'alert');

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

  // ===== STREAMING CHAT IMPLEMENTATION =====
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

    // State for streaming
    let isStreaming = false;
    let currentStreamingMessage = null;

    // Load chat history on page load
    await loadChatHistory(user.id, messagesContainer);

    const sendMessage = async () => {
      const message = val(messageInput).trim();
      if (!message || isStreaming) return;

      val(messageInput, '');
      prop(sendBtn, 'disabled', true);
      isStreaming = true;

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
        // Use HTTP streaming for Ollama
        const response = await fetch('/ollama/api/chat', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + getAuthToken(),
            'Accept': 'text/plain'
          },
          body: JSON.stringify({
            model: "devstral", // Use the model from your .env
            messages: [
              {
                role: "user",
                content: message
              }
            ],
            stream: true
          })
        });

        if (!response.ok) {
          throw new Error('Failed to get response from Ollama');
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        // Create streaming message container
        currentStreamingMessage = createElement('div', 'message assistant-message');
        currentStreamingMessage.innerHTML = `
          <div class="message-content">
            <div class="ai-response" id="streaming-content"></div>
          </div>
          <span class="message-timestamp">${new Date().toLocaleTimeString()}</span>
        `;
        append(messagesContainer, currentStreamingMessage);

        let accumulatedResponse = '';
        let streamEnded = false;

        while (!streamEnded) {
          const { done, value } = await reader.read();
          
          if (done) {
            streamEnded = true;
            break;
          }
          
          const chunk = decoder.decode(value);
          const lines = chunk.split('\n');
          
          for (const line of lines) {
            if (line.trim() && line.startsWith('data: ')) {
              try {
                const data = JSON.parse(line.substring(6));
                if (data.message && data.message.content) {
                  accumulatedResponse += data.message.content;
                  const streamingContent = $('#streaming-content');
                  if (streamingContent) {
                    streamingContent.textContent = accumulatedResponse;
                  }
                  scrollTop(messagesContainer, messagesContainer.scrollHeight);
                }
                
                if (data.done) {
                  streamEnded = true;
                  break;
                }
              } catch (e) {
                console.error('Error parsing streaming data:', e);
              }
            }
          }
        }

        // Save conversation after streaming is complete
        if (accumulatedResponse) {
          await saveConversationToRedis(user.id, message, accumulatedResponse);
        }

      } catch (error) {
        console.error('Failed to send message:', error);
        showFlashMessage('Failed to send message: ' + error.message, 'error');
        
        // Remove failed streaming message
        if (currentStreamingMessage) {
          remove(currentStreamingMessage);
          currentStreamingMessage = null;
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

  // Helper functions for chat
  const saveConversationToRedis = async (userId, userMessage, assistantResponse) => {
    try {
      const chatId = Date.now().toString() + '_' + userId;
      
      await fetch('/redis/hset', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + getAuthToken()
        },
        body: JSON.stringify({
          key: `chat:${chatId}`,
          field: 'conversation',
          value: JSON.stringify({
            user_message: userMessage,
            assistant_response: assistantResponse,
            timestamp: new Date().toISOString(),
            user_id: userId
          })
        })
      });
    } catch (error) {
      console.error('Failed to save conversation:', error);
    }
  };

  const loadChatHistory = async (userId, container) => {
    try {
      const response = await fetch(`/redis/get?key=chat_history:${userId}`, {
        headers: {
          'Authorization': 'Bearer ' + getAuthToken()
        }
      });

      if (response.ok) {
        const data = await response.json();
        if (data.success && data.value) {
          const history = JSON.parse(data.value);
          renderChatHistory(history, container);
        }
      }
    } catch (error) {
      console.error('Failed to load chat history:', error);
    }
  };

  const renderChatHistory = (history, container) => {
    // Clear existing messages except welcome message
    const welcomeMsg = container.querySelector('.assistant-message');
    container.innerHTML = '';
    if (welcomeMsg) {
      append(container, welcomeMsg);
    }

    // Render history
    history.forEach(chat => {
      // User message
      const userMsg = createElement('div', 'message user-message');
      userMsg.innerHTML = `
        <div class="message-content">
          <div class="user-text">${escapeHtml(chat.user_message)}</div>
        </div>
        <span class="message-timestamp">${new Date(chat.timestamp).toLocaleTimeString()}</span>
      `;
      append(container, userMsg);

      // Assistant message
      const assistantMsg = createElement('div', 'message assistant-message');
      assistantMsg.innerHTML = `
        <div class="message-content">
          <div class="ai-response">${escapeHtml(chat.assistant_response)}</div>
        </div>
        <span class="message-timestamp">${new Date(chat.timestamp).toLocaleTimeString()}</span>
      `;
      append(container, assistantMsg);
    });

    scrollTop(container, container.scrollHeight);
  };

  // ===== SECURE ADMIN REDIRECT =====
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
    
    // SECURITY: Admin functionality loaded from server, not client
    showLoadingIndicator();
    loadAdminContentFromServer();
  };

  const showLoadingIndicator = () => {
    const loadingDiv = $('#loading-indicator');
    if (loadingDiv) {
      loadingDiv.style.display = 'flex';
    }
  };

  const hideLoadingIndicator = () => {
    const loadingDiv = $('#loading-indicator');
    if (loadingDiv) {
      loadingDiv.style.display = 'none';
    }
  };

  const loadAdminContentFromServer = async () => {
    try {
      // Server renders the admin interface with proper permission checking
      const response = await fetch('/api/admin/dashboard', {
        headers: {
          'Authorization': 'Bearer ' + getAuthToken(),
          'Accept': 'text/html' // Request HTML, not JSON
        }
      });

      if (response.ok) {
        const adminHtml = await response.text();
        html('#app-content', adminHtml);
        
        // Only attach event listeners for elements that exist
        attachAdminEventListeners();
      } else {
        showFlashMessage('Failed to load admin dashboard', 'error');
        window.location.href = '/unauthorised';
      }
    } catch (error) {
      showFlashMessage('Failed to load admin dashboard: ' + error.message, 'error');
    } finally {
      hideLoadingIndicator();
    }
  };

  const attachAdminEventListeners = () => {
    // Event delegation for dynamically loaded admin content
    const appContent = $('#app-content');
    if (!appContent) return;

    appContent.addEventListener('click', async (e) => {
      const target = e.target.closest('button');
      if (!target) return;

      const action = target.dataset.action;
      const userId = target.dataset.userId;

      if (action === 'approve' && userId) {
        e.preventDefault();
        await performAdminAction('approve', userId);
      } else if (action === 'reject' && userId) {
        e.preventDefault();
        if (confirm('Are you sure you want to reject and delete this user?')) {
          await performAdminAction('reject', userId);
        }
      }
    });
  };

  const performAdminAction = async (action, userId) => {
    const endpoint = action === 'approve' ? '/api/admin/users/approve' : '/api/admin/users/reject';
    
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + getAuthToken()
        },
        body: JSON.stringify({ user_id: userId })
      });

      const data = await response.json();
      if (data.success) {
        showFlashMessage(`User ${action}d successfully`, 'success');
        // Reload admin content from server
        loadAdminContentFromServer();
      } else {
        showFlashMessage(`Failed to ${action} user: ${data.error}`, 'error');
      }
    } catch (error) {
      showFlashMessage(`Failed to ${action} user: ${error.message}`, 'error');
    }
  };

  return {
    showFlashMessage,
    logout,
    checkAuth,
    autoInit
  };
})();

// Global exports (minimal and secure)
window.DevstralClient = DevstralClient;
window.logout = DevstralClient.logout;

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  console.log('DOM loaded, auto-initializing DevstralClient');
  DevstralClient.autoInit();
});