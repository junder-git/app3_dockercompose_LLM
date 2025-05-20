/* File: graphql-client.js
   Directory: /deepseek-coder-setup/web-ui/static/js/ */

/**
 * GraphQL client for DeepSeek-Coder
 * A simple client for making GraphQL requests to the API
 */

// GraphQL endpoint URL
const GRAPHQL_URL = '/graphql';

/**
 * Execute a GraphQL query or mutation
 * @param {string} query - The GraphQL query/mutation
 * @param {Object} variables - Variables for the query/mutation
 * @returns {Promise<Object>} - The query result
 */
async function executeGraphQL(query, variables = {}) {
    try {
        const response = await fetch(GRAPHQL_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
            },
            body: JSON.stringify({
                query,
                variables
            }),
            credentials: 'include'
        });

        const result = await response.json();

        if (result.errors) {
            console.error('GraphQL errors:', result.errors);
            throw new Error(result.errors[0].message);
        }

        return result.data;
    } catch (error) {
        console.error('Error executing GraphQL:', error);
        throw error;
    }
}

/**
 * Get the current user
 * @returns {Promise<Object>} - Current user data
 */
async function getCurrentUser() {
    const query = `
        query Me {
            me {
                id
                username
                email
                fullName
                isAdmin
                createdAt
                lastLogin
            }
        }
    `;

    const data = await executeGraphQL(query);
    return data.me;
}

/**
 * Get all chats (active or archived)
 * @param {boolean} archived - Whether to get archived chats
 * @returns {Promise<Array>} - List of chats
 */
async function getChats(archived = false) {
    const query = `
        query Chats($archived: Boolean!) {
            chats(archived: $archived) {
                id
                title
                createdAt
                updatedAt
                isArchived
            }
        }
    `;

    const data = await executeGraphQL(query, { archived });
    return data.chats;
}

/**
 * Get a specific chat with messages and artifacts
 * @param {number} chatId - The chat ID
 * @returns {Promise<Object>} - Chat data with messages and artifacts
 */
async function getChat(chatId) {
    const query = `
        query Chat($id: Int!) {
            chat(id: $id) {
                id
                title
                createdAt
                updatedAt
                isArchived
                messages {
                    id
                    chatId
                    role
                    content
                    createdAt
                }
                artifacts {
                    id
                    chatId
                    messageId
                    title
                    language
                    createdAt
                }
            }
        }
    `;

    const data = await executeGraphQL(query, { id: chatId });
    return data.chat;
}

/**
 * Create a new chat
 * @param {string} title - The chat title
 * @returns {Promise<Object>} - The created chat
 */
async function createChat(title) {
    const mutation = `
        mutation CreateChat($input: ChatInput!) {
            createChat(input: $input) {
                id
                title
                createdAt
                updatedAt
                isArchived
            }
        }
    `;

    const data = await executeGraphQL(mutation, { 
        input: { title } 
    });
    return data.createChat;
}

/**
 * Update a chat title
 * @param {number} chatId - The chat ID
 * @param {string} title - The new title
 * @returns {Promise<Object>} - The updated chat
 */
async function updateChatTitle(chatId, title) {
    const mutation = `
        mutation UpdateChatTitle($id: Int!, $title: String!) {
            updateChatTitle(id: $id, title: $title) {
                id
                title
                createdAt
                updatedAt
            }
        }
    `;

    const data = await executeGraphQL(mutation, { 
        id: chatId,
        title
    });
    return data.updateChatTitle;
}

/**
 * Archive a chat
 * @param {number} chatId - The chat ID
 * @returns {Promise<Object>} - The archived chat
 */
async function archiveChat(chatId) {
    const mutation = `
        mutation ArchiveChat($id: Int!) {
            archiveChat(id: $id) {
                id
                title
                isArchived
            }
        }
    `;

    const data = await executeGraphQL(mutation, { id: chatId });
    return data.archiveChat;
}

/**
 * Restore an archived chat
 * @param {number} chatId - The chat ID
 * @returns {Promise<Object>} - The restored chat
 */
async function restoreChat(chatId) {
    const mutation = `
        mutation RestoreChat($id: Int!) {
            restoreChat(id: $id) {
                id
                title
                isArchived
            }
        }
    `;

    const data = await executeGraphQL(mutation, { id: chatId });
    return data.restoreChat;
}

/**
 * Delete a chat
 * @param {number} chatId - The chat ID
 * @returns {Promise<boolean>} - Success status
 */
async function deleteChat(chatId) {
    const mutation = `
        mutation DeleteChat($id: Int!) {
            deleteChat(id: $id)
        }
    `;

    const data = await executeGraphQL(mutation, { id: chatId });
    return data.deleteChat;
}

/**
 * Get all active sessions
 * @returns {Promise<Array>} - List of sessions
 */
async function getSessions() {
    const query = `
        query Sessions {
            sessions {
                id
                userId
                createdAt
                expiresAt
                ipAddress
                userAgent
                isCurrent
            }
        }
    `;

    const data = await executeGraphQL(query);
    return data.sessions;
}

// Export all functions
window.graphqlClient = {
    executeGraphQL,
    getCurrentUser,
    getChats,
    getChat,
    createChat,
    updateChatTitle,
    archiveChat,
    restoreChat,
    deleteChat,
    getSessions
};