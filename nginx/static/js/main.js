// nginx/static/js/main.js - SSE-only JavaScript for Chat Page
// This is the ONLY JavaScript file in the entire application

(function() {
    'use strict';
    
    // Only initialize on chat page
    if (!document.getElementById('chatMessages')) {
        return;
    }
    
    console.log('Initializing Devstral Chat SSE...');
    
    // SSE Connection Management
    let eventSource = null;
    let isConnected = false;
    let reconnectAttempts = 0;
    const maxReconnectAttempts = 5;
    const reconnectDelay = 2000;
    
    // DOM Elements
    const chatMessages = document.getElementById('chatMessages');
    const messageForm = document.getElementById('messageForm');
    const messageInput = document.getElementById('messageInput');
    const sendButton = document.getElementById('sendButton');
    const sseStatus = document.getElementById('sseStatus');
    const typingIndicator = document.getElementById('typingIndicator');
    const streamingMessage = document.getElementById('streamingMessage');
    const streamingContent = document.getElementById('streamingContent');
    const welcomeMessage = document.getElementById('welcomeMessage');
    
    // SSE Connection Functions
    function connectSSE() {
        if (eventSource) {
            eventSource.close();
        }
        
        showStatus('Connecting to Devstral...', 'info');
        eventSource = new EventSource('/sse');
        
        eventSource.onopen = function() {
            isConnected = true;
            reconnectAttempts = 0;
            showStatus('Connected to Devstral', 'success');
            setTimeout(() => hideStatus(), 3000);
        };
        
        eventSource.onmessage = function(event) {
            try {
                const data = JSON.parse(event.data);
                handleSSEMessage(data);
            } catch (e) {
                console.error('SSE parse error:', e);
            }
        };
        
        eventSource.onerror = function() {
            isConnected = false;
            eventSource.close();
            
            if (reconnectAttempts < maxReconnectAttempts) {
                reconnectAttempts++;
                showStatus(`Connection lost. Reconnecting... (${reconnectAttempts}/${maxReconnectAttempts})`, 'warning');
                setTimeout(connectSSE, reconnectDelay * reconnectAttempts);
            } else {
                showStatus('Connection failed. Please refresh the page.', 'danger');
            }
        };
    }
    
    // SSE Message Handler
    function handleSSEMessage(data) {
        switch (data.type) {
            case 'connected':
                console.log('SSE connected to Devstral');
                break;
                
            case 'message':
                addMessage(data.role, data.content, data.cached, data.timestamp);
                hideTyping();
                hideStreaming();
                enableInput();
                break;
                
            case 'stream':
                showStreaming(data.content);
                break;
                
            case 'typing':
                if (data.status === 'start') {
                    showTyping();
                } else {
                    hideTyping();
                }
                break;
                
            case 'complete':
                hideTyping();
                hideStreaming();
                enableInput();
                break;
                
            case 'error':
                showStatus(data.message, 'danger');
                hideTyping();
                hideStreaming();
                enableInput();
                break;
                
            case 'history':
                loadChatHistory(data.messages);
                break;
                
            case 'heartbeat':
                // Keep connection alive
                break;
                
            case 'session_created':
            case 'session_switched':
            case 'session_deleted':
                // Reload page for session changes
                setTimeout(() => window.location.reload(), 1000);
                break;
        }
    }
    
    // UI Functions
    function showStatus(message, type) {
        if (sseStatus) {
            sseStatus.className = `alert alert-${type}`;
            sseStatus.textContent = message;
            sseStatus.style.display = 'block';
        }
    }
    
    function hideStatus() {
        if (sseStatus) {
            sseStatus.style.display = 'none';
        }
    }
    
    function addMessage(role, content, cached = false, timestamp = null) {
        if (!chatMessages) return;
        
        // Hide welcome message
        if (welcomeMessage) {
            welcomeMessage.style.display = 'none';
        }
        
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${role === 'user' ? 'user-message' : 'assistant-message'} slide-in`;
        
        const contentDiv = document.createElement('div');
        contentDiv.className = 'message-content';
        contentDiv.innerHTML = escapeHtml(content);
        messageDiv.appendChild(contentDiv);
        
        if (timestamp) {
            const timestampDiv = document.createElement('small');
            timestampDiv.className = 'text-muted message-timestamp';
            timestampDiv.textContent = new Date(timestamp).toLocaleString();
            messageDiv.appendChild(timestampDiv);
        }
        
        if (cached && role === 'assistant') {
            const cachedDiv = document.createElement('div');
            cachedDiv.className = 'cached-indicator';
            cachedDiv.innerHTML = '<i class="bi bi-lightning-fill"></i> Cached response';
            messageDiv.appendChild(cachedDiv);
        }
        
        chatMessages.appendChild(messageDiv);
        scrollToBottom();
    }
    
    function showTyping() {
        if (typingIndicator) {
            typingIndicator.style.display = 'block';
            scrollToBottom();
        }
        if (welcomeMessage) {
            welcomeMessage.style.display = 'none';
        }
    }
    
    function hideTyping() {
        if (typingIndicator) {
            typingIndicator.style.display = 'none';
        }
    }
    
    function showStreaming(content) {
        if (!streamingMessage || !streamingContent) return;
        
        hideTyping();
        if (welcomeMessage) {
            welcomeMessage.style.display = 'none';
        }
        
        streamingMessage.style.display = 'block';
        streamingContent.textContent += content;
        scrollToBottom();
    }
    
    function hideStreaming() {
        if (streamingMessage && streamingContent) {
            // Move streaming content to a real message
            const content = streamingContent.textContent;
            if (content.trim()) {
                addMessage('assistant', content);
            }
            
            streamingMessage.style.display = 'none';
            streamingContent.textContent = '';
        }
    }
    
    function loadChatHistory(messages) {
        if (!chatMessages) return;
        
        // Clear existing messages except system elements
        const systemElements = chatMessages.querySelectorAll('#welcomeMessage, #typingIndicator, #streamingMessage');
        chatMessages.innerHTML = '';
        systemElements.forEach(el => chatMessages.appendChild(el));
        
        messages.forEach(msg => {
            addMessage(msg.role, msg.content, msg.cached, msg.timestamp);
        });
    }
    
    function enableInput() {
        if (sendButton) sendButton.disabled = false;
        if (messageInput) messageInput.disabled = false;
    }
    
    function disableInput() {
        if (sendButton) sendButton.disabled = true;
        if (messageInput) messageInput.disabled = true;
    }
    
    function scrollToBottom() {
        if (chatMessages) {
            chatMessages.scrollTop = chatMessages.scrollHeight;
        }
    }
    
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    
    // Form Handling
    if (messageForm) {
        messageForm.addEventListener('submit', function(e) {
            disableInput();
            hideStatus();
            
            // Add user message immediately
            const message = messageInput.value.trim();
            if (message) {
                addMessage('user', message, false, new Date().toISOString());
                messageInput.value = '';
            }
            
            // Form will submit normally, SSE will handle the response
        });
    }
    
    // Keyboard shortcuts
    if (messageInput) {
        messageInput.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey) {
                e.preventDefault();
                if (messageForm && !sendButton.disabled) {
                    messageForm.requestSubmit();
                }
            }
        });
    }
    
    // Initialize SSE connection
    connectSSE();
    
    // Cleanup on page unload
    window.addEventListener('beforeunload', function() {
        if (eventSource) {
            eventSource.close();
        }
    });
    
    // Auto-reconnect on page visibility change
    document.addEventListener('visibilitychange', function() {
        if (!document.hidden && !isConnected) {
            console.log('Page visible, attempting to reconnect SSE...');
            connectSSE();
        }
    });
    
    console.log('Devstral Chat SSE initialized successfully');
})();