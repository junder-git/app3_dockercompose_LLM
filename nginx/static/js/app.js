// static/js/app.js - Main Application Entry Point

// Global app namespace
const ChatApp = {
    ws: null,
    currentStreamMessage: null,
    isWaitingForResponse: false,
    currentPage: null,
    githubToken: localStorage.getItem('github_token') || null,
    githubUsername: localStorage.getItem('github_username') || null
};

// Make ChatApp globally available
window.ChatApp = ChatApp;

// Register Page Handler (simple, so keeping in main file)
const RegisterPage = {
    init: function() {
        const form = document.querySelector('form');
        if (form) {
            form.addEventListener('submit', function(e) {
                const password = document.getElementById('password').value;
                const confirmPassword = document.getElementById('confirm_password').value;
                
                if (password !== confirmPassword) {
                    e.preventDefault();
                    alert('Passwords do not match!');
                }
            });
        }
    }
};

// Page-specific initialization
document.addEventListener('DOMContentLoaded', function() {
    // Load Prism.js for syntax highlighting
    const prismCSS = document.createElement('link');
    prismCSS.rel = 'stylesheet';
    prismCSS.href = '/cdn/npm/prismjs@1.29.0/themes/prism-tomorrow.css';
    document.head.appendChild(prismCSS);

    const prismJS = document.createElement('script');
    prismJS.src = '/cdn/npm/prismjs@1.29.0/components/prism-core.min.js';
    prismJS.onload = () => {
        // Load additional language components
        const languages = ['markup', 'css', 'javascript', 'python', 'java', 'cpp', 'csharp', 'php', 'ruby', 'go', 'rust', 'kotlin', 'swift', 'sql', 'bash', 'json', 'yaml', 'markdown'];
        languages.forEach(lang => {
            const script = document.createElement('script');
            script.src = `/cdn/npm/prismjs@1.29.0/components/prism-${lang}.min.js`;
            document.head.appendChild(script);
        });
    };
    document.head.appendChild(prismJS);

    // Initialize GitHub integration
    if (window.GitHubIntegration) {
        GitHubIntegration.init();
    }

    // Detect current page
    const path = window.location.pathname;
    
    if (path === '/chat') {
        ChatApp.currentPage = 'chat';
        if (window.ChatPage) {
            ChatPage.init();
        }
    } else if (path === '/admin') {
        ChatApp.currentPage = 'admin';
        if (window.AdminPage) {
            AdminPage.init();
        }
    } else if (path === '/register') {
        ChatApp.currentPage = 'register';
        RegisterPage.init();
    }
});