// Add these functions to your client.js for streaming support

const initChat = async () => {
  console.log('Initializing chat page');
  const user = await checkAuth();
  if (!user) {
    window.location.href = '/login';
    return;
  }

  text('#username-display', user.username);

  const messagesContainer = $('#chat-messages');
  const messageInput = $('#message-input');
  const sendBtn = $('#send-btn');

  // WebSocket connection for streaming
  let ws = null;
  let isStreaming = false;

  const connectWebSocket = () => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ollama/api/chat`;
    
    ws = new WebSocket(wsUrl);
    
    ws.onopen = () => {
      console.log('WebSocket connected');
    };
    
    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        handleStreamingResponse(data);
      } catch (e) {
        console.error('Error parsing WebSocket message:', e);
      }
    };
    
    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
      showFlashMessage('Connection error occurred', 'error');
    };
    
    ws.onclose = () => {
      console.log('WebSocket disconnected');
      if (isStreaming) {
        // Reconnect if we were in the middle of streaming
        setTimeout(connectWebSocket, 1000);
      }
    };
  };

  let currentStreamingMessage = null;

  const handleStreamingResponse = (data) => {
    if (data.message && data.message.content) {
      if (!currentStreamingMessage) {
        // Create new streaming message
        currentStreamingMessage = createElement('div', 'message assistant-message');
        currentStreamingMessage.innerHTML = `
          <div class="message-content">
            <div class="ai-response" id="streaming-content"></div>
          </div>
          <span class="message-timestamp">${new Date().toLocaleTimeString()}</span>
        `;
        append(messagesContainer, currentStreamingMessage);
      }
      
      // Append new content
      const streamingContent = $('#streaming-content');
      if (streamingContent) {
        const currentText = streamingContent.textContent || '';
        streamingContent.textContent = currentText + data.message.content;
      }
      
      scrollTop(messagesContainer, messagesContainer.scrollHeight);
    }
    
    if (data.done) {
      isStreaming = false;
      currentStreamingMessage = null;
      prop(sendBtn, 'disabled', false);
      
      // Save the complete conversation to Redis
      const finalContent = $('#streaming-content')?.textContent;
      if (finalContent) {
        saveConversationToRedis(getLastUserMessage(), finalContent);
      }
    }
  };

  const saveConversationToRedis = async (userMessage, assistantResponse) => {
    try {
      const chatId = Date.now().toString() + '_' + user.id;
      
      await fetch('/redis/hset', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + getAuthToken()
        },
        body: JSON.stringify({
          key: `chat:${chatId}`,
          field: 'conversation',
          value: JSON.stringify({
            user_message: userMessage,
            assistant_response: assistantResponse,
            timestamp: new Date().toISOString(),
            user_id: user.id
          })
        })
      });
    } catch (error) {
      console.error('Failed to save conversation:', error);
    }
  };

  const getLastUserMessage = () => {
    const userMessages = messagesContainer.querySelectorAll('.user-message .user-text');
    return userMessages[userMessages.length - 1]?.textContent || '';
  };

  const sendMessage = async () => {
    const message = val(messageInput).trim();
    if (!message || isStreaming) return;

    val(messageInput, '');
    prop(sendBtn, 'disabled', true);
    isStreaming = true;

    // Add user message to chat
    const userMsg = createElement('div', 'message user-message');
    userMsg.innerHTML = `
      <div class="message-content">
        <div class="user-text">${escapeHtml(message)}</div>
      </div>
      <span class="message-timestamp">${new Date().toLocaleTimeString()}</span>
    `;
    append(messagesContainer, userMsg);
    scrollTop(messagesContainer, messagesContainer.scrollHeight);

    // Connect WebSocket if not connected
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      connectWebSocket();
      
      // Wait for connection
      await new Promise((resolve) => {
        const checkConnection = () => {
          if (ws && ws.readyState === WebSocket.OPEN) {
            resolve();
          } else {
            setTimeout(checkConnection, 100);
          }
        };
        checkConnection();
      });
    }

    // Send message via WebSocket
    const requestData = {
      model: "llama2", // or whatever model you're using
      messages: [
        {
          role: "user",
          content: message
        }
      ],
      stream: true
    };

    try {
      // Set auth header for WebSocket (this needs to be handled in nginx config)
      ws.send(JSON.stringify(requestData));
    } catch (error) {
      console.error('Failed to send message:', error);
      showFlashMessage('Failed to send message: ' + error.message, 'error');
      isStreaming = false;
      prop(sendBtn, 'disabled', false);
    }
  };

  // Initialize WebSocket connection
  connectWebSocket();

  on(sendBtn, 'click', sendMessage);
  on(messageInput, 'keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });

  // Cleanup on page unload
  window.addEventListener('beforeunload', () => {
    if (ws) {
      isStreaming = false;
      ws.close();
    }
  });
};

// Helper function to load chat history from Redis
const loadChatHistory = async () => {
  try {
    const user = await checkAuth();
    if (!user) return;

    const response = await fetch(`/redis/get?key=chat_history:${user.id}`, {
      headers: {
        'Authorization': 'Bearer ' + getAuthToken()
      }
    });

    if (response.ok) {
      const data = await response.json();
      if (data.success && data.value) {
        const history = JSON.parse(data.value);
        // Render chat history in the UI
        renderChatHistory(history);
      }
    }
  } catch (error) {
    console.error('Failed to load chat history:', error);
  }
};

const renderChatHistory = (history) => {
  const messagesContainer = $('#chat-messages');
  
  // Clear existing messages except welcome message
  const welcomeMsg = messagesContainer.querySelector('.assistant-message');
  messagesContainer.innerHTML = '';
  if (welcomeMsg) {
    append(messagesContainer, welcomeMsg);
  }

  // Render history
  history.forEach(chat => {
    // User message
    const userMsg = createElement('div', 'message user-message');
    userMsg.innerHTML = `
      <div class="message-content">
        <div class="user-text">${escapeHtml(chat.user_message)}</div>
      </div>
      <span class="message-timestamp">${new Date(chat.timestamp).toLocaleTimeString()}</span>
    `;
    append(messagesContainer, userMsg);

    // Assistant message
    const assistantMsg = createElement('div', 'message assistant-message');
    assistantMsg.innerHTML = `
      <div class="message-content">
        <div class="ai-response">${escapeHtml(chat.assistant_response)}</div>
      </div>
      <span class="message-timestamp">${new Date(chat.timestamp).toLocaleTimeString()}</span>
    `;
    append(messagesContainer, assistantMsg);
  });

  scrollTop(messagesContainer, messagesContainer.scrollHeight);
};