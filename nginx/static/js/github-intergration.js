// GitHub Integration
const GitHubIntegration = {
    isConnected: false,
    selectedFiles: [],
    
    init: function() {
        this.bindEvents();
        this.checkConnection();
    },
    
    bindEvents: function() {
        const connectBtn = document.getElementById('githubConnectBtn');
        const connectModalBtn = document.getElementById('connectGithubBtn');
        
        if (connectBtn) {
            connectBtn.addEventListener('click', () => {
                if (this.isConnected) {
                    this.showRepoSelector();
                } else {
                    const modal = new bootstrap.Modal(document.getElementById('githubConnectModal'));
                    modal.show();
                }
            });
        }
        
        if (connectModalBtn) {
            connectModalBtn.addEventListener('click', () => this.connect());
        }
    },
    
    async checkConnection() {
        try {
            const response = await fetch('/api/github/status');
            const data = await response.json();
            
            if (data.connected) {
                this.isConnected = true;
                this.updateConnectButton(data.username);
            }
        } catch (error) {
            console.error('Error checking GitHub connection:', error);
        }
    },
    
    async connect() {
        const token = document.getElementById('githubToken').value;
        if (!token) return;
        
        try {
            const response = await fetch('/api/github/connect', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ token })
            });
            
            const data = await response.json();
            
            if (data.success) {
                this.isConnected = true;
                this.updateConnectButton(data.username);
                bootstrap.Modal.getInstance(document.getElementById('githubConnectModal')).hide();
                document.getElementById('githubToken').value = '';
                this.loadRepos();
            } else {
                alert('Failed to connect: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            console.error('Error connecting to GitHub:', error);
            alert('Failed to connect to GitHub');
        }
    },
    
    updateConnectButton(username) {
        const btn = document.getElementById('githubConnectBtn');
        if (btn) {
            btn.innerHTML = `<i class="bi bi-github"></i> ${username}`;
            btn.classList.remove('btn-outline-primary');
            btn.classList.add('btn-success');
        }
    },
    
    async loadRepos() {
        try {
            const response = await fetch('/api/github/repos');
            const data = await response.json();
            
            const reposList = document.getElementById('reposList');
            const githubRepos = document.getElementById('githubRepos');
            
            if (data.repos && data.repos.length > 0) {
                githubRepos.style.display = 'block';
                reposList.innerHTML = data.repos.map(repo => `
                    <div class="repo-item" data-repo="${repo.name}">
                        <i class="bi bi-folder"></i> ${repo.name}
                    </div>
                `).join('');
                
                // Add click handlers
                document.querySelectorAll('.repo-item').forEach(item => {
                    item.addEventListener('click', () => this.loadRepoFiles(item.dataset.repo));
                });
            }
        } catch (error) {
            console.error('Error loading repos:', error);
        }
    },
    
    async loadRepoFiles(repoPath, path = '') {
        try {
            const response = await fetch(`/api/github/repo/${repoPath}/files?path=${path}`);
            const data = await response.json();
            
            // Show file selector modal
            this.showFileSelector(repoPath, data.files);
        } catch (error) {
            console.error('Error loading files:', error);
        }
    },
    
    showFileSelector(repoPath, files) {
        // Create and show a modal with file selection
        // This would allow users to select files to include in the chat context
        // Implementation depends on your UI preferences
    },
    
    async addFileToContext(repoPath, filePath) {
        try {
            const response = await fetch(`/api/github/repo/${repoPath}/file?path=${filePath}`);
            const data = await response.json();
            
            // Send file content to chat
            if (window.ChatPage && window.ChatPage.ws) {
                window.ChatPage.ws.send(JSON.stringify({
                    type: 'github_file',
                    repo: repoPath,
                    path: filePath,
                    content: data.content
                }));
            }
        } catch (error) {
            console.error('Error loading file:', error);
        }
    }
};

// Initialize on load
document.addEventListener('DOMContentLoaded', () => {
    GitHubIntegration.init();
});

window.GitHubIntegration = GitHubIntegration;