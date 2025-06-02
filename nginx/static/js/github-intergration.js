// static/js/github-integration.js - Enhanced with full repository reading

const GitHubIntegration = {
    repos: [],
    currentRepo: null,
    settings: {
        token: null,
        username: '',
        hasToken: false
    },
    repoContents: new Map(), // Cache for repository contents
    
    init: function() {
        this.loadSettings();
        this.createSettingsModal();
        this.createRepoModal();
        this.bindEvents();
    },

    bindEvents: function() {
        // Bind GitHub settings button in navbar
        const navBtn = document.getElementById('navGithubSettingsBtn');
        if (navBtn) {
            navBtn.addEventListener('click', () => {
                const modal = new bootstrap.Modal(document.getElementById('githubSettingsModal'));
                modal.show();
            });
        }
    },

    loadSettings: async function() {
        try {
            const response = await fetch('/api/github/settings');
            if (response.ok) {
                const data = await response.json();
                this.settings.username = data.username;
                // Token is stored server-side, we just know if it exists
                this.settings.hasToken = data.has_token;
                
                // Update UI based on token availability
                this.updateGitHubButtons();
            }
        } catch (error) {
            console.error('Failed to load GitHub settings:', error);
        }
    },

    saveSettings: async function(token, username) {
        try {
            const response = await fetch('/api/github/settings', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                },
                body: JSON.stringify({ token, username })
            });
            
            if (response.ok) {
                this.settings.token = token;
                this.settings.username = username;
                this.settings.hasToken = true;
                this.updateGitHubButtons();
                
                if (window.Utils) {
                    window.Utils.showSuccess('GitHub settings saved!', document.querySelector('.chat-messages') || document.body);
                }
                return true;
            } else {
                const error = await response.json();
                throw new Error(error.error || 'Failed to save settings');
            }
        } catch (error) {
            if (window.Utils) {
                window.Utils.showError(error.message, document.querySelector('.chat-messages') || document.body);
            }
            return false;
        }
    },

    updateGitHubButtons: function() {
        // Update GitHub buttons visibility
        document.querySelectorAll('.btn-github').forEach(btn => {
            btn.style.display = this.settings.hasToken ? 'inline-block' : 'none';
        });
        
        // Update browse repos button
        const browseBtn = document.getElementById('browseGithubRepos');
        if (browseBtn) {
            browseBtn.disabled = !this.settings.hasToken;
        }
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
                                       value="">
                                <div class="form-text">
                                    Create a token at: <a href="https://github.com/settings/tokens" target="_blank">GitHub Settings</a>
                                    <br>Required scopes: <code>repo</code> (for private repos) or <code>public_repo</code> (for public only)
                                </div>
                            </div>
                            <div class="mb-3">
                                <label for="githubUsername" class="form-label">Username</label>
                                <input type="text" class="form-control" id="githubUsername" 
                                       placeholder="your-username"
                                       value="${this.settings.username || ''}">
                            </div>
                            <div class="d-grid gap-2">
                                <button type="button" class="btn btn-primary" id="saveGithubSettings">
                                    <i class="bi bi-save"></i> Save Settings
                                </button>
                                <button type="button" class="btn btn-success" id="browseGithubRepos" 
                                        ${this.settings.hasToken ? '' : 'disabled'}>
                                    <i class="bi bi-folder2-open"></i> Browse My Repositories
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        const modalContainer = document.createElement('div');
        modalContainer.innerHTML = modalHtml;
        document.body.appendChild(modalContainer.firstElementChild);

        // Add save functionality
        document.getElementById('saveGithubSettings').addEventListener('click', async () => {
            const token = document.getElementById('githubToken').value.trim();
            const username = document.getElementById('githubUsername').value.trim();
            
            if (token && username) {
                const success = await this.saveSettings(token, username);
                if (success) {
                    document.getElementById('browseGithubRepos').disabled = false;
                    // Store token temporarily for API calls
                    this.settings.token = token;
                }
            } else {
                if (window.Utils) {
                    window.Utils.showError('Both token and username are required', document.querySelector('.chat-messages') || document.body);
                }
            }
        });

        // Add browse repos functionality
        document.getElementById('browseGithubRepos').addEventListener('click', () => {
            bootstrap.Modal.getInstance(document.getElementById('githubSettingsModal')).hide();
            this.showRepoModal();
        });
    },

    createRepoModal: function() {
        if (document.getElementById('githubRepoModal')) {
            return;
        }

        const modalHtml = `
            <div class="modal fade" id="githubRepoModal" tabindex="-1">
                <div class="modal-dialog modal-lg">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h5 class="modal-title">
                                <i class="bi bi-github"></i> Browse GitHub Repositories
                            </h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                        </div>
                        <div class="modal-body">
                            <div class="mb-3">
                                <div class="input-group">
                                    <input type="text" class="form-control" id="repoSearch" 
                                           placeholder="Search repositories...">
                                    <button class="btn btn-outline-secondary" id="refreshRepos">
                                        <i class="bi bi-arrow-clockwise"></i> Refresh
                                    </button>
                                </div>
                            </div>
                            <div id="repoList" class="repo-list">
                                <div class="text-center">
                                    <div class="spinner-border text-primary" role="status">
                                        <span class="visually-hidden">Loading...</span>
                                    </div>
                                    <p class="mt-2">Loading repositories...</p>
                                </div>
                            </div>
                            <div id="repoContents" class="repo-contents d-none">
                                <nav aria-label="breadcrumb">
                                    <ol class="breadcrumb" id="repoBreadcrumb">
                                        <li class="breadcrumb-item"><a href="#" onclick="GitHubIntegration.showRepos()">Repositories</a></li>
                                    </ol>
                                </nav>
                                <div id="fileList" class="file-list"></div>
                            </div>
                            <div id="repoReadProgress" class="mt-3 d-none">
                                <div class="progress">
                                    <div class="progress-bar progress-bar-striped progress-bar-animated" 
                                         role="progressbar" id="readProgressBar" 
                                         style="width: 0%">0%</div>
                                </div>
                                <small class="text-muted" id="readProgressText">Preparing to read repository...</small>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        const modalContainer = document.createElement('div');
        modalContainer.innerHTML = modalHtml;
        document.body.appendChild(modalContainer.firstElementChild);

        // Add event listeners
        document.getElementById('refreshRepos').addEventListener('click', () => this.fetchRepos());
        document.getElementById('repoSearch').addEventListener('input', (e) => this.filterRepos(e.target.value));
    },

    showRepoModal: async function() {
        const modal = new bootstrap.Modal(document.getElementById('githubRepoModal'));
        modal.show();
        await this.fetchRepos();
    },

    fetchRepos: async function() {
        if (!this.settings.token) {
            this.showError('GitHub token not configured');
            return;
        }

        const repoList = document.getElementById('repoList');
        repoList.innerHTML = `
            <div class="text-center">
                <div class="spinner-border text-primary" role="status">
                    <span class="visually-hidden">Loading...</span>
                </div>
                <p class="mt-2">Loading repositories...</p>
            </div>
        `;

        try {
            const response = await fetch('https://api.github.com/user/repos?per_page=100&sort=updated', {
                headers: {
                    'Authorization': `token ${this.settings.token}`,
                    'Accept': 'application/vnd.github.v3+json'
                }
            });

            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status}`);
            }

            this.repos = await response.json();
            this.displayRepos();
        } catch (error) {
            console.error('Error fetching repos:', error);
            repoList.innerHTML = `
                <div class="alert alert-danger">
                    <i class="bi bi-exclamation-triangle"></i> Failed to fetch repositories: ${error.message}
                </div>
            `;
        }
    },

    displayRepos: function() {
        const repoList = document.getElementById('repoList');
        
        if (this.repos.length === 0) {
            repoList.innerHTML = '<p class="text-muted text-center">No repositories found</p>';
            return;
        }

        repoList.innerHTML = this.repos.map(repo => `
            <div class="repo-item" onclick="GitHubIntegration.browseRepo('${repo.full_name}')">
                <div class="d-flex justify-content-between align-items-start">
                    <div>
                        <h6 class="mb-1">
                            <i class="bi bi-${repo.private ? 'lock' : 'unlock'}"></i>
                            ${repo.name}
                        </h6>
                        <p class="text-muted small mb-1">${repo.description || 'No description'}</p>
                        <div class="repo-meta">
                            <span class="badge bg-secondary">${repo.language || 'Unknown'}</span>
                            <span class="text-muted small">Updated: ${new Date(repo.updated_at).toLocaleDateString()}</span>
                        </div>
                    </div>
                    <div class="btn-group" role="group">
                        <button class="btn btn-sm btn-primary" onclick="event.stopPropagation(); GitHubIntegration.loadSingleFile('${repo.full_name}')" title="Load single file">
                            <i class="bi bi-file-earmark-arrow-down"></i>
                        </button>
                        <button class="btn btn-sm btn-success" onclick="event.stopPropagation(); GitHubIntegration.readEntireRepo('${repo.full_name}')" title="Read entire repository">
                            <i class="bi bi-folder-plus"></i> Read All
                        </button>
                    </div>
                </div>
            </div>
        `).join('');
    },

    filterRepos: function(searchTerm) {
        const filtered = this.repos.filter(repo => 
            repo.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
            (repo.description && repo.description.toLowerCase().includes(searchTerm.toLowerCase()))
        );
        
        this.displayFilteredRepos(filtered);
    },

    displayFilteredRepos: function(repos) {
        const repoList = document.getElementById('repoList');
        
        if (repos.length === 0) {
            repoList.innerHTML = '<p class="text-muted text-center">No repositories match your search</p>';
            return;
        }

        repoList.innerHTML = repos.map(repo => `
            <div class="repo-item" onclick="GitHubIntegration.browseRepo('${repo.full_name}')">
                <div class="d-flex justify-content-between align-items-start">
                    <div>
                        <h6 class="mb-1">
                            <i class="bi bi-${repo.private ? 'lock' : 'unlock'}"></i>
                            ${repo.name}
                        </h6>
                        <p class="text-muted small mb-1">${repo.description || 'No description'}</p>
                        <div class="repo-meta">
                            <span class="badge bg-secondary">${repo.language || 'Unknown'}</span>
                            <span class="text-muted small">Updated: ${new Date(repo.updated_at).toLocaleDateString()}</span>
                        </div>
                    </div>
                    <div class="btn-group" role="group">
                        <button class="btn btn-sm btn-primary" onclick="event.stopPropagation(); GitHubIntegration.loadSingleFile('${repo.full_name}')" title="Load single file">
                            <i class="bi bi-file-earmark-arrow-down"></i>
                        </button>
                        <button class="btn btn-sm btn-success" onclick="event.stopPropagation(); GitHubIntegration.readEntireRepo('${repo.full_name}')" title="Read entire repository">
                            <i class="bi bi-folder-plus"></i> Read All
                        </button>
                    </div>
                </div>
            </div>
        `).join('');
    },

    browseRepo: async function(repoFullName, path = '') {
        this.currentRepo = repoFullName;
        
        // Hide repo list, show contents
        document.getElementById('repoList').classList.add('d-none');
        document.getElementById('repoContents').classList.remove('d-none');
        
        // Update breadcrumb
        this.updateBreadcrumb(path);
        
        const fileList = document.getElementById('fileList');
        fileList.innerHTML = `
            <div class="text-center">
                <div class="spinner-border text-primary" role="status">
                    <span class="visually-hidden">Loading...</span>
                </div>
            </div>
        `;

        try {
            const url = `https://api.github.com/repos/${repoFullName}/contents/${path}`;
            const response = await fetch(url, {
                headers: {
                    'Authorization': `token ${this.settings.token}`,
                    'Accept': 'application/vnd.github.v3+json'
                }
            });

            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status}`);
            }

            const contents = await response.json();
            this.displayContents(contents, path);
        } catch (error) {
            console.error('Error browsing repo:', error);
            fileList.innerHTML = `
                <div class="alert alert-danger">
                    <i class="bi bi-exclamation-triangle"></i> Failed to load repository contents: ${error.message}
                </div>
            `;
        }
    },

    displayContents: function(contents, currentPath) {
        const fileList = document.getElementById('fileList');
        
        // Sort: directories first, then files
        contents.sort((a, b) => {
            if (a.type === 'dir' && b.type !== 'dir') return -1;
            if (a.type !== 'dir' && b.type === 'dir') return 1;
            return a.name.localeCompare(b.name);
        });

        // Add "Read All Files in This Directory" button if not in root
        const readAllButton = currentPath ? `
            <div class="mb-3">
                <button class="btn btn-success btn-sm" onclick="GitHubIntegration.readDirectoryFiles('${this.currentRepo}', '${currentPath}')">
                    <i class="bi bi-folder-plus"></i> Read All Files in This Directory
                </button>
            </div>
        ` : '';

        fileList.innerHTML = readAllButton + contents.map(item => {
            const icon = item.type === 'dir' ? 'folder-fill' : this.getFileIcon(item.name);
            const onclick = item.type === 'dir' 
                ? `GitHubIntegration.browseRepo('${this.currentRepo}', '${item.path}')`
                : `GitHubIntegration.loadFile('${item.download_url}', '${item.name}', '${item.path}')`;
            
            return `
                <div class="file-item" onclick="${onclick}">
                    <i class="bi bi-${icon}"></i>
                    <span>${item.name}</span>
                    ${item.type === 'file' ? `<small class="text-muted">${this.formatFileSize(item.size)}</small>` : ''}
                </div>
            `;
        }).join('');
    },

    updateBreadcrumb: function(path) {
        const breadcrumb = document.getElementById('repoBreadcrumb');
        const parts = path ? path.split('/') : [];
        
        let html = '<li class="breadcrumb-item"><a href="#" onclick="GitHubIntegration.showRepos()">Repositories</a></li>';
        html += `<li class="breadcrumb-item"><a href="#" onclick="GitHubIntegration.browseRepo('${this.currentRepo}', '')">${this.currentRepo.split('/')[1]}</a></li>`;
        
        let currentPath = '';
        parts.forEach((part, index) => {
            currentPath += (index > 0 ? '/' : '') + part;
            if (index === parts.length - 1) {
                html += `<li class="breadcrumb-item active">${part}</li>`;
            } else {
                html += `<li class="breadcrumb-item"><a href="#" onclick="GitHubIntegration.browseRepo('${this.currentRepo}', '${currentPath}')">${part}</a></li>`;
            }
        });
        
        breadcrumb.innerHTML = html;
    },

    showRepos: function() {
        document.getElementById('repoList').classList.remove('d-none');
        document.getElementById('repoContents').classList.add('d-none');
        document.getElementById('repoReadProgress').classList.add('d-none');
        this.displayRepos();
    },

    loadSingleFile: async function(repoFullName) {
        // Show file browser for single file selection
        this.currentRepo = repoFullName;
        await this.browseRepo(repoFullName);
    },

    loadFile: async function(downloadUrl, fileName, filePath) {
        try {
            const response = await fetch(downloadUrl);
            if (!response.ok) {
                throw new Error(`Failed to fetch file: ${response.status}`);
            }
            
            const content = await response.text();
            
            // Close the modal
            bootstrap.Modal.getInstance(document.getElementById('githubRepoModal')).hide();
            
            // Insert into chat
            this.insertFileIntoChat(fileName, filePath, content);
        } catch (error) {
            console.error('Error loading file:', error);
            alert(`Failed to load file: ${error.message}`);
        }
    },

    readEntireRepo: async function(repoFullName) {
        if (!confirm(`This will read all files from the repository "${repoFullName}". This may take some time for large repositories. Continue?`)) {
            return;
        }

        // Show progress
        document.getElementById('repoReadProgress').classList.remove('d-none');
        
        try {
            const files = await this.getAllRepoFiles(repoFullName);
            
            if (files.length === 0) {
                alert('No files found in the repository.');
                return;
            }

            // Close modal
            bootstrap.Modal.getInstance(document.getElementById('githubRepoModal')).hide();
            
            // Create a summary of all files
            const repoContent = await this.createRepoSummary(repoFullName, files);
            this.insertRepoIntoChat(repoFullName, repoContent);
            
        } catch (error) {
            console.error('Error reading repository:', error);
            alert(`Failed to read repository: ${error.message}`);
        } finally {
            document.getElementById('repoReadProgress').classList.add('d-none');
        }
    },

    readDirectoryFiles: async function(repoFullName, directory) {
        if (!confirm(`This will read all files from the directory "${directory}". Continue?`)) {
            return;
        }

        // Show progress
        document.getElementById('repoReadProgress').classList.remove('d-none');
        
        try {
            const files = await this.getDirectoryFiles(repoFullName, directory);
            
            if (files.length === 0) {
                alert('No files found in the directory.');
                return;
            }

            // Close modal
            bootstrap.Modal.getInstance(document.getElementById('githubRepoModal')).hide();
            
            // Create a summary of directory files
            const dirContent = await this.createDirectorySummary(repoFullName, directory, files);
            this.insertDirectoryIntoChat(directory, dirContent);
            
        } catch (error) {
            console.error('Error reading directory:', error);
            alert(`Failed to read directory: ${error.message}`);
        } finally {
            document.getElementById('repoReadProgress').classList.add('d-none');
        }
    },

    getAllRepoFiles: async function(repoFullName, path = '', allFiles = []) {
        const url = `https://api.github.com/repos/${repoFullName}/contents/${path}`;
        
        try {
            const response = await fetch(url, {
                headers: {
                    'Authorization': `token ${this.settings.token}`,
                    'Accept': 'application/vnd.github.v3+json'
                }
            });

            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status}`);
            }

            const contents = await response.json();
            
            for (const item of contents) {
                if (item.type === 'file' && this.isReadableFile(item.name)) {
                    allFiles.push({
                        path: item.path,
                        name: item.name,
                        size: item.size,
                        download_url: item.download_url
                    });
                    
                    // Update progress
                    this.updateReadProgress(allFiles.length, `Found ${allFiles.length} files...`);
                } else if (item.type === 'dir' && !this.isIgnoredDirectory(item.name)) {
                    // Recursively get files from subdirectories
                    await this.getAllRepoFiles(repoFullName, item.path, allFiles);
                }
            }
            
            return allFiles;
        } catch (error) {
            console.error(`Error fetching contents at ${path}:`, error);
            return allFiles;
        }
    },

    getDirectoryFiles: async function(repoFullName, directory) {
        const url = `https://api.github.com/repos/${repoFullName}/contents/${directory}`;
        const files = [];
        
        try {
            const response = await fetch(url, {
                headers: {
                    'Authorization': `token ${this.settings.token}`,
                    'Accept': 'application/vnd.github.v3+json'
                }
            });

            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status}`);
            }

            const contents = await response.json();
            
            for (const item of contents) {
                if (item.type === 'file' && this.isReadableFile(item.name)) {
                    files.push({
                        path: item.path,
                        name: item.name,
                        size: item.size,
                        download_url: item.download_url
                    });
                    
                    // Update progress
                    this.updateReadProgress(files.length, `Found ${files.length} files...`);
                }
            }
            
            return files;
        } catch (error) {
            console.error(`Error fetching directory contents:`, error);
            return files;
        }
    },

    createRepoSummary: async function(repoFullName, files) {
        let summary = `# Repository: ${repoFullName}\n\n`;
        summary += `Total files: ${files.length}\n\n`;
        summary += `## File Structure\n\n`;
        
        // Group files by directory
        const fileTree = {};
        files.forEach(file => {
            const parts = file.path.split('/');
            const dir = parts.length > 1 ? parts.slice(0, -1).join('/') : '/';
            if (!fileTree[dir]) fileTree[dir] = [];
            fileTree[dir].push(file);
        });
        
        // Create tree structure
        for (const [dir, dirFiles] of Object.entries(fileTree)) {
            summary += `### ${dir === '/' ? 'Root' : dir}\n`;
            dirFiles.forEach(file => {
                summary += `- ${file.name} (${this.formatFileSize(file.size)})\n`;
            });
            summary += '\n';
        }
        
        summary += `\n## File Contents\n\n`;
        
        // Read and add file contents
        let processedFiles = 0;
        for (const file of files) {
            try {
                this.updateReadProgress(
                    Math.round((processedFiles / files.length) * 100),
                    `Reading ${file.name}...`
                );
                
                const response = await fetch(file.download_url);
                if (response.ok) {
                    const content = await response.text();
                    const lang = this.getFileExtension(file.name);
                    
                    summary += `### File: ${file.path}\n\n`;
                    summary += `\`\`\`${lang}\n${content}\n\`\`\`\n\n`;
                }
                
                processedFiles++;
            } catch (error) {
                console.error(`Error reading file ${file.path}:`, error);
                summary += `### File: ${file.path}\n\n`;
                summary += `*Error reading file: ${error.message}*\n\n`;
            }
        }
        
        return summary;
    },

    createDirectorySummary: async function(repoFullName, directory, files) {
        let summary = `# Directory: ${directory} (from ${repoFullName})\n\n`;
        summary += `Total files: ${files.length}\n\n`;
        summary += `## Files\n\n`;
        
        files.forEach(file => {
            summary += `- ${file.name} (${this.formatFileSize(file.size)})\n`;
        });
        
        summary += `\n## File Contents\n\n`;
        
        // Read and add file contents
        let processedFiles = 0;
        for (const file of files) {
            try {
                this.updateReadProgress(
                    Math.round((processedFiles / files.length) * 100),
                    `Reading ${file.name}...`
                );
                
                const response = await fetch(file.download_url);
                if (response.ok) {
                    const content = await response.text();
                    const lang = this.getFileExtension(file.name);
                    
                    summary += `### File: ${file.path}\n\n`;
                    summary += `\`\`\`${lang}\n${content}\n\`\`\`\n\n`;
                }
                
                processedFiles++;
            } catch (error) {
                console.error(`Error reading file ${file.path}:`, error);
                summary += `### File: ${file.path}\n\n`;
                summary += `*Error reading file: ${error.message}*\n\n`;
            }
        }
        
        return summary;
    },

    updateReadProgress: function(percent, message) {
        const progressBar = document.getElementById('readProgressBar');
        const progressText = document.getElementById('readProgressText');
        
        if (progressBar) {
            progressBar.style.width = `${percent}%`;
            progressBar.textContent = `${percent}%`;
        }
        
        if (progressText) {
            progressText.textContent = message;
        }
    },

    isReadableFile: function(filename) {
        const readableExtensions = [
            '.js', '.ts', '.jsx', '.tsx', '.py', '.java', '.cpp', '.c', '.h', '.cs',
            '.php', '.rb', '.go', '.rs', '.kt', '.swift', '.m', '.scala', '.r',
            '.html', '.css', '.scss', '.less', '.sass',
            '.json', '.xml', '.yaml', '.yml', '.toml', '.ini', '.conf', '.config',
            '.md', '.txt', '.rst', '.tex', '.log',
            '.sh', '.bash', '.zsh', '.fish', '.ps1', '.bat', '.cmd',
            '.sql', '.graphql', '.proto',
            '.dockerfile', '.docker-compose.yml', '.env', '.env.example',
            '.gitignore', '.gitattributes', '.editorconfig',
            'Makefile', 'Rakefile', 'Gemfile', 'Pipfile', 'requirements.txt',
            'package.json', 'package-lock.json', 'yarn.lock', 'composer.json',
            'pom.xml', 'build.gradle', 'build.sbt', 'Cargo.toml'
        ];
        
        const lowerName = filename.toLowerCase();
        return readableExtensions.some(ext => lowerName.endsWith(ext)) ||
               lowerName === 'readme' || lowerName === 'license' || lowerName === 'changelog' ||
               !lowerName.includes('.');
    },

    isIgnoredDirectory: function(dirname) {
        const ignoredDirs = [
            'node_modules', '.git', '.svn', '.hg', 'vendor', 'venv', 'env',
            '__pycache__', '.pytest_cache', '.idea', '.vscode', '.vs',
            'bin', 'obj', 'dist', 'build', 'out', 'target', '.next',
            '.nuxt', 'coverage', '.nyc_output', 'bower_components'
        ];
        
        return ignoredDirs.includes(dirname.toLowerCase());
    },

    insertFileIntoChat: function(fileName, filePath, content) {
        if (!window.ChatPage) {
            console.error('Chat page not initialized');
            return;
        }
        
        const messageInput = document.getElementById('messageInput');
        if (!messageInput) return;
        
        // Format the file content for chat
        const formattedContent = `I'd like to discuss this file from my GitHub repository:\n\n**File:** ${filePath}\n\`\`\`${this.getFileExtension(fileName)}\n${content}\n\`\`\`\n\nCan you help me with this?`;
        
        messageInput.value = formattedContent;
        messageInput.style.height = 'auto';
        messageInput.style.height = Math.min(messageInput.scrollHeight, 200) + 'px';
        messageInput.focus();
        
        // Show success message
        if (window.Utils) {
            window.Utils.showSuccess(`Loaded ${fileName} into chat`, document.querySelector('.chat-messages'));
        }
    },

    insertRepoIntoChat: function(repoName, content) {
        if (!window.ChatPage) {
            console.error('Chat page not initialized');
            return;
        }
        
        const messageInput = document.getElementById('messageInput');
        if (!messageInput) return;
        
        // Format the repo content for chat
        const formattedContent = `I've loaded the entire repository "${repoName}" for analysis. Here's the complete structure and contents:\n\n${content}\n\nPlease analyze this repository and provide insights about its structure, purpose, and any improvements you might suggest.`;
        
        messageInput.value = formattedContent;
        messageInput.style.height = 'auto';
        messageInput.style.height = Math.min(messageInput.scrollHeight, 200) + 'px';
        messageInput.focus();
        
        // Show success message
        if (window.Utils) {
            window.Utils.showSuccess(`Loaded entire repository ${repoName} into chat`, document.querySelector('.chat-messages'));
        }
    },

    insertDirectoryIntoChat: function(directory, content) {
        if (!window.ChatPage) {
            console.error('Chat page not initialized');
            return;
        }
        
        const messageInput = document.getElementById('messageInput');
        if (!messageInput) return;
        
        // Format the directory content for chat
        const formattedContent = `I've loaded all files from the directory "${directory}". Here are the contents:\n\n${content}\n\nPlease analyze these files and provide any insights or suggestions.`;
        
        messageInput.value = formattedContent;
        messageInput.style.height = 'auto';
        messageInput.style.height = Math.min(messageInput.scrollHeight, 200) + 'px';
        messageInput.focus();
        
        // Show success message
        if (window.Utils) {
            window.Utils.showSuccess(`Loaded directory ${directory} into chat`, document.querySelector('.chat-messages'));
        }
    },

    getFileIcon: function(fileName) {
        const ext = fileName.split('.').pop().toLowerCase();
        const iconMap = {
            'js': 'file-earmark-code',
            'ts': 'file-earmark-code',
            'py': 'file-earmark-code',
            'java': 'file-earmark-code',
            'cpp': 'file-earmark-code',
            'c': 'file-earmark-code',
            'h': 'file-earmark-code',
            'css': 'file-earmark-code',
            'html': 'file-earmark-code',
            'json': 'file-earmark-code',
            'xml': 'file-earmark-code',
            'md': 'file-earmark-text',
            'txt': 'file-earmark-text',
            'pdf': 'file-earmark-pdf',
            'jpg': 'file-earmark-image',
            'jpeg': 'file-earmark-image',
            'png': 'file-earmark-image',
            'gif': 'file-earmark-image',
            'svg': 'file-earmark-image',
            'zip': 'file-earmark-zip',
            'rar': 'file-earmark-zip',
            'tar': 'file-earmark-zip',
            'gz': 'file-earmark-zip'
        };
        return iconMap[ext] || 'file-earmark';
    },

    formatFileSize: function(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    },

    getFileExtension: function(filename) {
        const ext = filename.split('.').pop().toLowerCase();
        return this.getFileExtensionMapping()[ext] || 'text';
    },

    getFileExtensionMapping: function() {
        return {
            'js': 'javascript',
            'ts': 'typescript',
            'py': 'python',
            'java': 'java',
            'cpp': 'cpp',
            'c': 'c',
            'cs': 'csharp',
            'php': 'php',
            'rb': 'ruby',
            'go': 'go',
            'rs': 'rust',
            'kt': 'kotlin',
            'swift': 'swift',
            'html': 'html',
            'css': 'css',
            'scss': 'scss',
            'less': 'less',
            'json': 'json',
            'xml': 'xml',
            'yaml': 'yaml',
            'yml': 'yaml',
            'md': 'markdown',
            'sql': 'sql',
            'sh': 'bash',
            'bash': 'bash',
            'ps1': 'powershell',
            'dockerfile': 'dockerfile',
            'conf': 'nginx',
            'txt': 'text'
        };
    },

    createGist: async function(code, language) {
        if (!this.settings.token) {
            const modal = new bootstrap.Modal(document.getElementById('githubSettingsModal'));
            modal.show();
            return;
        }

        try {
            const filename = `code.${this.getFileExtensionFromLanguage(language)}`;
            const response = await fetch('https://api.github.com/gists', {
                method: 'POST',
                headers: {
                    'Authorization': `token ${this.settings.token}`,
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

    getFileExtensionFromLanguage: function(language) {
        const mapping = this.getFileExtensionMapping();
        const reverseMapping = {};
        for (const [ext, lang] of Object.entries(mapping)) {
            reverseMapping[lang] = ext;
        }
        return reverseMapping[language.toLowerCase()] || 'txt';
    },

    showError: function(message) {
        const repoList = document.getElementById('repoList');
        if (repoList) {
            repoList.innerHTML = `
                <div class="alert alert-danger">
                    <i class="bi bi-exclamation-triangle"></i> ${message}
                </div>
            `;
        }
    }
};

// Export for use in other modules
window.GitHubIntegration = GitHubIntegration;