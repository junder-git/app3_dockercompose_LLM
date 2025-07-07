// nginx/njs/chat.js - Chat handling functionality
import database from "./database.js";
import auth from "./auth.js";

async function handleChatRequest(r) {
    try {
        // Check authentication
        const authResult = await auth.verifyRequest(r);
        if (!authResult.success) {
            r.return(401, JSON.stringify({ error: "Authentication required" }));
            return;
        }

        const path = r.uri.replace('/api/chat/', '');
        const method = r.method;

        // Route chat requests
        if (path === 'send' && method === 'POST') {
            await handleSendMessage(r, authResult.user);
        } else if (path === 'history' && method === 'GET') {
            await handleGetHistory(r, authResult.user);
        } else {
            r.return(404, JSON.stringify({ error: "Chat endpoint not found" }));
        }

    } catch (e) {
        r.log('Chat error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Internal server error" }));
    }
}

async function handleSendMessage(r, user) {
    try {
        const body = r.requestBody;
        if (!body) {
            r.return(400, JSON.stringify({ error: "Message is required" }));
            return;
        }

        const data = JSON.parse(body);
        const message = data.message;

        if (!message || message.trim() === '') {
            r.return(400, JSON.stringify({ error: "Message cannot be empty" }));
            return;
        }

        // Generate chat ID
        const chatId = Date.now().toString() + '_' + user.id;

        // For now, return a simple echo response
        // In production, this would interface with Ollama
        const response = "Echo: " + message;

        // Save chat to database
        const saved = await database.saveChat(chatId, user.id, message, response);
        if (!saved) {
            r.log('Failed to save chat to database');
        }

        r.return(200, JSON.stringify({
            success: true,
            chat_id: chatId,
            message: message,
            response: response,
            timestamp: new Date().toISOString()
        }));

    } catch (e) {
        r.log('Send message error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to send message" }));
    }
}

async function handleGetHistory(r, user) {
    try {
        const chats = await database.getUserChats(user.id);
        
        r.return(200, JSON.stringify({
            success: true,
            chats: chats,
            total: chats.length
        }));

    } catch (e) {
        r.log('Get history error: ' + e.message);
        r.return(500, JSON.stringify({ error: "Failed to fetch chat history" }));
    }
}

export default { 
    handleChatRequest,
    handleSendMessage,
    handleGetHistory
};