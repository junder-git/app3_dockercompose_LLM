// =============================================================================
// nginx/static/js/is_shared_chat.js - COMPLETE WORKING CHAT FUNCTIONALITY
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
        breaks: true,
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
// SHARED CHAT BASE CLASS - COMPLETE WORKING IMPLEMENTATION
// =============================================================================

class SharedChatBase {
    constructor() {
        this.isTyping = false;
        this.abortController = null;
        this.messageCount = 0;
        this.enableRealtimeMarkdown = true;
        this.markdownUpdateInterval = 100;
        this.lastMarkdownUpdate = 0;
        this.maxTokens = 1024;
        this.storageType = 'none';
        
        setupMarkedWithFormatting();
        
        // Auto-initialize everything when constructed
        this.init();
    }

    // =============================================================================
    // INITIALIZATION - AUTOMATICALLY CALLED
    // =============================================================================
    
    init() {
        // Wait for DOM to be ready
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

    // =============================================================================
    // CONTAINER MANAGEMENT
    // =============================================================================

    getMessagesContainer() {
        return document.getElementById('chat-messages-content') || document.getElementById('chat-messages');
    }

    // =============================================================================
    // EVENT LISTENERS SETUP - COMPLETE IMPLEMENTATION
    // =============================================================================
    
    setupEventListeners() {
        console.log('🎯 Setting up chat event listeners...');

        // Chat form submission
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.sendMessage();
                return false;
            });
            console.log('✅ Chat form listener added');
        }

        // Stop button
        const stopButton = document.getElementById('stop-button');
        if (stopButton) {
            stopButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.stopGeneration();
            });
            console.log('✅ Stop button listener added');
        }

        // Clear button
        const clearButton = document.getElementById('clear-chat');
        if (clearButton) {
            clearButton.addEventListener('click', (e) => {
                e.preventDefault();
                this.clearChat();
            });
            console.log('✅ Clear button listener added');
        }
        
        // Textarea handling
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            // Input changes for character count and auto-resize
            textarea.addEventListener('input', (e) => {
                this.updateCharCount();
                this.autoResizeTextarea();
            });
            
            // FIXED: Enter key handling
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    if (e.shiftKey) {
                        // Shift+Enter: Allow new line (do nothing, let default behavior happen)
                        return;
                    } else {
                        // Enter only: Send message
                        e.preventDefault();
                        e.stopPropagation();
                        
                        if (textarea.value.trim()) {
                            this.sendMessage();
                        }
                        return false;
                    }
                }
            });

            // Auto-resize on load
            this.autoResizeTextarea();
            console.log('✅ Textarea listeners added');
        }

        // Send button
        const sendButton = document.getElementById('send-button');
        if (sendButton) {
            sendButton.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                
                const textarea = document.getElementById('chat-input');
                if (textarea && textarea.value.trim()) {
                    this.sendMessage();
                }
                return false;
            });
            console.log('✅ Send button listener added');
        }

        console.log('🎯 Chat event listeners setup complete');
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
            const count = textarea.value.length;
            countEl.textContent = count;
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
    // SCROLLING METHODS
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
    // MESSAGE HANDLING - WORKING IMPLEMENTATION
    // =============================================================================

    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        const messagesContainer = this.getMessagesContainer();
        if (!messagesContainer) {
            console.error('Messages container not found');
            return null;
        }

        // Hide welcome prompt when first message is added
        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt && sender === 'user') {
            welcomePrompt.style.display = 'none';
        }

        const messageDiv = document.createElement('div');
        messageDiv.className = `message message-${sender}`;
        
        const avatarDiv = document.createElement('div');
        avatarDiv.className = `message-avatar avatar-${sender}`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        
        if (sender === 'user') {
            avatarDiv.innerHTML = '<i class="bi bi-person-circle"></i>';
            contentDiv.innerHTML = window.marked ? marked.parse(content) : content;
            
            if (!skipStorage && this.saveMessage) {
                this.saveMessage('user', content);
            }
        } else {
            avatarDiv.innerHTML = '<i class="bi bi-robot"></i>';
            contentDiv.innerHTML = isStreaming ? 
                '<span class="streaming-content"></span>' : 
                (window.marked ? marked.parse(content) : content);
                
            if (!isStreaming && content.trim() && !skipStorage && this.saveMessage) {
                this.saveMessage('assistant', content);
            }
        }
        
        messageDiv.appendChild(avatarDiv);
        messageDiv.appendChild(contentDiv);
        messagesContainer.appendChild(messageDiv);
        this.scrollToBottom();
        
        console.log(`💬 Added ${sender} message:`, content.substring(0, 50) + '...');
        
        return messageDiv;
    }

    // =============================================================================
    // SEND MESSAGE - WORKING IMPLEMENTATION FOR ALL USERS
    // =============================================================================

    async sendMessage() {
        console.log('🚀 sendMessage called');
        const input = document.getElementById('chat-input');
        if (!input) {
            console.error('Chat input not found');
            return;
        }
        
        const message = input.value.trim();
        
        if (!message) {
            console.warn('Empty message - not sending');
            return;
        }

        if (this.isTyping) {
            console.warn('Already typing - ignoring send request');
            return;
        }

        console.log('📤 Sending message:', message);

        // Hide welcome prompt
        const welcomePrompt = document.getElementById('welcome-prompt');
        if (welcomePrompt) welcomePrompt.style.display = 'none';
        
        // Add user message to UI immediately
        this.addMessage('user', message);
        
        // Clear input immediately and reset height
        input.value = '';
        input.style.height = 'auto';
        this.updateCharCount();
        this.autoResizeTextarea();
        
        // Set typing state
        this.isTyping = true;
        this.updateButtons(true);

        // Create abort controller for this request
        this.abortController = new AbortController();
        
        // Add AI message container for streaming
        const aiMessage = this.addMessage('ai', '', true);

        try {
            console.log('🌐 Making SSE request to /api/chat/stream');
            
            const response = await fetch('/api/chat/stream', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'Accept': 'text/event-stream',
                    'Cache-Control': 'no-cache'
                },
                credentials: 'include',
                signal: this.abortController.signal,
                body: JSON.stringify({
                    message: message,
                    stream: true
                })
            });

            console.log('📡 Response status:', response.status);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // Process the streaming response
            await this.processSSEStream(response, aiMessage);

        } catch (error) {
            console.error('❌ Chat error:', error);
            
            if (error.name === 'AbortError') {
                console.log('🛑 Request was aborted by user');
                this.updateStreamingMessage(aiMessage, '*Request cancelled*');
            } else {
                const errorMessage = `*Error: ${error.message}*`;
                this.updateStreamingMessage(aiMessage, errorMessage);
            }
            
            this.finishStreaming(aiMessage, `Error: ${error.message}`);
        }
    }

    // =============================================================================
    // SSE STREAM PROCESSING
    // =============================================================================

    async processSSEStream(response, aiMessage) {
        console.log('📺 Starting SSE stream processing');
        
        let accumulated = '';
        
        const parser = this.createEventSourceParser((event) => {
            if (event.type === 'event') {
                
                if (event.data === '[DONE]') {
                    console.log('✅ Stream completed with [DONE]');
                    this.finishStreaming(aiMessage, accumulated);
                    return;
                }
                
                try {
                    const data = JSON.parse(event.data);
                    
                    if (data.type === 'content' && data.content) {
                        accumulated += data.content;
                        this.updateStreamingMessageWithMarkdown(aiMessage, accumulated);
                    }
                    
                    if (data.type === 'complete' || data.done === true) {
                        console.log('✅ Stream completed with complete flag');
                        this.finishStreaming(aiMessage, accumulated);
                        return;
                    }
                    
                    if (data.type === 'error') {
                        console.error('❌ Stream error:', data.error);
                        const errorMsg = '*Error: ' + data.error + '*';
                        this.updateStreamingMessageWithMarkdown(aiMessage, errorMsg);
                        this.finishStreaming(aiMessage, errorMsg);
                        return;
                    }
                    
                } catch (parseError) {
                    console.warn('⚠️ JSON parse error:', parseError, 'for:', event.data);
                }
            }
        });
        
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        
        try {
            while (true) {
                const { done, value } = await reader.read();
                
                if (done) {
                    console.log('✅ Stream reader finished');
                    if (accumulated) {
                        this.finishStreaming(aiMessage, accumulated);
                    }
                    break;
                }
                
                const chunk = decoder.decode(value, { stream: true });
                parser.feed(chunk);
            }
        } catch (error) {
            console.error('❌ Stream reading error:', error);
            const errorMsg = '*Stream error: ' + error.message + '*';
            this.updateStreamingMessageWithMarkdown(aiMessage, errorMsg);
            this.finishStreaming(aiMessage, errorMsg);
        }
        
        console.log('🏁 Stream processing completed');
        return accumulated;
    }
    
    createEventSourceParser(onParse) {
        if (typeof createParser !== 'undefined') {
            return createParser(onParse);
        }
        
        console.warn('⚠️ eventsource-parser not found, using fallback parser');
        let buffer = '';
        
        return {
            feed: (chunk) => {
                buffer += chunk;
                
                let newlineIndex;
                while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
                    const line = buffer.slice(0, newlineIndex).trim();
                    buffer = buffer.slice(newlineIndex + 1);
                    
                    if (line.startsWith('data: ')) {
                        const data = line.slice(6).trim();
                        onParse({
                            type: 'event',
                            data: data
                        });
                    }
                }
            }
        };
    }

    updateStreamingMessageWithMarkdown(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const processedContent = processMarkdownSafely(content);
            streamingEl.innerHTML = processedContent + '<span class="cursor blink">▋</span>';
            this.smartScroll();
        }
    }

    updateStreamingMessage(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            streamingEl.innerHTML = content + '<span class="cursor blink">▋</span>';
            this.smartScroll();
        }
    }

    finishStreaming(messageDiv, finalContent) {
        console.log('🏁 Finishing stream with content length:', finalContent.length);
        
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const parsedContent = processMarkdownSafely(finalContent);
            streamingEl.innerHTML = parsedContent;
            
            if (this.saveMessage && finalContent.trim()) {
                this.saveMessage('assistant', finalContent);
            }
        }
        
        this.isTyping = false;
        this.updateButtons(false);
        
        setTimeout(() => {
            this.scrollToLatestMessage();
        }, 100);
        
        const input = document.getElementById('chat-input');
        if (input) {
            input.focus();
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
// GLOBAL EXPORTS AND AUTO-INITIALIZATION
// =============================================================================

if (typeof window !== 'undefined') {
    window.SharedChatBase = SharedChatBase;
    window.processMarkdownSafely = processMarkdownSafely;
    window.setupMarkedWithFormatting = setupMarkedWithFormatting;
    
    console.log('💬 Shared chat functionality loaded and available globally');
}

// Auto-resize textarea functionality for all pages
document.addEventListener('DOMContentLoaded', () => {
    const chatInput = document.getElementById('chat-input');
    if (chatInput) {
        chatInput.addEventListener('input', function() {
            this.style.height = '';
            this.style.height = this.scrollHeight + 'px';
        });
    }
});