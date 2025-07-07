// chat.js - Chat Module

class ChatModule {
    constructor(app) {
        this.app = app;
        this.currentUser = null;
        this.currentSession = null;
        this.isStreaming = false;
        this.streamingResponse = null;
        this.eventSource = null;
        
        // Configuration
        this.config = {
            MAX_MESSAGE_LENGTH: 5000,
            RATE_LIMIT_MAX: 100,
            OLLAMA_URL: '/api/ollama',
            MODEL_NAME: 'devstral'
        };
        
        console.log('💬 ChatModule created');
    }

    async loadChatPage(sessionId = null) {
        try {
            // Verify authentication
            this.currentUser = await this.app.modules.auth.getCurrentUser();
            if (!this.currentUser) {
                throw new Error('User not authenticated');
            }

            // Load or create session
            if (sessionId) {
                this.currentSession = await window.Database.getChatSession(sessionId);
                if (!this.currentSession || this.currentSession.user_id !== this.currentUser.id) {
                    throw new Error('Session not found or access denied');
                }
            } else {
                await this.createNewSession();
            }

            const html = `
                <div class="container-fluid h-100">
                    <div class="row h-100">
                        <!-- Sidebar -->
                        <div class="col-md-3 col-lg-2 d-none d-md-block" id="sidebar">
                            <div class="card h-100 border-end rounded-0">
                                <div class="card-header">
                                    <div class="d-flex justify-content-between align-items-center">
                                        <h6 class="mb-0"><i class="bi bi-chat-dots"></i> Chat Sessions</h6>
                                        <button class="btn btn-sm btn-outline-primary" onclick="window.DevstralApp.modules.chat.createNewSession()">
                                            <i class="bi bi-plus"></i>
                                        </button>
                                    </div>
                                </div>
                                <div class="card-body p-0">
                                    <div id="sessions-list" class="list-group list-group-flush">
                                        <!-- Sessions will be loaded here -->
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- Main Chat Area -->
                        <div class="col-md-9 col-lg-10" id="main-chat">
                            <div class="card h-100 rounded-0">
                                <!-- Chat Header -->
                                <div class="card-header">
                                    <div class="d-flex justify-content-between align-items-center">
                                        <div class="d-flex align-items-center">
                                            <button class="btn btn-sm btn-outline-secondary d-md-none me-2" id="toggle-sidebar">
                                                <i class="bi bi-list"></i>
                                            </button>
                                            <h6 class="mb-0" id="session-title">${this.currentSession?.title || 'New Chat'}</h6>
                                        </div>
                                        <div class="btn-group btn-group-sm">
                                            <button class="btn btn-outline-secondary" onclick="window.DevstralApp.modules.chat.clearCurrentSession()" title="Clear Messages">
                                                <i class="bi bi-trash"></i>
                                            </button>
                                            <button class="btn btn-outline-secondary" onclick="window.DevstralApp.modules.chat.exportSession()" title="Export Chat">
                                                <i class="bi bi-download"></i>
                                            </button>
                                        </div>
                                    </div>
                                </div>

                                <!-- Chat Messages -->
                                <div class="card-body d-flex flex-column p-0 position-relative">
                                    <div id="chat-messages" class="flex-grow-1 p-3" style="overflow-y: auto; max-height: calc(100vh - 250px);">
                                        <!-- Messages will be loaded here -->
                                    </div>

                                    <!-- Streaming Controls -->
                                    <div id="streaming-controls" class="d-none p-2 border-top bg-light">
                                        <div class="d-flex justify-content-between align-items-center">
                                            <span class="text-muted small">
                                                <i class="bi bi-cpu"></i> AI is thinking...
                                            </span>
                                            <button class="btn btn-sm btn-outline-danger" onclick="window.DevstralApp.modules.chat.stopStreaming()">
                                                <i class="bi bi-stop"></i> Stop
                                            </button>
                                        </div>
                                    </div>

                                    <!-- Message Input -->
                                    <div class="border-top p-3">
                                        <form id="message-form" class="d-flex gap-2">
                                            <div class="flex-grow-1">
                                                <textarea 
                                                    id="message-input" 
                                                    class="form-control" 
                                                    rows="2" 
                                                    placeholder="Type your message..."
                                                    maxlength="${this.config.MAX_MESSAGE_LENGTH}"
                                                    required></textarea>
                                                <div class="form-text">
                                                    <span id="char-count">0</span>/${this.config.MAX_MESSAGE_LENGTH} characters
                                                </div>
                                            </div>
                                            <div class="d-flex flex-column justify-content-end">
                                                <button type="submit" class="btn btn-primary" id="send-button" disabled>
                                                    <i class="bi bi-send"></i>
                                                </button>
                                            </div>
                                        </form>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            `;

            $('#app-content').html(html);
            
            // Initialize chat interface
            await this.initializeChatInterface();

        } catch (error) {
            console.error('❌ Error loading chat page:', error);
            this.app.showError('Failed to load chat', error.message);
        }
    }

    async initializeChatInterface() {
        try {
            // Load sessions list
            await this.loadSessionsList();
            
            // Load current session messages
            await this.loadSessionMessages();
            
            // Set up event handlers
            this.setupEventHandlers();
            
            // Focus on input
            $('#message-input').focus();

        } catch (error) {
            console.error('❌ Error initializing chat interface:', error);
            this.app.showFlashMessage('Failed to initialize chat interface', 'error');
        }
    }

    setupEventHandlers() {
        // Message form submission
        $('#message-form').on('submit', (e) => {
            e.preventDefault();
            this.sendMessage();
        });

        // Character count
        $('#message-input').on('input', (e) => {
            const length = e.target.value.length;
            $('#char-count').text(length);
            $('#send-button').prop('disabled', length === 0 || this.isStreaming);
        });

        // Enter to send (Shift+Enter for new line)
        $('#message-input').on('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                if (!$('#send-button').prop('disabled')) {
                    this.sendMessage();
                }
            }
        });

        // Auto-resize textarea
        $('#message-input').on('input', function() {
            this.style.height = 'auto';
            this.style.height = Math.min(this.scrollHeight, 150) + 'px';
        });

        // Mobile sidebar toggle
        $('#toggle-sidebar').on('click', () => {
            $('#sidebar').toggleClass('d-none');
        });

        // Auto-scroll messages to bottom
        this.setupAutoScroll();
    }

    setupAutoScroll() {
        const messagesContainer = $('#chat-messages')[0];
        if (messagesContainer) {
            messagesContainer.scrollTop = messagesContainer.scrollHeight;
        }
    }

    async createNewSession() {
        try {
            const session = await window.Database.createChatSession(this.currentUser.id);
            this.currentSession = session;
            
            // Update URL
            window.history.pushState(null, '', `#chat/${session.id}`);
            
            // Update UI
            $('#session-title').text(session.title);
            $('#chat-messages').empty();
            
            // Reload sessions list
            await this.loadSessionsList();
            
            // Focus input
            $('#message-input').focus();

        } catch (error) {
            console.error('❌ Error creating new session:', error);
            this.app.showFlashMessage('Failed to create new session', 'error');
        }
    }

    async loadSessionsList() {
        try {
            const sessions = await window.Database.getUserChatSessions(this.currentUser.id);
            
            if (sessions.length === 0) {
                $('#sessions-list').html('<div class="p-3 text-muted">No sessions yet</div>');
                return;
            }

            const sessionItems = sessions.map(session => `
                <div class="list-group-item list-group-item-action ${session.id === this.currentSession?.id ? 'active' : ''}"
                     onclick="window.DevstralApp.modules.chat.switchToSession('${session.id}')">
                    <div class="d-flex w-100 justify-content-between">
                        <h6 class="mb-1">${Utils.truncateText(session.title, 25)}</h6>
                        <small>${Utils.formatRelativeTime(session.updated_at)}</small>
                    </div>
                    <small class="text-muted">
                        Created ${Utils.formatRelativeTime(session.created_at)}
                    </small>
                </div>
            `).join('');

            $('#sessions-list').html(sessionItems);

        } catch (error) {
            console.error('❌ Error loading sessions list:', error);
            $('#sessions-list').html('<div class="p-3 text-danger">Failed to load sessions</div>');
        }
    }

    async switchToSession(sessionId) {
        try {
            const session = await window.Database.getChatSession(sessionId);
            if (!session || session.user_id !== this.currentUser.id) {
                throw new Error('Session not found or access denied');
            }

            this.currentSession = session;
            
            // Update URL
            window.history.pushState(null, '', `#chat/${sessionId}`);
            
            // Update UI
            $('#session-title').text(session.title);
            
            // Load messages
            await this.loadSessionMessages();
            
            // Update sessions list
            await this.loadSessionsList();
            
            // Hide sidebar on mobile
            if (Utils.isMobileDevice()) {
                $('#sidebar').addClass('d-none');
            }

        } catch (error) {
            console.error('❌ Error switching to session:', error);
            this.app.showFlashMessage('Failed to switch session', 'error');
        }
    }

    async loadSessionMessages() {
        try {
            if (!this.currentSession) return;

            const messages = await window.Database.getSessionMessages(this.currentSession.id);
            
            if (messages.length === 0) {
                $('#chat-messages').html(`
                    <div class="text-center text-muted py-5">
                        <i class="bi bi-chat-dots" style="font-size: 3rem;"></i>
                        <h5 class="mt-3">Start a conversation</h5>
                        <p>Type a message below to begin chatting with Devstral AI.</p>
                    </div>
                `);
                return;
            }

            const messageElements = messages.map(msg => this.renderMessage(msg)).join('');
            $('#chat-messages').html(messageElements);
            
            // Scroll to bottom
            setTimeout(() => this.setupAutoScroll(), 100);

        } catch (error) {
            console.error('❌ Error loading session messages:', error);
            $('#chat-messages').html('<div class="text-center text-danger">Failed to load messages</div>');
        }
    }

    renderMessage(message) {
        const isUser = message.role === 'user';
        const timestamp = Utils.formatTimestamp(message.timestamp);
        const cachedIndicator = message.cached ? '<i class="bi bi-lightning-fill text-success"></i> Cached response' : '';
        
        return `
            <div class="message ${isUser ? 'user-message' : 'assistant-message'} ${message.cached ? 'cached' : ''}" data-message-id="${message.id}">
                <div class="message-content">
                    ${isUser ? 
                        `<div class="user-text">${Utils.escapeHtml(message.content)}</div>` :
                        `<div class="ai-response">${this.renderAssistantContent(message.content)}</div>`
                    }
                    <div class="message-timestamp">
                        ${timestamp}
                        ${cachedIndicator}
                    </div>
                </div>
            </div>
        `;
    }

    renderAssistantContent(content) {
        // Simple markdown rendering for AI responses
        return Utils.renderMarkdown(content);
    }

    async sendMessage() {
        const messageText = $('#message-input').val().trim();
        if (!messageText || this.isStreaming) return;

        try {
            // Check rate limiting
            const rateLimitOk = await window.Database.checkRateLimit(this.currentUser.id, this.config.RATE_LIMIT_MAX);
            if (!rateLimitOk) {
                this.app.showFlashMessage('Rate limit exceeded. Please wait before sending another message.', 'warning');
                return;
            }

            // Clear input and disable form
            $('#message-input').val('');
            $('#char-count').text('0');
            $('#send-button').prop('disabled', true);
            this.isStreaming = true;

            // Add user message to UI immediately
            const userMessage = {
                id: Utils.generateRandomId('msg'),
                role: 'user',
                content: messageText,
                timestamp: new Date().toISOString()
            };

            this.addMessageToUI(userMessage);

            // Save user message to database
            await window.Database.saveMessage(
                this.currentUser.id,
                'user',
                messageText,
                this.currentSession.id
            );

            // Start AI response
            await this.getAIResponse(messageText);

        } catch (error) {
            console.error('❌ Error sending message:', error);
            this.app.showFlashMessage('Failed to send message', 'error');
            this.isStreaming = false;
            $('#send-button').prop('disabled', false);
        }
    }

    addMessageToUI(message) {
        const messageHtml = this.renderMessage(message);
        $('#chat-messages').append(messageHtml);
        this.setupAutoScroll();
    }

    async getAIResponse(userMessage) {
        try {
            // Show streaming controls
            $('#streaming-controls').removeClass('d-none');

            // Check for cached response
            const promptHash = await Utils.generateHash(userMessage);
            const cachedResponse = await window.Database.getCachedResponse(promptHash);

            if (cachedResponse) {
                // Use cached response
                const assistantMessage = {
                    id: Utils.generateRandomId('msg'),
                    role: 'assistant',
                    content: cachedResponse,
                    timestamp: new Date().toISOString(),
                    cached: true
                };

                this.addMessageToUI(assistantMessage);

                // Save to database
                await window.Database.saveMessage(
                    this.currentUser.id,
                    'assistant',
                    cachedResponse,
                    this.currentSession.id
                );

                this.finishStreaming();
                return;
            }

            // Get conversation history
            const messages = await window.Database.getSessionMessages(this.currentSession.id, 10);
            const conversationHistory = messages.map(msg => ({
                role: msg.role,
                content: msg.content
            }));

            // Add current user message
            conversationHistory.push({
                role: 'user',
                content: userMessage
            });

            // Start streaming response
            await this.streamAIResponse(conversationHistory, promptHash);

        } catch (error) {
            console.error('❌ Error getting AI response:', error);
            this.addErrorMessage('Failed to get AI response. Please try again.');
            this.finishStreaming();
        }
    }

    async streamAIResponse(messages, promptHash) {
        try {
            // Create streaming response container
            const streamingId = Utils.generateRandomId('streaming');
            const streamingHtml = `
                <div class="message assistant-message" id="${streamingId}">
                    <div class="message-content">
                        <div class="ai-response" id="${streamingId}-content"></div>
                        <div class="message-timestamp">
                            <span class="text-muted">Generating response...</span>
                        </div>
                    </div>
                </div>
            `;

            $('#chat-messages').append(streamingHtml);
            this.setupAutoScroll();

            // Prepare request payload
            const requestPayload = {
                model: this.config.MODEL_NAME,
                messages: messages,
                stream: true,
                options: {
                    temperature: 0.7,
                    num_predict: 512,
                    stop: ["<|endoftext|>", "<|im_end|>", "[DONE]", "<|end|>"]
                }
            };

            // Make streaming request
            const response = await fetch(`${this.config.OLLAMA_URL}/api/chat`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestPayload)
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // Process streaming response
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let fullResponse = '';

            while (true) {
                const { done, value } = await reader.read();
                
                if (done) break;
                if (!this.isStreaming) break; // User stopped streaming

                const chunk = decoder.decode(value);
                const lines = chunk.split('\n').filter(line => line.trim());

                for (const line of lines) {
                    try {
                        const data = JSON.parse(line);
                        
                        if (data.message && data.message.content) {
                            fullResponse += data.message.content;
                            
                            // Update UI with incremental content
                            const contentElement = $(`#${streamingId}-content`);
                            contentElement.html(this.renderAssistantContent(fullResponse));
                            this.setupAutoScroll();
                        }

                        if (data.done) {
                            break;
                        }
                    } catch (parseError) {
                        console.warn('Failed to parse streaming chunk:', parseError);
                    }
                }
            }

            if (fullResponse.trim()) {
                // Update final message
                const finalTimestamp = new Date().toISOString();
                $(`#${streamingId} .message-timestamp`).html(Utils.formatTimestamp(finalTimestamp));
                $(`#${streamingId}`).attr('data-message-id', Utils.generateRandomId('msg'));

                // Save to database
                await window.Database.saveMessage(
                    this.currentUser.id,
                    'assistant',
                    fullResponse,
                    this.currentSession.id
                );

                // Cache the response
                await window.Database.cacheResponse(promptHash, fullResponse);

                // Update session title if this is the first message
                await this.updateSessionTitle(fullResponse);
            } else {
                // Remove empty response
                $(`#${streamingId}`).remove();
                this.addErrorMessage('Received empty response from AI.');
            }

        } catch (error) {
            console.error('❌ Streaming error:', error);
            this.addErrorMessage(`AI Error: ${error.message}`);
        } finally {
            this.finishStreaming();
        }
    }

    async updateSessionTitle(firstResponse) {
        if (!this.currentSession || this.currentSession.title !== `Chat ${new Date(this.currentSession.created_at).toLocaleString()}`) {
            return; // Title already customized
        }

        try {
            // Generate title from first response
            const words = firstResponse.split(' ').slice(0, 6);
            let newTitle = words.join(' ');
            if (firstResponse.split(' ').length > 6) {
                newTitle += '...';
            }

            // Update session
            this.currentSession.title = newTitle || 'Untitled Chat';
            await window.Database.hset(`session:${this.currentSession.id}`, 'title', this.currentSession.title);

            // Update UI
            $('#session-title').text(this.currentSession.title);
            await this.loadSessionsList();

        } catch (error) {
            console.warn('Failed to update session title:', error);
        }
    }

    addErrorMessage(errorText) {
        const errorMessage = {
            id: Utils.generateRandomId('msg'),
            role: 'assistant',
            content: `⚠️ **Error**: ${errorText}`,
            timestamp: new Date().toISOString()
        };

        this.addMessageToUI(errorMessage);
    }

    stopStreaming() {
        this.isStreaming = false;
        this.finishStreaming();
    }

    finishStreaming() {
        this.isStreaming = false;
        $('#streaming-controls').addClass('d-none');
        $('#send-button').prop('disabled', false);
        $('#message-input').focus();
    }

    async clearCurrentSession() {
        if (!this.currentSession) return;

        Utils.confirmDialog(
            'Clear Messages',
            'Are you sure you want to clear all messages in this session? This action cannot be undone.',
            async () => {
                try {
                    await window.Database.clearSessionMessages(this.currentSession.id);
                    $('#chat-messages').empty();
                    this.app.showFlashMessage('Session cleared successfully', 'success');
                } catch (error) {
                    console.error('❌ Error clearing session:', error);
                    this.app.showFlashMessage('Failed to clear session', 'error');
                }
            }
        );
    }

    async exportSession() {
        if (!this.currentSession) return;

        try {
            const messages = await window.Database.getSessionMessages(this.currentSession.id);
            
            const exportData = {
                session_title: this.currentSession.title,
                session_id: this.currentSession.id,
                created_at: this.currentSession.created_at,
                user: this.currentUser.username,
                messages: messages.map(msg => ({
                    role: msg.role,
                    content: msg.content,
                    timestamp: msg.timestamp
                })),
                export_timestamp: new Date().toISOString()
            };

            const filename = `chat_${this.currentSession.id}_${new Date().toISOString().split('T')[0]}.json`;
            Utils.downloadJSON(exportData, filename);
            
            this.app.showFlashMessage('Chat exported successfully', 'success');

        } catch (error) {
            console.error('❌ Error exporting session:', error);
            this.app.showFlashMessage('Failed to export chat', 'error');
        }
    }

    // Utility methods
    scrollToBottom() {
        const messagesContainer = $('#chat-messages');
        messagesContainer.scrollTop(messagesContainer[0].scrollHeight);
    }

    async regenerateLastResponse() {
        try {
            if (!this.currentSession) return;

            const messages = await window.Database.getSessionMessages(this.currentSession.id);
            if (messages.length < 2) return;

            // Find last user message
            let lastUserMessage = null;
            for (let i = messages.length - 1; i >= 0; i--) {
                if (messages[i].role === 'user') {
                    lastUserMessage = messages[i];
                    break;
                }
            }

            if (!lastUserMessage) return;

            // Remove last assistant response from UI and database
            const lastMessage = messages[messages.length - 1];
            if (lastMessage.role === 'assistant') {
                await window.Database.del(`message:${lastMessage.id}`);
                await window.Database.zrem(`session_messages:${this.currentSession.id}`, lastMessage.id);
                
                // Remove from UI
                $(`[data-message-id="${lastMessage.id}"]`).remove();
            }

            // Regenerate response
            await this.getAIResponse(lastUserMessage.content);

        } catch (error) {
            console.error('❌ Error regenerating response:', error);
            this.app.showFlashMessage('Failed to regenerate response', 'error');
        }
    }

    // Copy message content
    copyMessage(messageId) {
        const messageElement = $(`[data-message-id="${messageId}"] .message-content`);
        const content = messageElement.text().trim();
        
        Utils.copyToClipboard(content);
    }

    // Clean up resources
    cleanup() {
        if (this.eventSource) {
            this.eventSource.close();
            this.eventSource = null;
        }
        
        this.isStreaming = false;
        this.currentSession = null;
        this.streamingResponse = null;
    }

    // Handle connection errors
    handleConnectionError(error) {
        console.error('Connection error:', error);
        this.addErrorMessage('Connection lost. Please check your internet connection and try again.');
        this.finishStreaming();
    }

    // Retry failed request
    async retryLastMessage() {
        const messages = await window.Database.getSessionMessages(this.currentSession.id);
        const lastUserMessage = messages.reverse().find(msg => msg.role === 'user');
        
        if (lastUserMessage) {
            await this.getAIResponse(lastUserMessage.content);
        }
    }
}

// Make available globally
window.ChatModule = ChatModule;

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = ChatModule;
}