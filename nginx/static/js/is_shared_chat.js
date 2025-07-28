// =============================================================================
// nginx/static/js/is_shared_chat.js - DEDICATED CHAT FUNCTIONALITY WITH REAL-TIME MARKDOWN
// =============================================================================

// =============================================================================
// MARKDOWN SETUP AND PROCESSING - MOVED HERE FROM is_shared.js
// =============================================================================

// Enhanced marked.js setup for chat functionality
function setupMarkedWithFormatting() {
    if (!window.marked) {
        console.warn('⚠️ marked.js not available - markdown rendering disabled');
        return;
    }
    
    // Configure marked with better options for chat
    marked.setOptions({
        breaks: true,           // Convert \n to <br>
        gfm: true,             // GitHub Flavored Markdown
        headerIds: false,      // Don't add IDs to headers
        mangle: false,         // Don't mangle text
        sanitize: false,       // Don't sanitize HTML (we trust our AI)
        smartLists: true,      // Better list formatting
        smartypants: false,    // Don't convert quotes/dashes
        xhtml: false,          // Don't close tags
        pedantic: false,       // Don't be strict about markdown
        silent: true           // Don't throw on errors
    });
    
    console.log('📝 Marked.js configured for chat rendering');
}

// Process markdown safely with error handling
function processMarkdownSafely(text) {
    if (!window.marked || !text) return text;
    
    try {
        return marked.parse(text);
    } catch (error) {
        console.warn('⚠️ Markdown processing error:', error);
        return text; // Fallback to plain text
    }
}

// =============================================================================
// SHARED CHAT BASE CLASS - COMPLETE CHAT FUNCTIONALITY
// =============================================================================

class SharedChatBase {
    constructor() {
        this.isTyping = false;
        this.abortController = null;
        this.messageCount = 0;
        this.enableRealtimeMarkdown = true;
        this.markdownUpdateInterval = 100; // Update markdown every 100ms
        this.lastMarkdownUpdate = 0;
        this.maxTokens = 1024; // Default, override in subclasses
        this.storageType = 'none'; // Override in subclasses
        
        // Initialize markdown when chat base is created
        setupMarkedWithFormatting();
    }

    // =============================================================================
    // CHAT EVENT LISTENERS SETUP
    // =============================================================================
    setupEventListeners() {
        // Prevent form submission from refreshing page
        const chatForm = document.getElementById('chat-form');
        if (chatForm) {
            chatForm.addEventListener('submit', (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.sendMessage();
                return false;
            });
        }

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
        
        // Proper Enter key handling for textarea
        const textarea = document.getElementById('chat-input');
        if (textarea) {
            // Handle input changes for character count and auto-resize
            textarea.addEventListener('input', (e) => {
                this.updateCharCount();
                this.autoResizeTextarea();
            });
            
            // Enter key handling
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    if (e.shiftKey) {
                        // Shift+Enter: Allow new line
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
        }

        // Send button click handler
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
    // CHAT UI HELPERS
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
            
            const maxHeight = 120; // 120px max height
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

    scrollToBottom() {
        const messagesContainer = document.getElementById('chat-messages');
        if (messagesContainer) {
            messagesContainer.scrollTo({
                top: messagesContainer.scrollHeight,
                behavior: 'smooth'
            });
        }
    }

    // =============================================================================
    // ENHANCED SSE STREAM PROCESSING WITH REAL-TIME MARKDOWN ON EVERY CHUNK
    // =============================================================================
    async processSSEStream(response, aiMessage) {
        console.log('📺 Starting SSE stream processing with real-time markdown on every chunk');
        
        let accumulated = '';
        
        // Create the parser
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
                        // Accumulate content
                        accumulated += data.content;
                        
                        // REAL-TIME MARKDOWN: Process entire accumulated response with markdown on every chunk
                        this.updateStreamingMessageWithMarkdown(aiMessage, accumulated);
                        
                        console.log('📝 Content chunk received, processing entire response with markdown');
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
        
        // Read the response stream and feed to parser
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        
        try {
            while (true) {
                const { done, value } = await reader.read();
                
                if (done) {
                    console.log('✅ Stream reader finished');
                    // Final markdown update
                    if (accumulated) {
                        this.finishStreaming(aiMessage, accumulated);
                    }
                    break;
                }
                
                const chunk = decoder.decode(value, { stream: true });
                
                // Feed the chunk to the parser
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
    
    // Create parser function (will be replaced if eventsource-parser is available)
    createEventSourceParser(onParse) {
        // Use eventsource-parser if available
        if (typeof createParser !== 'undefined') {
            return createParser(onParse);
        }
        
        // Simple fallback implementation
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

    // ENHANCED: Update streaming message with real-time markdown processing on every chunk
    updateStreamingMessageWithMarkdown(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Process entire accumulated content with markdown on every chunk
            const processedContent = processMarkdownSafely(content);
            
            // Add typing cursor
            streamingEl.innerHTML = processedContent + '<span class="cursor blink">▋</span>';
            
            // Scroll to bottom
            this.scrollToBottom();
        }
    }

    // Legacy method for compatibility (without markdown) - kept for fallback
    updateStreamingMessage(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Show raw text during streaming (no markdown processing)
            streamingEl.innerHTML = content + '<span class="cursor blink">▋</span>';
            this.scrollToBottom();
        }
    }

    finishStreaming(messageDiv, finalContent) {
        console.log('🏁 Finishing stream with content length:', finalContent.length);
        
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Final markdown processing (should already be processed from real-time updates)
            const parsedContent = processMarkdownSafely(finalContent);
            streamingEl.innerHTML = parsedContent;
            
            // Save to appropriate storage (overridden by subclasses)
            if (this.saveMessage && finalContent.trim()) {
                this.saveMessage('assistant', finalContent);
            }
        }
        
        this.isTyping = false;
        this.updateButtons(false);
        this.scrollToBottom();
        
        const input = document.getElementById('chat-input');
        if (input) {
            input.focus();
        }
    }

    // =============================================================================
    // SHARED MESSAGE HANDLING - OVERRIDE IN SUBCLASSES
    // =============================================================================
    addMessage(sender, content, isStreaming = false, skipStorage = false) {
        // This should be overridden by subclasses to handle user-specific styling
        console.warn('addMessage should be overridden by subclass');
        return null;
    }

    async sendMessage() {
        // This should be overridden by subclasses
        console.warn('sendMessage should be overridden by subclass');
    }

    clearChat() {
        // This should be overridden by subclasses
        console.warn('clearChat should be overridden by subclass');
    }

    // Save message method - override in subclasses for different storage types
    saveMessage(role, content) {
        // This should be overridden by subclasses for their specific storage needs
        console.log(`💾 Saving ${role} message (${content.length} chars) - override in subclass`);
    }
}

// =============================================================================
// AUTO-INITIALIZATION AND GLOBAL EXPORTS
// =============================================================================

// Export the chat base class and functions globally
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