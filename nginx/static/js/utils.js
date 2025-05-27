// static/js/utils.js - Utility functions

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
                    <button class="btn-github" title="Create GitHub Gist" style="display: ${window.ChatApp && window.ChatApp.githubToken ? 'inline-block' : 'none'}">
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
            if (window.GitHubIntegration) {
                window.GitHubIntegration.createGist(codeBlock.code, codeBlock.language);
            }
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

// Export for use in other modules
window.Utils = Utils;