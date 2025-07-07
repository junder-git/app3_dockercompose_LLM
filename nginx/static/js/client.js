const initLogin = async () => {
    const user = await checkAuth();
    if (user) {
      window.location.href = user.is_admin ? '/admin' : '/chat';
      return;
    }

    on('#loginForm', 'submit', async (e) => {
      e.preventDefault();
      const username = val('#username');
      const password = val('#password');
      
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
          window.location.href = result.user.is_admin ? '/admin' : '/chat';
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
    const user = await checkAuth();
    if (user) {
      window.location.href = user.is_admin ? '/admin' : '/chat';
      return;
    }

    // Show registration form by default
    $('#registerForm').style.display = 'block';

    on('#registerForm', 'submit', async (e) => {
      e.preventDefault();
      const username = val('#username');
      const password = val('#password');
      const confirmPassword = val('#confirmPassword');
      
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
          $('#registerForm').style.display = 'none';
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
            'Authorization': 'Bearer ' + getAuthToken()
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

    // Load admin dashboard
    loadAdminDashboard();
  };

  const loadAdminDashboard = async () => {
    try {
      const [usersRes, statsRes] = await Promise.all([
        fetch('/api/admin/users', {
          headers: { 'Authorization': 'Bearer ' + getAuthToken() }
        }),
        fetch('/api/admin/stats', {
          headers: { 'Authorization': 'Bearer ' + getAuthToken() }
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
          'Authorization': 'Bearer ' + getAuthToken()
        },
        body: JSON.stringify({ user_id: userId })
      });

      const data = await res.json();
      if (data.success) {
        showFlashMessage('User approved successfully', 'success');
        loadAdminDashboard(); // Reload dashboard
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
          'Authorization': 'Bearer ' + getAuthToken()
        },
        body: JSON.stringify({ user_id: userId })
      });

      const data = await res.json();
      if (data.success) {
        showFlashMessage('User rejected and deleted', 'success');
        loadAdminDashboard(); // Reload dashboard
      } else {
        showFlashMessage('Failed to reject user: ' + data.error, 'error');
      }
    } catch (error) {
      showFlashMessage('Failed to reject user: ' + error.message, 'error');
    }
  };