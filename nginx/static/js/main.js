/* File: main.js
   Directory: /deepseek-coder-setup/web-ui/static/js/ */

document.addEventListener('DOMContentLoaded', function() {
    // Initialize UI elements
    initDropdowns();
    initThemeToggle();
    initInputExpansion();
    initCopyToClipboard();
    initSyntaxHighlighting();
    
    // Handle page-specific initializations
    if (document.querySelector('.chat-input')) {
        initChat();
    }
    
    if (document.querySelector('.chat-title-edit')) {
        initChatTitleEditor();
    }
    
    if (document.querySelector('.artifact-download-btn')) {
        initArtifactDownload();
    }
});

// Initialize dropdown menus
function initDropdowns() {
    const dropdownTriggers = document.querySelectorAll('.dropdown-trigger');
    
    dropdownTriggers.forEach(trigger => {
        const dropdown = trigger.nextElementSibling;
        
        // Show dropdown on click
        trigger.addEventListener('click', (e) => {
            e.stopPropagation();
            dropdown.classList.toggle('show');
        });
        
        // Close dropdown when clicking outside
        document.addEventListener('click', () => {
            dropdown.classList.remove('show');
        });
        
        // Prevent closing dropdown when clicking inside it
        dropdown.addEventListener('click', (e) => {
            e.stopPropagation();
        });
    });
}

// Theme toggle
function initThemeToggle() {
    const themeToggle = document.querySelector('.theme-toggle');
    
    if (themeToggle) {
        themeToggle.addEventListener('click', () => {
            document.body.classList.toggle('light-theme');
            
            // Save preference to localStorage
            const isDarkTheme = !document.body.classList.contains('light-theme');
            localStorage.setItem('darkTheme', isDarkTheme);
        });
        
        // Load saved theme preference
        const isDarkTheme = localStorage.getItem('darkTheme') !== 'false';
        document.body.classList.toggle('light-theme', !isDarkTheme);
    }
}

// Auto-expand text areas
function initInputExpansion() {
    const autoExpandTextareas = document.querySelectorAll('textarea.auto-expand');
    
    autoExpandTextareas.forEach(textarea => {
        textarea.addEventListener('input', function() {
            // Reset height to get proper scrollHeight
            this.style.height = 'auto';
            
            // Set new height based on content
            const maxHeight = parseInt(getComputedStyle(this).getPropertyValue('max-height'));
            const newHeight = Math.min(this.scrollHeight, maxHeight);
            this.style.height = newHeight + 'px';
        });
        
        // Trigger initial resize
        textarea.dispatchEvent(new Event('input'));
    });
}

// Initialize copy to clipboard functionality
function initCopyToClipboard() {
    const copyButtons = document.querySelectorAll('.copy-button');
    
    copyButtons.forEach(button => {
        button.addEventListener('click', async () => {
            const textToCopy = button.getAttribute('data-text') || 
                              button.parentElement.querySelector('code')?.textContent;
            
            if (textToCopy) {
                try {
                    await navigator.clipboard.writeText(textToCopy);
                    
                    // Show success feedback
                    const originalText = button.innerHTML;
                    button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>';
                    
                    setTimeout(() => {
                        button.innerHTML = originalText;
                    }, 2000);
                } catch (err) {
                    console.error('Failed to copy text: ', err);
                }
            }
        });
    });
}

// Initialize syntax highlighting
function initSyntaxHighlighting() {
    const codeBlocks = document.querySelectorAll('pre code');
    
    codeBlocks.forEach(block => {
        // Add line numbers
        const lines = block.textContent.split('\n');
        if (!block.parentNode.querySelector('.line-numbers')) {
            const lineNumbersWrapper = document.createElement('div');
            lineNumbersWrapper.classList.add('line-numbers');
            
            lines.forEach((_, i) => {
                const lineNumber = document.createElement('span');
                lineNumber.classList.add('line-number');
                lineNumber.textContent = i + 1;
                lineNumbersWrapper.appendChild(lineNumber);
            });
            
            block.parentNode.prepend(lineNumbersWrapper);
        }
        
        // Add language indicator if it doesn't exist
        if (!block.parentNode.querySelector('.code-language')) {
            const language = block.className.replace('language-', '').trim();
            if (language) {
                const languageIndicator = document.createElement('div');
                languageIndicator.classList.add('code-language');
                languageIndicator.textContent = language;
                block.parentNode.prepend(languageIndicator);
            }
        }

        // Add copy button if it doesn't exist
        if (!block.parentNode.querySelector('.copy-button')) {
            const copyButton = document.createElement('button');
            copyButton.classList.add('copy-button');
            copyButton.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
            copyButton.setAttribute('title', 'Copy to clipboard');
            copyButton.setAttribute('data-text', block.textContent);
            block.parentNode.appendChild(copyButton);
        }
    });
}

// Initialize chat functionality
function initChat() {
    const chatInput = document.querySelector('.chat-input');
    const sendButton = document.querySelector('.send-button');
    const chatMessages = document.querySelector('.chat-history');
    
    if (!chatInput || !sendButton || !chatMessages) return;
    
    // Connect to WebSocket
    const chatId = window.location.pathname.split('/').pop();
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(`${wsProtocol}//${window.location.host}/ws/chat/${chatId}`);
    
    let isConnected = false;
    let pendingMessage = '';
    
    ws.onopen = () => {
        isConnected = true;
        sendButton.disabled = false;
        
        // If there was a pending message when connection was lost, send it now
        if (pendingMessage) {
            sendMessage(pendingMessage);
            pendingMessage = '';
        }
    };
    
    ws.onclose = () => {
        isConnected = false;
        sendButton.disabled = true;
        console.log('WebSocket connection closed');
    };
    
    ws.onerror = (error) => {
        console.error('WebSocket error:', error);
    };
    
    let currentAssistantMessageId = null;
    let assistantResponse = '';
    
    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        
        if (data.type === 'token') {
            // Append token to assistant message
            if (currentAssistantMessageId !== data.id) {
                currentAssistantMessageId = data.id;
                assistantResponse = '';
            }
            
            assistantResponse += data.token;
            
            // Update the message content
            const messageElement = document.querySelector(`.message-bubble[data-message-id="${data.id}"]`);
            if (messageElement) {
                const contentElement = messageElement.querySelector('.message-content');
                contentElement.innerHTML = formatMarkdown(assistantResponse);
            } else {
                // Create a new message element
                const timestamp = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                const newMessage = createMessageElement('assistant', data.id, assistantResponse, timestamp);
                chatMessages.appendChild(newMessage);
                chatMessages.scrollTop = chatMessages.scrollHeight;
            }
        } else if (data.type === 'complete') {
            // Message is complete
            chatInput.disabled = false;
            sendButton.disabled = false;
            sendButton.classList.remove('loading');
            
            // Final update to message content
            assistantResponse = data.content;
            const messageElement = document.querySelector(`.message-bubble[data-message-id="${data.id}"]`);
            if (messageElement) {
                const contentElement = messageElement.querySelector('.message-content');
                contentElement.innerHTML = formatMarkdown(assistantResponse);
            }
            
            // Initialize syntax highlighting on new code blocks
            setTimeout(() => {
                initSyntaxHighlighting();
            }, 100);
            
            // Reset state
            currentAssistantMessageId = null;
            assistantResponse = '';
            
            // Scroll to bottom
            chatMessages.scrollTop = chatMessages.scrollHeight;
        } else if (data.type === 'artifact') {
            // New artifact created
            const artifactsList = document.querySelector('.artifacts-list');
            if (artifactsList) {
                const newArtifact = document.createElement('div');
                newArtifact.classList.add('artifact-item');
                newArtifact.setAttribute('data-language', data.language || '');
                
                // Apply language-specific styling
                if (data.language) {
                    const langClass = getLanguageClass(data.language);
                    if (langClass) {
                        newArtifact.classList.add(langClass);
                    }
                }
                
                newArtifact.innerHTML = `
                    <div class="artifact-title">${escapeHTML(data.title)}</div>
                    <div class="artifact-meta">
                        <span class="artifact-date">${data.created_at}</span>
                        ${data.language ? `<span class="artifact-language">${data.language}</span>` : ''}
                    </div>
                    <div class="artifact-actions">
                        <button class="artifact-download-btn" data-artifact-id="${data.id}">
                            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                                <polyline points="7 10 12 15 17 10"></polyline>
                                <line x1="12" y1="15" x2="12" y2="3"></line>
                            </svg>
                            Download
                        </button>
                    </div>
                `;
                
                artifactsList.appendChild(newArtifact);
                
                // Initialize download button
                const downloadBtn = newArtifact.querySelector('.artifact-download-btn');
                downloadBtn.addEventListener('click', function() {
                    const artifactId = this.getAttribute('data-artifact-id');
                    window.location.href = `/api/download-artifact/${artifactId}`;
                });
            }
        } else if (data.type === 'error') {
            // Error occurred
            chatInput.disabled = false;
            sendButton.disabled = false;
            sendButton.classList.remove('loading');
            
            // Show error message
            const errorMessage = document.createElement('div');
            errorMessage.classList.add('error-message');
            errorMessage.textContent = data.error || 'An error occurred';
            chatMessages.appendChild(errorMessage);
            
            // Scroll to bottom
            chatMessages.scrollTop = chatMessages.scrollHeight;
        }
    };
    
    // Send message function
    function sendMessage(content) {
        if (!isConnected) {
            pendingMessage = content;
            return;
        }
        
        // Send the message
        ws.send(JSON.stringify({
            content: content
        }));
        
        // Clear input and disable until response is received
        chatInput.value = '';
        chatInput.style.height = 'auto';
        chatInput.disabled = true;
        
        // Show loading state
        sendButton.disabled = true;
        sendButton.classList.add('loading');
        sendButton.innerHTML = '<div class="spinner"></div>';
        
        // Add user message to chat
        const timestamp = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const userMessage = createMessageElement('user', Date.now(), content, timestamp);
        chatMessages.appendChild(userMessage);
        
        // Scroll to bottom
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }
    
    // Handle send button click
    sendButton.addEventListener('click', () => {
        const content = chatInput.value.trim();
        if (content) {
            sendMessage(content);
        }
    });
    
    // Handle enter key
    chatInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            const content = chatInput.value.trim();
            if (content) {
                sendMessage(content);
            }
        }
    });
    
    // Create message element function
    function createMessageElement(role, id, content, timestamp) {
        const messageElement = document.createElement('div');
        messageElement.classList.add(`${role}-message`);
        
        const avatarLetter = role === 'user' ? 'U' : 'D';
        
        messageElement.innerHTML = `
            <div class="message-avatar ${role}-avatar">${avatarLetter}</div>
            <div class="message-bubble ${role}-bubble" data-message-id="${id}">
                <div class="message-content">${formatMarkdown(content)}</div>
                <div class="message-meta">
                    <span class="message-time">${timestamp}</span>
                </div>
            </div>
        `;
        
        return messageElement;
    }
    
    // Helper function to format markdown
    function formatMarkdown(text) {
        // Replace newlines with <br>
        text = text.replace(/\n/g, '<br>');
        
        // Format code blocks
        text = text.replace(/```([\w]*)([\s\S]*?)```/g, (match, language, code) => {
            language = language.trim();
            code = code.trim();
            
            return `<pre><code class="language-${language || 'plaintext'}">${escapeHTML(code)}</code></pre>`;
        });
        
        // Format inline code
        text = text.replace(/`([^`]+)`/g, '<code>$1</code>');
        
        // Format bold text
        text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        
        // Format italic text
        text = text.replace(/\*([^*]+)\*/g, '<em>$1</em>');
        
        return text;
    }
}

// Initialize chat title editor
function initChatTitleEditor() {
    const titleElement = document.querySelector('.chat-title');
    const editButton = document.querySelector('.chat-title-edit');
    
    if (!titleElement || !editButton) return;
    
    editButton.addEventListener('click', () => {
        const currentTitle = titleElement.textContent.trim();
        
        // Create input element
        const inputElement = document.createElement('input');
        inputElement.type = 'text';
        inputElement.value = currentTitle;
        inputElement.classList.add('chat-title-input');
        
        // Replace title with input
        titleElement.textContent = '';
        titleElement.appendChild(inputElement);
        inputElement.focus();
        
        // Add event listeners for save and cancel
        inputElement.addEventListener('keydown', async (e) => {
            if (e.key === 'Enter') {
                await saveTitle(inputElement.value);
            } else if (e.key === 'Escape') {
                titleElement.textContent = currentTitle;
            }
        });
        
        inputElement.addEventListener('blur', async () => {
            await saveTitle(inputElement.value);
        });
    });
    
    async function saveTitle(newTitle) {
        if (!newTitle.trim()) {
            titleElement.textContent = currentTitle;
            return;
        }
        
        try {
            const chatId = window.location.pathname.split('/').pop();
            const response = await fetch(`/chat/${chatId}/update-title`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ title: newTitle })
            });
            
            const data = await response.json();
            
            if (data.success) {
                titleElement.textContent = newTitle;
            } else {
                titleElement.textContent = currentTitle;
                console.error('Error updating title:', data.error);
            }
        } catch (error) {
            titleElement.textContent = currentTitle;
            console.error('Error updating title:', error);
        }
    }
}

// Initialize artifact download
function initArtifactDownload() {
    const downloadButtons = document.querySelectorAll('.artifact-download-btn');
    
    downloadButtons.forEach(button => {
        button.addEventListener('click', function() {
            const artifactId = this.getAttribute('data-artifact-id');
            window.location.href = `/api/download-artifact/${artifactId}`;
        });
    });
}

// Helper to get language-specific class
function getLanguageClass(language) {
    const languageMap = {
        'python': 'badge-python',
        'javascript': 'badge-javascript',
        'typescript': 'badge-typescript',
        'java': 'badge-java',
        'cpp': 'badge-cpp',
        'c++': 'badge-cpp',
        'go': 'badge-go',
        'rust': 'badge-rust'
    };
    
    return languageMap[language.toLowerCase()] || 'badge-generic';
}

// Helper to escape HTML
function escapeHTML(html) {
    const element = document.createElement('div');
    element.textContent = html;
    return element.innerHTML;
}