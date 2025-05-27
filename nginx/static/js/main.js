// static/js/main.js - Complete version with all functionality

// Global app namespace
const ChatApp = {
    ws: null,
    currentStreamMessage: null,
    isWaitingForResponse: false,
    currentPage: null,
    githubToken: localStorage.getItem('github_token') || null,
    githubUsername: localStorage.getItem('github_username') || null
};

// Utility functions
const Utils = {
    showError: function(message, container) {
        const errorDiv = document.createElement('div');
        errorDiv.className = 'error-message';
        errorDiv.textContent = message;
        container.appendChild(errorDiv);
        
        // Auto-remove after 5 seconds
        setTimeout(() => errorDiv.remove(), 5000);
    },
    
    showSuccess: function(message, container) {
        const successDiv = document.createElement('div');
        successDiv.className = 'success-message';
        successDiv.textContent = message;
        container.appendChild(successDiv);
        
        // Auto-remove after 3 seconds
        setTimeout(() => successDiv.remove(), 3000);
    },
    
    formatDate: function(dateString) {
        return new Date(dateString).toLocaleString();
    },

    // Detect code blocks in text
    detectCodeBlocks: function(text) {
        const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
        const inlineCodeRegex = /`([^`]+)`/g;
        
        let result = text;
        const codeBlocks = [];
        let match;
        
        // Extract multi-line code blocks
        while ((match = codeBlockRegex.exec(text)) !== null) {
            const language = match[1] || 'text';
            const code = match[2];
            const id = 'code-block-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
            
            codeBlocks.push({ id, language, code, type: 'block' });
            
            const placeholder = `__CODE_BLOCK_${codeBlocks.length - 1}__`;
            result = result.replace(match[0], placeholder);
        }
        
        // Reset regex
        codeBlockRegex.lastIndex = 0;
        
        return { text: result, codeBlocks };
    },

    // Copy text to clipboard
    copyToClipboard: async function(text) {
        try {
            await navigator.clipboard.writeText(text);
            return true;
        } catch (err) {
            // Fallback for older browsers
            const textArea = document.createElement('textarea');
            textArea.value = text;
            textArea.style.position = 'fixed';
            textArea.style.left = '-999999px';
            textArea.style.top = '-999999px';
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();
            
            try {
                document.execCommand('copy');
                document.body.removeChild(textArea);
                return true;
            } catch (err) {
                document.body.removeChild(textArea);
                return false;
            }
        }
    },

    // Render code block with syntax highlighting
    renderCodeBlock: function(codeBlock) {
        const container = document.createElement('div');
        container.className = 'code-block-container';
        container.innerHTML = `
            <div class="code-block-header">
                <span class="code-language" data-lang="${codeBlock.language}">${codeBlock.language}</span>
                <div class="code-actions">
                    <button class="btn-copy" title="Copy to clipboard">
                        <i class="bi bi-copy"></i>
                    </button>
                    <button class="btn-github" title="Create GitHub Gist" style="display: ${ChatApp.githubToken ? 'inline-block' : 'none'}">
                        <i class="bi bi-github"></i>
                    </button>
                </div>
            </div>
            <pre><code class="language-${codeBlock.language}" id="${codeBlock.id}">${this.escapeHtml(codeBlock.code)}</code></pre>
        `;

        // Add copy functionality
        const copyBtn = container.querySelector('.btn-copy');
        copyBtn.addEventListener('click', async () => {
            const success = await this.copyToClipboard(codeBlock.code);
            if (success) {
                copyBtn.innerHTML = '<i class="bi bi-check"></i>';
                copyBtn.classList.add('copied');
                setTimeout(() => {
                    copyBtn.innerHTML = '<i class="bi bi-copy"></i>';
                    copyBtn.classList.remove('copied');
                }, 2000);
            }
        });

        // Add GitHub gist functionality
        const githubBtn = container.querySelector('.btn-github');
        githubBtn.addEventListener('click', () => {
            GitHubIntegration.createGist(codeBlock.code, codeBlock.language);
        });

        return container;
    },

    escapeHtml: function(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    // Process message content with code blocks
    processMessageContent: function(content) {
        const { text, codeBlocks } = this.detectCodeBlocks(content);
        const container = document.createElement('div');
        container.className = 'message-content';
        
        let processedText = text;
        
        // Replace code block placeholders with actual rendered blocks
        codeBlocks.forEach((block, index) => {
            const placeholder = `__CODE_BLOCK_${index}__`;
            const parts = processedText.split(placeholder);
            
            // Create text part before code block
            if (parts[0]) {
                const textDiv = document.createElement('div');
                textDiv.className = 'message-text';
                textDiv.textContent = parts[0];
                container.appendChild(textDiv);
            }
            
            // Add code block
            container.appendChild(this.renderCodeBlock(block));
            
            // Update text for next iteration
            processedText = parts.slice(1).join(placeholder);
        });
        
        // Add remaining text
        if (processedText) {
            const textDiv = document.createElement('div');
            textDiv.className = 'message-text';
            textDiv.textContent = processedText;
            container.appendChild(textDiv);
        }
        
        return container;
    }
};

// GitHub Integration
const GitHubIntegration = {
    init: function() {
        this.loadSettings();
        this.createSettingsModal();
    },

    loadSettings: function() {
        ChatApp.githubToken = localStorage.getItem('github_token') || null;
        ChatApp.githubUsername = localStorage.getItem('github_username') || null;
    },

    saveSettings: function(token, username) {
        localStorage.setItem('github_token', token);
        localStorage.setItem('github_username', username);
        ChatApp.githubToken = token;
        ChatApp.githubUsername = username;
        
        // Update GitHub buttons visibility
        document.querySelectorAll('.btn-github').forEach(btn => {
            btn.style.display = token ? 'inline-block' : 'none';
        });
    },

    createSettingsModal: function() {
        const modal = document.createElement('div');
        modal.innerHTML = `
            <div class="modal fade" id="githubSettingsModal" tabindex="-1">
                <div class="modal-dialog">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h5 class="modal-title">
                                <i class="bi bi-github"></i> GitHub Integration
                            </h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                        </div>
                        <div class="modal-body">
                            <div class="mb-3">
                                <label for="githubToken" class="form-label">Personal Access Token</label>
                                <input type="password" class="form-control" id="githubToken" 
                                       placeholder="ghp_xxxxxxxxxxxxxxxxxxxx"
                                       value="${ChatApp.githubToken || ''}">
                                <div class="form-text">
                                    Create a token at: <a href="https://github.com/settings/tokens" target="_blank">GitHub Settings</a>
                                    <br>Required scopes: <code>gist</code>
                                </div>
                            </div>
                            <div class="mb-3">
                                <label for="githubUsername" class="form-label">Username</label>
                                <input type="text" class="form-control" id="githubUsername" 
                                       placeholder="your-username"
                                       value="${ChatApp.githubUsername || ''}">
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                            <button type="button" class="btn btn-primary" id="saveGithubSettings">Save</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        document.body.appendChild(modal.firstElementChild);

        // Add save functionality
        document.getElementById('saveGithubSettings').addEventListener('click', () => {
            const token = document.getElementById('githubToken').value.trim();
            const username = document.getElementById('githubUsername').value.trim();
            
            if (token && username) {
                this.saveSettings(token, username);
                bootstrap.Modal.getInstance(document.getElementById('githubSettingsModal')).hide();
                Utils.showSuccess('GitHub settings saved!', document.querySelector('.chat-messages') || document.body);
            }
        });
    },

    createGist: async function(code, language) {
        if (!ChatApp.githubToken) {
            const modal = new bootstrap.Modal(document.getElementById('githubSettingsModal'));
            modal.show();
            return;
        }

        try {
            const filename = `code.${this.getFileExtension(language)}`;
            const response = await fetch('https://api.github.com/gists', {
                method: 'POST',
                headers: {
                    'Authorization': `token ${ChatApp.githubToken}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    description: `Code snippet from AI Chat - ${new Date().toISOString()}`,
                    public: false,
                    files: {
                        [filename]: {
                            content: code
                        }
                    }
                })
            });

            if (response.ok) {
                const gist = await response.json();
                window.open(gist.html_url, '_blank');
                Utils.showSuccess('Gist created successfully!', document.querySelector('.chat-messages') || document.body);
            } else {
                throw new Error(`GitHub API error: ${response.status}`);
            }
        } catch (error) {
            console.error('GitHub gist creation failed:', error);
            Utils.showError('Failed to create GitHub gist. Check your token and try again.', document.querySelector('.chat-messages') || document.body);
        }
    },

    getFileExtension: function(language) {
        const extensions = {
            javascript: 'js',
            typescript: 'ts',
            python: 'py',
            java: 'java',
            cpp: 'cpp',
            csharp: 'cs',
            php: 'php',
            ruby: 'rb',
            go: 'go',
            rust: 'rs',
            kotlin: 'kt',
            swift: 'swift',
            html: 'html',
            css: 'css',
            scss: 'scss',
            less: 'less',
            json: 'json',
            xml: 'xml',
            yaml: 'yml',
            markdown: 'md',
            sql: 'sql',
            bash: 'sh',
            shell: 'sh',
            powershell: 'ps1',
            dockerfile: 'dockerfile',
            nginx: 'conf'
        };
        return extensions[language.toLowerCase()] || 'txt';
    }
};

// Admin Database Management
const AdminDB = {
    currentAction: null,
    
    init: function() {
        this.loadDatabaseStats();
        this.loadUsers();
        this.bindEvents();
    },

    bindEvents: function() {
        // Make functions globally available for onclick handlers
        window.performCleanup = this.performCleanup.bind(this);
        window.createBackup = this.createBackup.bind(this);
        window.refreshAllData = this.refreshAllData.bind(this);
        
        // Confirmation modal events
        const confirmBtn = document.getElementById('confirmActionBtn');
        if (confirmBtn) {
            confirmBtn.addEventListener('click', this.executeCleanup.bind(this));
        }
    },
    
    loadDatabaseStats: async function() {
        try {
            const response = await fetch('/api/admin/database/stats');
            const stats = await response.json();
            
            if (stats.error) {
                this.renderStatsError(stats.error);
                return;
            }
            
            this.renderDatabaseStats(stats);
        } catch (error) {
            console.error('Error loading database stats:', error);
            this.renderStatsError(error.message);
        }
    },
    
    renderDatabaseStats: function(stats) {
        const container = document.getElementById('databaseStats');
        const statusBadge = document.getElementById('dbStatusBadge');
        const userCount = document.getElementById('userCount');
        
        if (!container) return; // Not on admin page
        
        statusBadge.textContent = 'Online';
        statusBadge.className = 'badge bg-success ms-2';
        userCount.textContent = stats.user_count || 0;
        
        container.innerHTML = `
            <div class="row text-center">
                <div class="col-6">
                    <div class="border rounded p-2 mb-2">
                        <div class="h4 text-primary mb-0">${stats.total_keys || 0}</div>
                        <small class="text-muted">Total Keys</small>
                    </div>
                </div>
                <div class="col-6">
                    <div class="border rounded p-2 mb-2">
                        <div class="h4 text-info mb-0">${stats.user_count || 0}</div>
                        <small class="text-muted">Users</small>
                    </div>
                </div>
            </div>
            <div class="mb-2">
                <small class="text-muted">Key Types:</small>
                <ul class="list-unstyled small">
                    ${Object.entries(stats.key_types || {}).map(([type, count]) => 
                        `<li>• ${type}: ${count}</li>`
                    ).join('')}
                </ul>
            </div>
            ${stats.memory_usage ? `
                <div class="mb-2">
                    <small class="text-muted">Memory: ${stats.memory_usage.used_memory}</small>
                </div>
            ` : ''}
            <div>
                <small class="text-muted">Next User ID: ${stats.next_user_id}</small>
            </div>
        `;
    },
    
    renderStatsError: function(error) {
        const container = document.getElementById('databaseStats');
        const statusBadge = document.getElementById('dbStatusBadge');
        
        if (!container) return; // Not on admin page
        
        statusBadge.textContent = 'Error';
        statusBadge.className = 'badge bg-danger ms-2';
        
        container.innerHTML = `
            <div class="alert alert-danger">
                <strong>Database Error:</strong> ${error}
            </div>
        `;
    },
    
    performCleanup: function(type) {
        const actions = {
            'clear_cache': {
                title: 'Clear Cache',
                message: 'This will clear all AI response cache and rate limiting data. Chat history will be preserved.',
                danger: false
            },
            'fix_sessions': {
                title: 'Fix Orphaned Sessions',
                message: 'This will remove chat sessions that belong to deleted users.',
                danger: false
            },
            'recreate_admin': {
                title: 'Recreate Admin User',
                message: 'This will recreate the admin user with proper settings. Current admin sessions may be affected.',
                danger: true
            },
            'fix_users': {
                title: 'Fix User Data',
                message: 'This will reset all user accounts and recreate the admin user. All user accounts will be lost, but chat data will be preserved.',
                danger: true
            },
            'complete_reset': {
                title: 'Complete Database Reset',
                message: 'This will delete ALL data from the database and recreate only the admin user. Everything will be lost!',
                danger: true
            }
        };
        
        const action = actions[type];
        if (!action) return;
        
        this.currentAction = type;
        
        document.getElementById('confirmationMessage').innerHTML = `
            <strong>${action.title}</strong><br>
            ${action.message}
        `;
        
        const confirmBtn = document.getElementById('confirmActionBtn');
        confirmBtn.className = action.danger ? 'btn btn-danger' : 'btn btn-warning';
        confirmBtn.textContent = action.danger ? 'Yes, Delete' : 'Confirm';
        
        const modal = new bootstrap.Modal(document.getElementById('confirmationModal'));
        modal.show();
    },

    executeCleanup: async function() {
        const modal = bootstrap.Modal.getInstance(document.getElementById('confirmationModal'));
        modal.hide();
        
        if (!this.currentAction) return;
        
        // Show loading modal
        const loadingModal = new bootstrap.Modal(document.getElementById('loadingModal'));
        document.getElementById('loadingMessage').textContent = 'Processing database operation...';
        loadingModal.show();
        
        try {
            const response = await fetch('/api/admin/database/cleanup', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                },
                body: JSON.stringify({ type: this.currentAction })
            });
            
            const result = await response.json();
            
            loadingModal.hide();
            
            // Show results
            const resultsDiv = document.getElementById('cleanupResults');
            const messageDiv = document.getElementById('cleanupMessage');
            
            if (result.success) {
                messageDiv.className = 'alert alert-success';
                messageDiv.innerHTML = `
                    <strong>Success!</strong> ${result.message}
                    <br><small>Completed at: ${new Date(result.timestamp).toLocaleString()}</small>
                `;
            } else {
                messageDiv.className = 'alert alert-danger';
                messageDiv.innerHTML = `<strong>Error:</strong> ${result.message}`;
            }
            
            resultsDiv.style.display = 'block';
            
            // Refresh data
            setTimeout(() => {
                this.refreshAllData();
            }, 1000);
            
        } catch (error) {
            loadingModal.hide();
            console.error('Cleanup error:', error);
            
            const resultsDiv = document.getElementById('cleanupResults');
            const messageDiv = document.getElementById('cleanupMessage');
            
            messageDiv.className = 'alert alert-danger';
            messageDiv.innerHTML = `<strong>Network Error:</strong> ${error.message}`;
            resultsDiv.style.display = 'block';
        }
        
        this.currentAction = null;
    },

    createBackup: async function() {
        const loadingModal = new bootstrap.Modal(document.getElementById('loadingModal'));
        document.getElementById('loadingMessage').textContent = 'Creating database backup...';
        loadingModal.show();
        
        try {
            const response = await fetch('/api/admin/database/backup');
            const backup = await response.json();
            
            loadingModal.hide();
            
            if (backup.error) {
                alert('Backup failed: ' + backup.error);
                return;
            }
            
            // Download backup as JSON file
            const blob = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `redis-backup-${new Date().toISOString().split('T')[0]}.json`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
        } catch (error) {
            loadingModal.hide();
            console.error('Backup error:', error);
            alert('Backup failed: ' + error.message);
        }
    },

    refreshAllData: function() {
        this.loadDatabaseStats();
        AdminPage.loadUsers();
    }
};

// Page-specific initialization
document.addEventListener('DOMContentLoaded', function() {
    // Load Prism.js for syntax highlighting
    const prismCSS = document.createElement('link');
    prismCSS.rel = 'stylesheet';
    prismCSS.href = '/cdn/npm/prismjs@1.29.0/themes/prism-tomorrow.css';
    document.head.appendChild(prismCSS);

    const prismJS = document.createElement('script');
    prismJS.src = '/cdn/npm/prismjs@1.29.0/components/prism-core.min.js';
    prismJS.onload = () => {
        // Load additional language components
        const languages = ['markup', 'css', 'javascript', 'python', 'java', 'cpp', 'csharp', 'php', 'ruby', 'go', 'rust', 'kotlin', 'swift', 'sql', 'bash', 'json', 'yaml', 'markdown'];
        languages.forEach(lang => {
            const script = document.createElement('script');
            script.src = `/cdn/npm/prismjs@1.29.0/components/prism-${lang}.min.js`;
            document.head.appendChild(script);
        });
    };
    document.head.appendChild(prismJS);

    // Initialize GitHub integration
    GitHubIntegration.init();

    // Detect current page
    const path = window.location.pathname;
    
    if (path === '/chat') {
        ChatApp.currentPage = 'chat';
        ChatPage.init();
    } else if (path === '/admin') {
        ChatApp.currentPage = 'admin';
        AdminPage.init();
    } else if (path === '/register') {
        ChatApp.currentPage = 'register';
        RegisterPage.init();
    }
});

// Chat Page Handler
const ChatPage = {
    elements: {},
    currentSession: null,
    
    init: function() {
        this.elements = {
            chatMessages: document.getElementById('chatMessages'),
            messageInput: document.getElementById('messageInput'),
            sendButton: document.getElementById('sendButton'),
            typingIndicator: document.getElementById('typingIndicator'),
            githubSettingsBtn: document.getElementById('githubSettingsBtn'),
            sessionsList: document.getElementById('sessionsList'),
            newSessionBtn: document.getElementById('newSessionBtn')
        };
        
        this.bindEvents();
        this.initWebSocket();
        this.setupTextareaAutoResize();
        this.loadSessions();
    },
    
    bindEvents: function() {
        this.elements.sendButton.addEventListener('click', () => this.sendMessage());
        this.elements.messageInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                this.sendMessage();
            }
        });

        // GitHub settings button
        if (this.elements.githubSettingsBtn) {
            this.elements.githubSettingsBtn.addEventListener('click', () => {
                const modal = new bootstrap.Modal(document.getElementById('githubSettingsModal'));
                modal.show();
            });
        }

        // New session button
        if (this.elements.newSessionBtn) {
            this.elements.newSessionBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.createNewSession();
            });
        }
    },

    loadSessions: async function() {
        try {
            const response = await fetch('/api/chat/sessions');
            const data = await response.json();
            
            this.renderSessionsList(data.sessions);
        } catch (error) {
            console.error('Error loading sessions:', error);
        }
    },

    renderSessionsList: function(sessions) {
        if (!this.elements.sessionsList) return;
        
        // Clear existing sessions (keep header and new session button)
        const existingSessions = this.elements.sessionsList.querySelectorAll('.session-item');
        existingSessions.forEach(item => item.remove());

        // Add sessions
        sessions.forEach(session => {
            const sessionItem = document.createElement('li');
            sessionItem.className = 'session-item';
            sessionItem.innerHTML = `
                <a class="dropdown-item d-flex justify-content-between align-items-center" href="#" 
                   onclick="ChatPage.switchSession('${session.id}')">
                    <div>
                        <div class="fw-semibold">${session.title}</div>
                        <small class="text-muted">${session.message_count} messages</small>
                    </div>
                    <button class="btn btn-sm btn-outline-danger" onclick="event.stopPropagation(); ChatPage.deleteSession('${session.id}')" 
                            title="Delete session" ${sessions.length <= 1 ? 'disabled' : ''}>
                        <i class="bi bi-trash"></i>
                    </button>
                </a>
            `;
            this.elements.sessionsList.appendChild(sessionItem);
        });

        // Add divider if there are sessions
        if (sessions.length > 0) {
            const divider = document.createElement('li');
            divider.innerHTML = '<hr class="dropdown-divider">';
            this.elements.sessionsList.appendChild(divider);
        }
    },

    createNewSession: async function() {
        const title = prompt('Enter a title for the new chat session (optional):');
        
        try {
            const response = await fetch('/api/chat/sessions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                },
                body: JSON.stringify({ title: title || null })
            });

            if (response.ok) {
                const data = await response.json();
                this.currentSession = data.session;
                
                // Clear current chat
                this.elements.chatMessages.innerHTML = '';
                
                // Reload sessions list
                await this.loadSessions();
                
                Utils.showSuccess('New chat session created!', this.elements.chatMessages);
            } else {
                Utils.showError('Failed to create new session', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error creating session:', error);
            Utils.showError('Failed to create new session', this.elements.chatMessages);
        }
    },

    switchSession: async function(sessionId) {
        try {
            const response = await fetch(`/api/chat/sessions/${sessionId}/switch`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                }
            });

            if (response.ok) {
                const data = await response.json();
                this.currentSession = data.session;
                
                // Clear and reload messages
                this.elements.chatMessages.innerHTML = '';
                data.messages.forEach(msg => {
                    this.addMessage(msg.role, msg.content);
                });
                
                // Apply syntax highlighting
                setTimeout(() => this.applySyntaxHighlighting(), 100);
                
                Utils.showSuccess(`Switched to: ${data.session.title}`, this.elements.chatMessages);
            } else {
                Utils.showError('Failed to switch session', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error switching session:', error);
            Utils.showError('Failed to switch session', this.elements.chatMessages);
        }
    },

    deleteSession: async function(sessionId) {
        if (!confirm('Are you sure you want to delete this chat session? This action cannot be undone.')) {
            return;
        }

        try {
            const response = await fetch(`/api/chat/sessions/${sessionId}`, {
                method: 'DELETE',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                }
            });

            if (response.ok) {
                // Reload sessions
                await this.loadSessions();
                
                // If this was the current session, reload chat history
                if (this.currentSession && this.currentSession.id === sessionId) {
                    await this.loadChatHistory();
                }
                
                Utils.showSuccess('Session deleted successfully', this.elements.chatMessages);
            } else {
                const data = await response.json();
                Utils.showError(data.error || 'Failed to delete session', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error deleting session:', error);
            Utils.showError('Failed to delete session', this.elements.chatMessages);
        }
    },

    setupTextareaAutoResize: function() {
        const textarea = this.elements.messageInput;
        if (!textarea) return;
        
        textarea.style.height = 'auto';
        textarea.style.minHeight = '38px';
        textarea.style.maxHeight = '200px';
        textarea.style.overflowY = 'hidden';
        textarea.style.resize = 'none';

        textarea.addEventListener('input', () => {
            textarea.style.height = 'auto';
            const newHeight = Math.min(textarea.scrollHeight, 200);
            textarea.style.height = newHeight + 'px';
            textarea.style.overflowY = newHeight >= 200 ? 'auto' : 'hidden';
        });

        // Handle paste events to prevent consuming all characters
        textarea.addEventListener('paste', (e) => {
            setTimeout(() => {
                // Trigger resize after paste
                textarea.dispatchEvent(new Event('input'));
            }, 0);
        });
    },
    
    initWebSocket: function() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        ChatApp.ws = new WebSocket(`${protocol}//${window.location.host}/ws`);
        
        ChatApp.ws.onopen = () => {
            console.log('WebSocket connected');
            this.loadChatHistory();
            this.enableInput();
        };
        
        ChatApp.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };
        
        ChatApp.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            Utils.showError('Connection error. Please refresh the page.', this.elements.chatMessages);
        };
        
        ChatApp.ws.onclose = () => {
            console.log('WebSocket disconnected');
            this.disableInput();
            setTimeout(() => this.initWebSocket(), 3000);
        };
    },
    
    handleWebSocketMessage: function(data) {
        switch(data.type) {
            case 'message':
                if (data.role === 'assistant') {
                    this.addMessage(data.role, data.content, data.cached);
                    ChatApp.isWaitingForResponse = false;
                    this.enableInput();
                } else {
                    this.addMessage(data.role, data.content);
                }
                break;
                
            case 'stream':
                if (!ChatApp.currentStreamMessage) {
                    ChatApp.currentStreamMessage = this.addMessage('assistant', '', false, true);
                }
                // For streaming, we need to handle code blocks carefully
                ChatApp.currentStreamMessage.streamContent = (ChatApp.currentStreamMessage.streamContent || '') + data.content;
                this.updateStreamingMessage(ChatApp.currentStreamMessage, ChatApp.currentStreamMessage.streamContent);
                this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
                break;
                
            case 'complete':
                if (ChatApp.currentStreamMessage) {
                    // Final processing of the complete message
                    this.finalizeStreamingMessage(ChatApp.currentStreamMessage);
                }
                ChatApp.currentStreamMessage = null;
                ChatApp.isWaitingForResponse = false;
                this.enableInput();
                break;
                
            case 'typing':
                this.elements.typingIndicator.style.display = data.status === 'start' ? 'block' : 'none';
                break;
                
            case 'error':
                Utils.showError(data.message, this.elements.chatMessages);
                ChatApp.isWaitingForResponse = false;
                this.enableInput();
                break;
        }
    },

    updateStreamingMessage: function(messageElement, content) {
        // For streaming, just show raw content until complete
        const contentDiv = messageElement.querySelector('.message-content') || messageElement;
        contentDiv.textContent = content;
    },

    finalizeStreamingMessage: function(messageElement) {
        // Process the final content with syntax highlighting
        const content = messageElement.streamContent;
        const processedContent = Utils.processMessageContent(content);
        const contentDiv = messageElement.querySelector('.message-content') || messageElement;
        contentDiv.innerHTML = '';
        contentDiv.appendChild(processedContent);
        
        // Apply syntax highlighting
        this.applySyntaxHighlighting();
    },

    applySyntaxHighlighting: function() {
        // Apply Prism.js syntax highlighting
        if (window.Prism) {
            window.Prism.highlightAll();
        }
    },
    
    loadChatHistory: async function() {
        try {
            const response = await fetch('/api/chat/history');
            const data = await response.json();
            
            this.elements.chatMessages.innerHTML = '';
            data.messages.forEach(msg => {
                this.addMessage(msg.role, msg.content);
            });
            
            // Apply syntax highlighting to loaded messages
            setTimeout(() => this.applySyntaxHighlighting(), 100);
        } catch (error) {
            console.error('Error loading chat history:', error);
        }
    },
    
    addMessage: function(role, content, cached = false, streaming = false) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${role === 'user' ? 'user-message' : 'assistant-message'}`;
        if (cached) messageDiv.classList.add('cached');
        
        if (streaming) {
            // For streaming messages, start with simple text content
            const contentDiv = document.createElement('div');
            contentDiv.className = 'message-content';
            messageDiv.appendChild(contentDiv);
            messageDiv.streamContent = '';
        } else {
            // For complete messages, process with syntax highlighting
            const processedContent = Utils.processMessageContent(content);
            messageDiv.appendChild(processedContent);
            
            // Apply syntax highlighting after a short delay
            setTimeout(() => this.applySyntaxHighlighting(), 50);
        }
        
        if (cached && role === 'assistant') {
            const cachedIndicator = document.createElement('div');
            cachedIndicator.className = 'cached-indicator';
            cachedIndicator.innerHTML = '<i class="bi bi-check-circle"></i> Cached response';
            messageDiv.appendChild(cachedIndicator);
        }
        
        this.elements.chatMessages.appendChild(messageDiv);
        this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
        return messageDiv;
    },
    
    sendMessage: function() {
        const message = this.elements.messageInput.value.trim();
        if (message && ChatApp.ws && ChatApp.ws.readyState === WebSocket.OPEN && !ChatApp.isWaitingForResponse) {
            ChatApp.isWaitingForResponse = true;
            this.disableInput();
            
            ChatApp.ws.send(JSON.stringify({
                type: 'chat',
                message: message
            }));
            
            this.elements.messageInput.value = '';
            this.elements.messageInput.style.height = 'auto'; // Reset height
            ChatApp.currentStreamMessage = null;
        }
    },
    
    enableInput: function() {
        this.elements.sendButton.disabled = false;
        this.elements.messageInput.disabled = false;
        this.elements.messageInput.focus();
    },
    
    disableInput: function() {
        this.elements.sendButton.disabled = true;
        this.elements.messageInput.disabled = true;
    }
};

// Admin Page Handler
const AdminPage = {
    elements: {},
    
    init: function() {
        this.elements = {
            userList: document.getElementById('userList'),
            chatHistory: document.getElementById('chatHistory'),
            selectedUserText: document.getElementById('selectedUser')
        };
        
        // Initialize database management if on admin page
        if (typeof AdminDB !== 'undefined') {
            AdminDB.init();
        } else {
            this.loadUsers();
        }
    },
    
    loadUsers: async function() {
        try {
            const response = await fetch('/api/admin/users');
            const data = await response.json();
            
            this.renderUserList(data.users);
        } catch (error) {
            console.error('Error loading users:', error);
            Utils.showError('Failed to load users', this.elements.userList);
        }
    },
    
    renderUserList: function(users) {
        if (!this.elements.userList) return;
        
        this.elements.userList.innerHTML = '';
        
        users.forEach(user => {
            const userDiv = document.createElement('div');
            userDiv.className = 'p-2 mb-2 bg-secondary rounded user-card';
            userDiv.innerHTML = `
                <div class="d-flex justify-content-between align-items-center">
                    <span>${user.username}</span>
                    <span class="badge ${user.is_admin ? 'bg-danger' : 'bg-primary'}">
                        ${user.is_admin ? 'Admin' : 'User'}
                    </span>
                </div>
                <small class="text-muted">
                    Joined: ${Utils.formatDate(user.created_at)}
                    ${user.session_count !== undefined ? `• ${user.session_count} sessions` : ''}
                    ${user.message_count !== undefined ? `• ${user.message_count} messages` : ''}
                </small>
            `;
            userDiv.addEventListener('click', () => this.loadUserChat(user.id, user.username));
            this.elements.userList.appendChild(userDiv);
        });
    },
    
    loadUserChat: async function(userId, username) {
        try {
            this.elements.selectedUserText.textContent = `Chat history for: ${username}`;
            
            const response = await fetch(`/api/admin/chat/${userId}`);
            const data = await response.json();
            
            this.elements.chatHistory.innerHTML = '';
            
            if (data.messages.length === 0) {
                this.elements.chatHistory.innerHTML = '<p class="text-muted text-center">No chat history found</p>';
                return;
            }
            
            data.messages.forEach(msg => {
                const messageDiv = document.createElement('div');
                messageDiv.className = `admin-message ${msg.role === 'user' ? 'admin-user-message' : 'admin-assistant-message'}`;
                
                const processedContent = Utils.processMessageContent(msg.content);
                messageDiv.appendChild(processedContent);
                
                const timestamp = document.createElement('small');
                timestamp.className = 'text-muted message-timestamp';
                timestamp.textContent = Utils.formatDate(msg.timestamp);
                messageDiv.appendChild(timestamp);
                
                this.elements.chatHistory.appendChild(messageDiv);
            });
            
            // Apply syntax highlighting to admin chat
            setTimeout(() => {
                if (window.Prism) {
                    window.Prism.highlightAll();
                }
            }, 100);
            
            this.elements.chatHistory.scrollTop = this.elements.chatHistory.scrollHeight;
        } catch (error) {
            console.error('Error loading chat history:', error);
            Utils.showError('Failed to load chat history', this.elements.chatHistory);
        }
    }
};

// Register Page Handler
const RegisterPage = {
    init: function() {
        const form = document.querySelector('form');
        if (form) {
            form.addEventListener('submit', function(e) {
                const password = document.getElementById('password').value;
                const confirmPassword = document.getElementById('confirm_password').value;
                
                if (password !== confirmPassword) {
                    e.preventDefault();
                    alert('Passwords do not match!');
                }
            });
        }
    }
};