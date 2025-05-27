// static/js/github-integration.js - GitHub Integration Module

const GitHubIntegration = {
    init: function() {
        this.loadSettings();
        this.createSettingsModal();
    },

    loadSettings: function() {
        if (window.ChatApp) {
            window.ChatApp.githubToken = localStorage.getItem('github_token') || null;
            window.ChatApp.githubUsername = localStorage.getItem('github_username') || null;
        }
    },

    saveSettings: function(token, username) {
        localStorage.setItem('github_token', token);
        localStorage.setItem('github_username', username);
        if (window.ChatApp) {
            window.ChatApp.githubToken = token;
            window.ChatApp.githubUsername = username;
        }
        
        // Update GitHub buttons visibility
        document.querySelectorAll('.btn-github').forEach(btn => {
            btn.style.display = token ? 'inline-block' : 'none';
        });
    },

    createSettingsModal: function() {
        // Check if modal already exists
        if (document.getElementById('githubSettingsModal')) {
            return;
        }
        
        const modalHtml = `
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
                                       value="${window.ChatApp?.githubToken || ''}">
                                <div class="form-text">
                                    Create a token at: <a href="https://github.com/settings/tokens" target="_blank">GitHub Settings</a>
                                    <br>Required scopes: <code>gist</code>
                                </div>
                            </div>
                            <div class="mb-3">
                                <label for="githubUsername" class="form-label">Username</label>
                                <input type="text" class="form-control" id="githubUsername" 
                                       placeholder="your-username"
                                       value="${window.ChatApp?.githubUsername || ''}">
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
        
        const modalContainer = document.createElement('div');
        modalContainer.innerHTML = modalHtml;
        document.body.appendChild(modalContainer.firstElementChild);

        // Add save functionality
        document.getElementById('saveGithubSettings').addEventListener('click', () => {
            const token = document.getElementById('githubToken').value.trim();
            const username = document.getElementById('githubUsername').value.trim();
            
            if (token && username) {
                this.saveSettings(token, username);
                bootstrap.Modal.getInstance(document.getElementById('githubSettingsModal')).hide();
                if (window.Utils) {
                    window.Utils.showSuccess('GitHub settings saved!', document.querySelector('.chat-messages') || document.body);
                }
            }
        });
    },

    createGist: async function(code, language) {
        if (!window.ChatApp?.githubToken) {
            const modal = new bootstrap.Modal(document.getElementById('githubSettingsModal'));
            modal.show();
            return;
        }

        try {
            const filename = `code.${this.getFileExtension(language)}`;
            const response = await fetch('https://api.github.com/gists', {
                method: 'POST',
                headers: {
                    'Authorization': `token ${window.ChatApp.githubToken}`,
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
                if (window.Utils) {
                    window.Utils.showSuccess('Gist created successfully!', document.querySelector('.chat-messages') || document.body);
                }
            } else {
                throw new Error(`GitHub API error: ${response.status}`);
            }
        } catch (error) {
            console.error('GitHub gist creation failed:', error);
            if (window.Utils) {
                window.Utils.showError('Failed to create GitHub gist. Check your token and try again.', document.querySelector('.chat-messages') || document.body);
            }
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

// Export for use in other modules
window.GitHubIntegration = GitHubIntegration;