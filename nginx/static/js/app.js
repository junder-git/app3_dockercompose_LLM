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

// Initialize Prism.js for syntax highlighting
/* function initializePrism() {
    // Load Prism.js CSS
    const prismCSS = document.createElement('link');
    prismCSS.rel = 'stylesheet';
    prismCSS.href = '/cdn/npm/prismjs@1.29.0/themes/prism-tomorrow.css';
    document.head.appendChild(prismCSS);

    // Configure Prism autoloader if available
    if (window.Prism && window.Prism.plugins && window.Prism.plugins.autoloader) {
        window.Prism.plugins.autoloader.languages_path = '/cdn/npm/prismjs@1.29.0/components/';
    }
    
    // Load additional language components manually if autoloader isn't working
    const languages = ['markup', 'css', 'javascript', 'python', 'java', 'cpp', 'csharp', 'php', 'ruby', 'go', 'rust', 'kotlin', 'swift', 'sql', 'bash', 'json', 'yaml', 'markdown'];
    languages.forEach(lang => {
        const script = document.createElement('script');
        script.src = `/cdn/npm/prismjs@1.29.0/components/prism-${lang}.min.js`;
        script.async = true;
        document.head.appendChild(script);
    });
} */

// Page-specific initialization
document.addEventListener('DOMContentLoaded', function() {
    // Initialize Prism.js for syntax highlighting
    //initializePrism();

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
    
    // Apply syntax highlighting to any existing code blocks
    /*setTimeout(() => {
        if (window.Prism) {
            window.Prism.highlightAll();
        }
    }, 500); */
});