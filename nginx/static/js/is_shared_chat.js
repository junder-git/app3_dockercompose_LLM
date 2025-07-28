// =============================================================================
// nginx/static/js/is_shared_chat.js - CLEAN CHAT FUNCTIONALITY
// =============================================================================

// =============================================================================
// MARKDOWN SETUP AND PROCESSING
// =============================================================================

function setupMarkedWithFormatting() {
    if (!window.marked) {
        console.warn('⚠️ marked.js not available - markdown rendering disabled');
        return;
    }
    
    marked.setOptions({
        breaks: false,
        gfm: true,
        headerIds: false,
        mangle: false,
        sanitize: false,
        smartLists: true,
        smartypants: false,
        xhtml: false,
        pedantic: false,
        silent: true
    });
    
    console.log('📝 Marked.js configured for chat rendering');
}

function processMarkdownSafely(text) {
    if (!window.marked || !text) return text;
    
    try {
        return marked.parse(text);
    } catch (error) {
        console.warn('⚠️ Markdown processing error:', error);
        return text;
    }
}

// =============================================================================
// STREAMLINED CHAT BASE CLASS - USES EXTERNAL MODULES
// =============================================================================

class SharedChatBase {
    constructor() {
        this.isTyping = false;
        this.abortController = null;
        this.messageCount = 0;
        this.storageType = 'none';
        
        // Initialize specialized managers (from separate JS files)
        this.codePanel = new CodePanelManager();
        this.codeProcessor = new CodeMarkdownProcessor();
        this.sseManager = new SSERequestManager(this);
        
        setupMarkedWithFormatting();
        
        // Make this instance globally available
        window.sharedChatInstance = this;
        
        // Auto-initialize
        this.init();
    }

    // =============================================================================
    // INITIALIZATION
    // =============================================================================
    
    init() {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => {
                this.setupEventListeners();
                this.setupSuggestionChips();
                console.log('🎯 SharedChatBase initialized and ready');
            });
        } else {
            this.setupEventListeners();
            this.setupSuggestionChips();
            console.log('🎯 SharedChatBase initialized and ready');
        }
    }

    getMessagesContainer() {
        return document.getElementById('chat-messages-content') || document.getElementById('chat-messages');
    }

    // =============================================================================
    // EVENT LISTENERS
    // =============================================================================
    
    setupEventListeners() {
        console.log('🎯 Setting up chat event listeners...');

        // Form submission
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault();
                this.sendMessage();
                return false;
            });
        }

        // Stop/Clear buttons
        const stopButton = document.getElementById('stop-button');
        if (stopButton) {
            stopButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.stopGeneration();
            });
        }

        const clearButton = document.getElementById('clear-chat');
        if (clearButton) {
            clearButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.clearChat();
            });
        }
        
        // Textarea handling
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.addEventListener('input', () => {
                this.updateCharCount();
                this.autoResizeTextarea();
            });
            
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    if (textarea.value.trim()) {
                        this.sendMessage();
                    }
                    return false;
                }
            });

            this.autoResizeTextarea();
        }

        // Send button
        const sendButton = document.getElementById('send-button');
        if (sendButton) {
            sendButton.addEventListener('click', (e) => {
                e.preventDefault();
                const textarea = document.getElementById('chat-input');
                if (textarea && textarea.value.trim()) {
                    this.sendMessage();
                }
                return false;
            });
        }

        console.log('🎯 Event listeners setup complete');
    }

    setupSuggestionChips() {
        document.querySelectorAll('.suggestion-chip').forEach(chip => {
            chip.addEventListener('click', (e) => {
                e.preventDefault();
                const input = document.getElementById('chat-input');
                if (input) {
                    input.value = chip.dataset.prompt;
                    input.focus();
                    this.updateCharCount();
                    this.autoResizeTextarea();
                }
            });
        });
    }

    // =============================================================================
    // UI HELPERS
    // =============================================================================
    
    updateCharCount() {
        const textarea = document.getElementById('chat-input');
        const countEl = document.getElementById('char-count');
        
        if (textarea && countEl) {
            countEl.textContent = textarea.value.length;
        }
    }

    autoResizeTextarea() {
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            textarea.style.height = 'auto';
            const maxHeight = 120;
            const newHeight = Math.min(textarea.scrollHeight, maxHeight);
            textarea.style.height = newHeight + 'px';
            textarea.style.overflowY = textarea.scrollHeight > maxHeight ? 'auto' : 'hidden';
        }
    }

    updateButtons(isTyping) {
        const sendButton = document.getElementById('send-button');
        const stopButton = document.getElementById('stop-button');
        const chatInput = document.getElementById('chat-input');

        if (sendButton) {
            sendButton.style.display = isTyping ? 'none' : 'inline-flex';
            sendButton.disabled = isTyping;
        }
        if (stopButton) {
            stopButton.style.display = isTyping ? 'inline-flex' : 'none';
            stopButton.disabled = !isTyping;
        }
        if (chatInput) {
            chatInput.disabled = isTyping;
        }
    }

    stopGeneration() {
        console.log('⏹️ Stopping generation');
        if (this.abortController) {
            this.abortController.abort();
        }
        this.isTyping = false;
        this.updateButtons(false);
    }

    // =============================================================================
    // SCROLLING
    // =============================================================================

    scrollToBottom() {
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            messagesContainer.scrollTo({
                top: messagesContainer.scrollHeight,
                behavior: 'smooth'
            });
        }
    }

    scrollToLatestMessage() {
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            const messages = messagesContainer.querySelectorAll('.message');
            if (messages.length > 0) {
                const latestMessage = messages[messages.length - 1];
                latestMessage.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            } else {
                this.scrollToBottom();
            }
        }
    }

    smartScroll() {
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            const { scrollTop, scrollHeight, clientHeight } = messagesContainer;
            const isNearBottom = scrollTop + clientHeight >= scrollHeight - 100;
            
            if (isNearBottom) {
                this.scrollToBottom();
            }
        }
    }

    // =============================================================================
    // MESSAGE HANDLING - SIMPLE AND CLEAN
    // =============================================================================

    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        const messagesContainer = this.getMessagesContainer();
        if (!messagesContainer) {
            console.error('Messages container not found');
            return null;
        }

        // Hide welcome prompt for user messages
        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt && sender === 'user') {
            welcomePrompt.style.display = 'none';
        }

        // Prevent duplicate empty AI messages
        if (
            sender === 'ai' &&
            !isStreaming &&
            (!content || content.trim() === '')
        ) {
            console.warn('🛑 Skipping blank AI message');
            return null;
        }

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;

        // Header section
        const headerDiv = document.createElement('div');
        headerDiv.className = 'message-header';

        const avatarDiv = document.createElement('div');
        avatarDiv.className = `message-avatar avatar-${sender}`;

        const labelSpan = document.createElement('span');
        if (sender === 'user') {
            avatarDiv.innerHTML = '<i class="bi bi-person-circle"></i>';
            labelSpan.textContent = 'You';
        } else {
            avatarDiv.innerHTML = '<i class="bi bi-robot"></i>';
            labelSpan.textContent = 'AI Assistant';
        }

        headerDiv.appendChild(avatarDiv);
        headerDiv.appendChild(labelSpan);

        // Content section
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';

        if (sender === 'user') {
            contentDiv.innerHTML = window.marked ? marked.parse(content) : content;

            if (!skipStorage && this.saveMessage) {
                this.saveMessage('user', content);
            }
        } else if (isStreaming) {
            const streamDiv = document.createElement('div');
            streamDiv.className = 'streaming-content';
            contentDiv.appendChild(streamDiv);
        } else {
            contentDiv.innerHTML = window.marked ? marked.parse(content) : content;

            if (content.trim() && !skipStorage && this.saveMessage) {
                this.saveMessage('assistant', content);
            }
        }

        messageDiv.appendChild(headerDiv);
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);

        this.scrollToBottom();

        console.log(`💬 Added ${sender} message:`, content.substring(0, 50) + '...');
        return messageDiv;
    }


    // =============================================================================
    // SEND MESSAGE - DELEGATES TO SSE MANAGER
    // =============================================================================

    async sendMessage() {
        console.log('🚀 sendMessage called');
        const input = document.getElementById('chat-input');
        if (!input) {
            console.error('Chat input not found');
            return;
        }
        
        const message = input.value.trim();
        if (!message || this.isTyping) {
            return;
        }

        console.log('📤 Sending message:', message);

        // Hide welcome prompt
        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt) welcomePrompt.style.display = 'none';
        
        // Add user message
        this.addMessage('user', message);
        
        // Clear input
        input.value = '';
        input.style.height = 'auto';
        this.updateCharCount();
        this.autoResizeTextarea();
        
        // Set typing state
        this.isTyping = true;
        this.updateButtons(true);
        this.abortController = new AbortController();
        
        // Add AI message container
        const aiMessage = this.addMessage('ai', '', true);

        try {
            // Delegate to SSE manager
            await this.sseManager.sendStreamingRequest(message, aiMessage);
        } catch (error) {
            // Delegate error handling to SSE manager
            this.sseManager.handleStreamingError(error, aiMessage);
        }
    }

    // =============================================================================
    // CLEAR CHAT
    // =============================================================================

    clearChat() {
        if (!confirm('Clear chat history?')) return;
        
        const messagesContainer = this.getMessagesContainer();
        const welcomePrompt = document.getElementById('welcome-prompt');
        
        if (messagesContainer) {
            const messages = messagesContainer.querySelectorAll('.message');
            messages.forEach(msg => msg.remove());
        }
        
        if (welcomePrompt) {
            welcomePrompt.style.display = 'block';
        }
        
        // Clear code artifacts and hide panel
        
        this.messageCount = 0;
        
        if (this.clearStorage) {
            this.clearStorage();
        }
        
        console.log('🗑️ Chat history cleared');
    }

    // =============================================================================
    // STORAGE - OVERRIDE IN SUBCLASSES
    // =============================================================================

    saveMessage(role, content) {
        console.log(`💾 Saving ${role} message (${content.length} chars) - override in subclass for persistent storage`);
    }
}

// =============================================================================
// GLOBAL EXPORTS
// =============================================================================

if (typeof window !== 'undefined') {
    window.SharedChatBase = SharedChatBase;
    window.processMarkdownSafely = processMarkdownSafely;
    window.setupMarkedWithFormatting = setupMarkedWithFormatting;
    
    console.log('💬 Clean chat functionality loaded and available globally');
}

// Auto-resize textarea functionality
document.addEventListener('DOMContentLoaded', () => {
    const chatInput = document.getElementById('chat-input');
    if (chatInput) {
        chatInput.addEventListener('input', function() {
            this.style.height = '';
            this.style.height = this.scrollHeight + 'px';
        });
    }
});