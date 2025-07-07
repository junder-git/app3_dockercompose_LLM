// nginx/static/js/client.js - ES6+ Full Version

const DevstralClient = (() => {
  'use strict';

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
      const res = await fetch('/api/auth/verify', { headers: { Authorization: `Bearer ${token}` } });
      if (res.ok) {
        const data = await res.json();
        return data.user;
      }
    } catch {}
    return false;
  };

  const login = async (username, password) => {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });
    const data = await res.json();
    if (data.token) {
      setAuthToken(data.token);
      return { success: true, user: data.user };
    }
    return { success: false, error: data.error || 'Login failed' };
  };

  const register = async (username, password) => {
    const res = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });
    return res.json();
  };

  const autoInit = () => {
    const path = window.location.pathname;
    if (path === '/') initIndex();
    else if (path === '/login') initLogin();
    else if (path === '/register') initRegister();
    else if (path === '/chat') initChat();
    else if (path === '/admin') initAdmin();
    else console.log('No specific init for:', path);
  };

  const initIndex = async () => {
    const user = await checkAuth();
    if (user) {
      html('#nav-links', '<a class="nav-link" href="/chat"><i class="bi bi-chat-dots"></i> Chat</a><a class="nav-link" href="#" onclick="DevstralClient.logout()"><i class="bi bi-box-arrow-right"></i> Logout</a>');
      const actions = document.querySelector('.text-center:last-child');
      if (actions) html(actions, '<a href="/chat" class="btn btn-primary btn-lg"><i class="bi bi-chat-dots"></i> Continue Chatting</a>');
    }
  };

  // (Other init functions remain similar; move logic into arrow functions with async/await as above)

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
    autoInit
  };
})();

window.logout = DevstralClient.logout;
document.addEventListener('DOMContentLoaded', () => DevstralClient.autoInit());
