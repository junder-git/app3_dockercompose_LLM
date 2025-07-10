window.DevstralCommon = {
    $: (selector, parent = document) => parent.querySelector(selector),

    $$: (selector, parent = document) => parent.querySelectorAll(selector),

    val: (selector) => DevstralCommon.$(selector)?.value || '',

    text: (el, text = null) => {
        if (!el) return;
        if (text !== null) el.innerText = text;
        else return el.innerText;
    },

    html: (selector, html) => {
        const el = DevstralCommon.$(selector);
        if (el) el.innerHTML = html;
    },

    prop: (el, prop, value) => {
        if (el) el[prop] = value;
    },

    showFlashMessage: (message, type = 'success', container = '#flash-messages') => {
        const flashContainer = DevstralCommon.$(container);
        if (!flashContainer) return;

        const div = document.createElement('div');
        div.className = `alert alert-${type}`;
        div.innerHTML = `<i class="bi bi-info-circle"></i> ${message}`;

        flashContainer.innerHTML = '';
        flashContainer.appendChild(div);

        setTimeout(() => {
            div.remove();
        }, 5000);
    },

    isTokenExpired: (token) => {
        try {
            const payload = JSON.parse(atob(token.split('.')[1]));
            return payload.exp && payload.exp < Date.now() / 1000;
        } catch (e) {
            return true;
        }
    },

    saveToken: (token) => {
        localStorage.setItem('auth_token', token);
    },

    getToken: () => {
        return localStorage.getItem('auth_token');
    },

    clearToken: () => {
        localStorage.removeItem('auth_token');
    },

    authHeaders: () => {
        const token = DevstralCommon.getToken();
        return token ? { 'Authorization': `Bearer ${token}` } : {};
    },

    login: async (username, password) => {
        const response = await fetch('/api/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.error || 'Login failed');
        }

        const data = await response.json();
        if (data.success && data.token) {
            DevstralCommon.saveToken(data.token);
        }
        return data;
    },

    logout: () => {
        DevstralCommon.clearToken();
        window.location.href = '/login';
    },

    fetchWithAuth: async (url, options = {}) => {
        const headers = { ...(options.headers || {}), ...DevstralCommon.authHeaders() };
        const response = await fetch(url, { ...options, headers });

        if (response.status === 401) {
            DevstralCommon.logout();
            throw new Error('Unauthorized - logged out');
        }

        return response;
    }
};
