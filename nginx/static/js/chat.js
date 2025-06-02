// static/js/chat.js - Updated with chat management functions

const ChatPage = {
    elements: {},
    ws: null,
    currentStreamMessage: null,
    isWaitingForResponse: false,
    
    init: function() {
        this.elements = {
            chatMessages: document.getElementById('chatMessages'),
            messageInput: document.getElementById('messageInput'),
            sendButton: document.getElementById('sendButton'),
            typingIndicator: document.getElementById('typingIndicator'),
            githubSettingsBtn: document.getElementById('githubSettingsBtn'),
            chatStatsBtn: document.getElementById('chatStatsBtn'),
            exportChatBtn: document.getElementById('exportChatBtn'),
            compressChatBtn: document.getElementById('compressChatBtn'),
            clearChatBtn: document.getElementById('clearChatBtn')
        };
        
        this.bindEvents();
        this.initWebSocket();
        this.setupTextareaAutoResize();
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

        // Chat management buttons
        if (this.elements.chatStatsBtn) {
            this.elements.chatStatsBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.showChatStatistics();
            });
        }

        if (this.elements.exportChatBtn) {
            this.elements.exportChatBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.exportChat();
            });
        }

        if (this.elements.compressChatBtn) {
            this.elements.compressChatBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.showCompressDialog();
            });
        }

        if (this.elements.clearChatBtn) {
            this.elements.clearChatBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.clearChat();
            });
        }

        // Compress chat modal confirm button
        const confirmCompressBtn = document.getElementById('confirmCompressBtn');
        if (confirmCompressBtn) {
            confirmCompressBtn.addEventListener('click', () => this.compressChat());
        }
    },

    showChatStatistics: async function() {
        const modal = new bootstrap.Modal(document.getElementById('chatStatsModal'));
        const contentDiv = document.getElementById('chatStatsContent');
        
        modal.show();
        
        try {
            const response = await fetch('/api/chat/statistics');
            const stats = await response.json();
            
            contentDiv.innerHTML = `
                <div class="row">
                    <div class="col-6">
                        <div class="text-center p-3 border rounded">
                            <h4 class="text-primary">${stats.total_messages}</h4>
                            <small class="text-muted">Total Messages</small>
                        </div>
                    </div>
                    <div class="col-6">
                        <div class="text-center p-3 border rounded">
                            <h4 class="text-info">${stats.user_messages}</h4>
                            <small class="text-muted">Your Messages</small>
                        </div>
                    </div>
                </div>
                <div class="row mt-3">
                    <div class="col-6">
                        <div class="text-center p-3 border rounded">
                            <h4 class="text-success">${stats.assistant_messages}</h4>
                            <small class="text-muted">AI Responses</small>
                        </div>
                    </div>
                    <div class="col-6">
                        <div class="text-center p-3 border rounded">
                            <h6 class="text-warning">
                                ${stats.session_created ? new Date(stats.session_created).toLocaleDateString() : 'N/A'}
                            </h6>
                            <small class="text-muted">Chat Started</small>
                        </div>
                    </div>
                </div>
                ${stats.oldest_message && stats.newest_message ? `
                <div class="mt-3 p-3 border rounded">
                    <small class="text-muted">
                        <i class="bi bi-clock-history"></i> 
                        First message: ${new Date(stats.oldest_message).toLocaleString()}<br>
                        Last message: ${new Date(stats.newest_message).toLocaleString()}
                    </small>
                </div>
                ` : ''}
            `;
        } catch (error) {
            console.error('Error loading statistics:', error);
            contentDiv.innerHTML = `
                <div class="alert alert-danger">
                    <i class="bi bi-exclamation-triangle"></i> Failed to load statistics
                </div>
            `;
        }
    },

    exportChat: async function() {
        try {
            const response = await fetch('/api/chat/export');
            const data = await response.json();
            
            // Create a blob and download
            const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `chat-export-${new Date().toISOString().split('T')[0]}.json`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            
            window.Utils.showSuccess('Chat exported successfully!', this.elements.chatMessages);
        } catch (error) {
            console.error('Error exporting chat:', error);
            window.Utils.showError('Failed to export chat', this.elements.chatMessages);
        }
    },

    showCompressDialog: function() {
        const modal = new bootstrap.Modal(document.getElementById('compressChatModal'));
        modal.show();
    },

    compressChat: async function() {
        const keepCount = parseInt(document.getElementById('keepMessagesCount').value);
        const modal = bootstrap.Modal.getInstance(document.getElementById('compressChatModal'));
        
        try {
            const response = await fetch('/api/chat/compress', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                },
                body: JSON.stringify({ keep_count: keepCount })
            });
            
            const result = await response.json();
            
            if (result.success) {
                modal.hide();
                window.Utils.showSuccess(result.message, this.elements.chatMessages);
                // Reload chat to show compressed history
                await this.loadChatHistory();
            } else {
                window.Utils.showError(result.message || 'Compression failed', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error compressing chat:', error);
            window.Utils.showError('Failed to compress chat', this.elements.chatMessages);
        }
    },

    clearChat: async function() {
        if (!confirm('Are you sure you want to clear all chat messages? This action cannot be undone.')) {
            return;
        }
        
        try {
            const response = await fetch('/api/chat/clear', {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
                }
            });
            
            const result = await response.json();
            
            if (result.success) {
                this.elements.chatMessages.innerHTML = '';
                window.Utils.showSuccess(result.message, this.elements.chatMessages);
            } else {
                window.Utils.showError(result.message || 'Failed to clear chat', this.elements.chatMessages);
            }
        } catch (error) {
            console.error('Error clearing chat:', error);
            window.Utils.showError('Failed to clear chat', this.elements.chatMessages);
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
                textarea.dispatchEvent(new Event('input'));
            }, 0);
        });
    },
    
    initWebSocket: function() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        this.ws = new WebSocket(`${protocol}//${window.location.host}/ws`);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
            this.loadChatHistory();
            this.enableInput();
        };
        
        this.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            window.Utils.showError('Connection error. Please refresh the page.', this.elements.chatMessages);
        };
        
        this.ws.onclose = () => {
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
                    this.isWaitingForResponse = false;
                    this.enableInput();
                } else {
                    this.addMessage(data.role, data.content);
                }
                break;
                
            case 'stream':
                if (!this.currentStreamMessage) {
                    this.currentStreamMessage = this.addMessage('assistant', '', false, true);
                }
                // Accumulate streaming content
                this.currentStreamMessage.streamContent = (this.currentStreamMessage.streamContent || '') + data.content;
                this.updateStreamingMessage(this.currentStreamMessage, this.currentStreamMessage.streamContent);
                this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
                break;
                
            case 'complete':
                if (this.currentStreamMessage) {
                    // Final processing of the complete message
                    this.finalizeStreamingMessage(this.currentStreamMessage);
                }
                this.currentStreamMessage = null;
                this.isWaitingForResponse = false;
                this.enableInput();
                break;
                
            case 'typing':
                this.elements.typingIndicator.style.display = data.status === 'start' ? 'block' : 'none';
                break;
                
            case 'error':
                window.Utils.showError(data.message, this.elements.chatMessages);
                this.isWaitingForResponse = false;
                this.enableInput();
                if (this.currentStreamMessage) {
                    this.currentStreamMessage.remove();
                    this.currentStreamMessage = null;
                }
                break;
        }
    },

    updateStreamingMessage: function(messageElement, content) {
        // Process content in real-time during streaming
        const processedContent = this.processStreamingContent(content);
        const contentDiv = messageElement.querySelector('.message-content') || messageElement;
        contentDiv.innerHTML = '';
        contentDiv.appendChild(processedContent);
        
        // Apply syntax highlighting to any complete code blocks
        this.applySyntaxHighlighting();
    },

    processStreamingContent: function(content) {
        // Process content for streaming - handle partial code blocks
        const container = document.createElement('div');
        container.className = 'message-content';
        
        // Split by code block markers
        const parts = content.split(/(```[\s\S]*?```|```[\s\S]*$)/);
        
        parts.forEach((part, index) => {
            if (part.startsWith('```')) {
                // This is a code block (complete or partial)
                const codeBlockDiv = this.createCodeBlock(part);
                container.appendChild(codeBlockDiv);
            } else if (part) {
                // This is regular text
                const textDiv = document.createElement('div');
                textDiv.className = 'message-text';
                textDiv.textContent = part;
                container.appendChild(textDiv);
            }
        });
        
        return container;
    },

    createCodeBlock: function(codeText) {
        // Handle both complete and partial code blocks
        const isComplete = codeText.endsWith('```');
        const lines = codeText.split('\n');
        const firstLine = lines[0].replace('```', '').trim();
        const language = firstLine || 'text';
        
        // Get code content (skip first line with language)
        const codeContent = lines.slice(1).join('\n');
        const displayCode = isComplete ? codeContent.slice(0, -3) : codeContent; // Remove trailing ```
        
        const container = document.createElement('div');
        container.className = 'code-block-container';
        
        container.innerHTML = `
            <div class="code-block-header">
                <span class="code-language">${language}</span>
                <div class="code-actions">
                    <button class="btn-copy" title="Copy to clipboard">
                        <i class="bi bi-copy"></i>
                    </button>
                    <button class="btn-github" title="Create GitHub Gist" style="display: ${window.GitHubIntegration && window.GitHubIntegration.settings.hasToken ? 'inline-flex' : 'none'}">
                        <i class="bi bi-github"></i>
                    </button>
                </div>
            </div>
            <pre><code class="language-${language}">${this.escapeHtml(displayCode)}</code></pre>
        `;

        // Add copy functionality
        const copyBtn = container.querySelector('.btn-copy');
        copyBtn.addEventListener('click', async () => {
            const success = await window.Utils.copyToClipboard(displayCode);
            if (success) {
                copyBtn.innerHTML = '<i class="bi bi-check"></i>';
                copyBtn.classList.add('copied');
                setTimeout(() => {
                    copyBtn.innerHTML = '<i class="bi bi-copy"></i>';
                    copyBtn.classList.remove('copied');
                }, 2000);
            }
        });

        // Add GitHub Gist functionality
        const githubBtn = container.querySelector('.btn-github');
        if (githubBtn && window.GitHubIntegration) {
            githubBtn.addEventListener('click', async () => {
                const filename = `code.${language}`;
                const result = await window.GitHubIntegration.createGist(filename, displayCode, language);
                if (result.success) {
                    window.Utils.showSuccess('Gist created successfully!', this.elements.chatMessages);
                }
            });
        }

        return container;
    },

    finalizeStreamingMessage: function(messageElement) {
        // Final processing after streaming is complete
        const content = messageElement.streamContent || '';
        const processedContent = this.processMessageContent(content);
        const contentDiv = messageElement.querySelector('.message-content') || messageElement;
        contentDiv.innerHTML = processedContent;
        
        // Apply final syntax highlighting
        this.applySyntaxHighlighting();
        
        // Add copy buttons to code blocks
        this.addCodeBlockButtons(messageElement);
        
        // Clean up streaming data
        delete messageElement.streamContent;
        messageElement.classList.remove('streaming');
    },

    processMessageContent: function(content) {
        // Process markdown-like content
        let processed = content;
        
        // Handle code blocks
        processed = processed.replace(/```(\w+)?\n([\s\S]*?)```/g, (match, lang, code) => {
            const language = lang || 'text';
            const escapedCode = this.escapeHtml(code.trim());
            return `
                <div class="code-block-container">
                    <div class="code-block-header">
                        <span class="code-language">${language}</span>
                        <div class="code-actions">
                            <button class="btn-copy" title="Copy to clipboard">
                                <i class="bi bi-copy"></i>
                            </button>
                            ${window.GitHubIntegration && window.GitHubIntegration.settings.hasToken ? 
                                `<button class="btn-github" title="Create GitHub Gist">
                                    <i class="bi bi-github"></i>
                                </button>` : ''}
                        </div>
                    </div>
                    <pre><code class="language-${language}">${escapedCode}</code></pre>
                </div>
            `;
        });
        
        // Handle inline code
        processed = processed.replace(/`([^`]+)`/g, '<code>\$1</code>');
        
        // Handle bold text
        processed = processed.replace(/\*\*([^*]+)\*\*/g, '<strong>\$1</strong>');
        
        // Handle italic text
        processed = processed.replace(/\*([^*]+)\*/g, '<em>\$1</em>');
        
        // Handle line breaks
        processed = processed.replace(/\n/g, '<br>');
        
        return processed;
    },

    addCodeBlockButtons: function(messageElement) {
        const codeBlocks = messageElement.querySelectorAll('.code-block-container');
        
        codeBlocks.forEach(block => {
            const code = block.querySelector('code').textContent;
            const language = block.querySelector('.code-language').textContent;
            
            // Re-attach copy button event
            const copyBtn = block.querySelector('.btn-copy');
            if (copyBtn && !copyBtn.hasAttribute('data-initialized')) {
                copyBtn.setAttribute('data-initialized', 'true');
                copyBtn.addEventListener('click', async () => {
                    const success = await window.Utils.copyToClipboard(code);
                    if (success) {
                        copyBtn.innerHTML = '<i class="bi bi-check"></i>';
                        copyBtn.classList.add('copied');
                        setTimeout(() => {
                            copyBtn.innerHTML = '<i class="bi bi-copy"></i>';
                            copyBtn.classList.remove('copied');
                        }, 2000);
                    }
                });
            }
            
            // Re-attach GitHub button event
            const githubBtn = block.querySelector('.btn-github');
            if (githubBtn && window.GitHubIntegration && !githubBtn.hasAttribute('data-initialized')) {
                githubBtn.setAttribute('data-initialized', 'true');
                githubBtn.addEventListener('click', async () => {
                    const filename = `code.${language}`;
                    const result = await window.GitHubIntegration.createGist(filename, code, language);
                    if (result.success) {
                        window.Utils.showSuccess('Gist created successfully!', this.elements.chatMessages);
                    }
                });
            }
        });
    },

    applySyntaxHighlighting: function() {
        // Apply syntax highlighting using Prism.js if available
        if (typeof Prism !== 'undefined') {
            Prism.highlightAll();
        }
    },

    escapeHtml: function(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    sendMessage: async function() {
        const message = this.elements.messageInput.value.trim();
        if (!message || this.isWaitingForResponse) return;
        
        // Clear input and disable
        this.elements.messageInput.value = '';
        this.elements.messageInput.style.height = 'auto';
        this.disableInput();
        this.isWaitingForResponse = true;
        
        // Add user message
        this.addMessage('user', message);
        
        // Send via WebSocket
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({
                type: 'message',
                content: message
            }));
        } else {
            window.Utils.showError('Connection lost. Please refresh the page.', this.elements.chatMessages);
            this.enableInput();
            this.isWaitingForResponse = false;
        }
    },

    addMessage: function(role, content, cached = false, isStreaming = false) {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${role}-message ${isStreaming ? 'streaming' : ''}`;
        
        const timestamp = new Date().toLocaleTimeString();
        
        if (role === 'user') {
            messageDiv.innerHTML = `
                <div class="message-header">
                    <span class="message-role">You</span>
                    <span class="message-time">${timestamp}</span>
                </div>
                <div class="message-content">${this.escapeHtml(content)}</div>
            `;
        } else {
            messageDiv.innerHTML = `
                <div class="message-header">
                    <span class="message-role">Assistant</span>
                    ${cached ? '<span class="cached-indicator" title="Cached response"><i class="bi bi-lightning-fill"></i></span>' : ''}
                    <span class="message-time">${timestamp}</span>
                </div>
                <div class="message-content">${isStreaming ? '' : this.processMessageContent(content)}</div>
            `;
        }
        
        this.elements.chatMessages.appendChild(messageDiv);
        this.elements.chatMessages.scrollTop = this.elements.chatMessages.scrollHeight;
        
        return messageDiv;
    },

    loadChatHistory: async function() {
        try {
            const response = await fetch('/api/chat/history');
            const data = await response.json();
            
            if (data.messages && data.messages.length > 0) {
                this.elements.chatMessages.innerHTML = '';
                data.messages.forEach(msg => {
                    this.addMessage(msg.role, msg.content, msg.cached);
                });
            }
        } catch (error) {
            console.error('Error loading chat history:', error);
        }
    },

    enableInput: function() {
        this.elements.messageInput.disabled = false;
        this.elements.sendButton.disabled = false;
        this.elements.messageInput.focus();
    },

    disableInput: function() {
        this.elements.messageInput.disabled = true;
        this.elements.sendButton.disabled = true;
    }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    ChatPage.init();
});

// Export for use in other modules
window.ChatPage = ChatPage;