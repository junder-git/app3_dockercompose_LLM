// =============================================================================
// nginx/static/js/is_shared_sse.js - SERVER-SENT EVENTS MANAGEMENT
// =============================================================================

// =============================================================================
// SSE EVENT SOURCE PARSER
// =============================================================================

class SSEParser {
    constructor(onParse) {
        this.onParse = onParse;
        this.buffer = '';
    }
    
    feed(chunk) {
        this.buffer += chunk;
        
        let newlineIndex;
        while ((newlineIndex = this.buffer.indexOf('\n')) !== -1) {
            const line = this.buffer.slice(0, newlineIndex).trim();
            this.buffer = this.buffer.slice(newlineIndex + 1);
            
            if (line.startsWith('data: ')) {
                const data = line.slice(6).trim();
                this.onParse({
                    type: 'event',
                    data: data
                });
            }
        }
    }
}

// =============================================================================
// SSE STREAM PROCESSOR
// =============================================================================

class SSEStreamProcessor {
    constructor(chatInstance) {
        this.chatInstance = chatInstance;
    }
    
    createEventSourceParser(onParse) {
        // Try to use external eventsource-parser if available
        if (typeof createParser !== 'undefined') {
            return createParser(onParse);
        }
        
        console.warn('⚠️ eventsource-parser not found, using fallback parser');
        return new SSEParser(onParse);
    }
    
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
                        this.updateStreamingMessage(aiMessage, accumulated);
                    }
                    
                    if (data.type === 'complete' || data.done === true) {
                        console.log('✅ Stream completed with complete flag');
                        this.finishStreaming(aiMessage, accumulated);
                        return;
                    }
                    
                    if (data.type === 'error') {
                        console.error('❌ Stream error:', data.error);
                        const errorMsg = '*Error: ' + data.error + '*';
                        this.updateStreamingMessage(aiMessage, errorMsg);
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
            this.updateStreamingMessage(aiMessage, errorMsg);
            this.finishStreaming(aiMessage, errorMsg);
        }
        
        console.log('🏁 Stream processing completed');
        return accumulated;
    }
    
    updateStreamingMessage(messageDiv, content) {
        // Fallback to basic streaming
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            const processedContent = window.processMarkdownSafely ? 
                window.processMarkdownSafely(content) : content;
            streamingEl.innerHTML = processedContent + '<span class="cursor blink">▋</span>';
            
            if (this.chatInstance && this.chatInstance.smartScroll) {
                this.chatInstance.smartScroll();
            }
        }
    }
    
    finishStreaming(messageDiv, finalContent) {
        console.log('🏁 Finishing stream with content length:', finalContent.length);
        
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {          
            // Process final content
            let parsedContent;
            parsedContent = window.processMarkdownSafely ? 
                window.processMarkdownSafely(finalContent) : finalContent;
            streamingEl.innerHTML = parsedContent;
            // Save message if chat instance supports it
            if (this.chatInstance && this.chatInstance.saveMessage && finalContent.trim()) {
                this.chatInstance.saveMessage('assistant', finalContent);
            }
        }
        // Update chat state
        if (this.chatInstance) {
            this.chatInstance.isTyping = false;
            if (this.chatInstance.updateButtons) {
                this.chatInstance.updateButtons(false);
            }
            // Scroll to latest message
            setTimeout(() => {
                if (this.chatInstance.scrollToLatestMessage) {
                    this.chatInstance.scrollToLatestMessage();
                }
            }, 100);
            
            // Focus input
            const input = document.getElementById('chat-input');
            if (input) {
                input.focus();
            }
        }
    }
}

// =============================================================================
// SSE REQUEST MANAGER
// =============================================================================

class SSERequestManager {
    constructor(chatInstance) {
        this.chatInstance = chatInstance;
        this.streamProcessor = new SSEStreamProcessor(chatInstance);
    }
    
    async sendStreamingRequest(message, aiMessage) {
        console.log('🌐 Making SSE request to /api/chat/stream');
        
        const response = await fetch('/api/chat/stream', {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
                'Cache-Control': 'no-cache'
            },
            credentials: 'include',
            signal: this.chatInstance.abortController ? this.chatInstance.abortController.signal : undefined,
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
        return await this.streamProcessor.processSSEStream(response, aiMessage);
    }
    
    handleStreamingError(error, aiMessage) {
        console.error('❌ Chat error:', error);
        
        let errorMessage;
        if (error.name === 'AbortError') {
            console.log('🛑 Request was aborted by user');
            errorMessage = '*Request cancelled*';
        } else {
            errorMessage = `*Error: ${error.message}*`;
        }
        
        this.streamProcessor.updateStreamingMessage(aiMessage, errorMessage);
        this.streamProcessor.finishStreaming(aiMessage, errorMessage);
    }
}

// =============================================================================
// GLOBAL EXPORTS
// =============================================================================

if (typeof window !== 'undefined') {
    window.SSEParser = SSEParser;
    window.SSEStreamProcessor = SSEStreamProcessor;
    window.SSERequestManager = SSERequestManager;
    
    console.log('📡 SSE management loaded and available globally');
}