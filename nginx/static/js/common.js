const DevstralCommon = {
    async logout() {
        try {
            await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });

            // Clear cookies
            const cookies = ['access_token', 'session', 'auth_token'];
            cookies.forEach(name => {
                document.cookie = name + '=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax';
            });

            // Clear storage
            localStorage.clear();
            sessionStorage.clear();

            // Redirect and force reload
            window.location.href = '/?clear_cache=1';
        } catch (err) {
            console.error('Logout failed', err);
        }
    },

    setupSmoothScrolling() {
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                const target = document.querySelector(this.getAttribute('href'));
                if (target) {
                    target.scrollIntoView({
                        behavior: 'smooth',
                        block: 'start'
                    });
                }
            });
        });
    },

    setupFeatureCardAnimations() {
        const featureCards = document.querySelectorAll('.feature-card');

        featureCards.forEach((card, index) => {
            card.style.animationDelay = (index * 0.1) + 's';
            card.classList.add('animate-in');

            card.addEventListener('mouseenter', function () {
                this.style.transform = 'translateY(-8px) scale(1.02)';
                this.style.boxShadow = '0 15px 40px rgba(13, 110, 253, 0.3)';
            });

            card.addEventListener('mouseleave', function () {
                this.style.transform = 'translateY(0) scale(1)';
                this.style.boxShadow = '0 10px 30px rgba(13, 110, 253, 0.2)';
            });
        });
    },

    setupKeyboardNavigation() {
        document.addEventListener('keydown', function (e) {
            if (e.altKey && e.key === 'h') {
                e.preventDefault();
                window.location.href = '/';
            }
            if (e.altKey && e.key === 'c') {
                e.preventDefault();
                window.location.href = '/chat.html';
            }
            if (e.altKey && e.key === 'l') {
                e.preventDefault();
                window.location.href = '/login.html';
            }
            if (e.altKey && e.key === 'r') {
                e.preventDefault();
                window.location.href = '/register.html';
            }
        });
    },

    setupAnalytics() {
        const trackableElements = {
            'cta-start-chat': document.querySelector('.cta-button[href*="chat"]'),
            'cta-get-started': document.querySelector('.btn[href*="register"]'),
            'nav-chat': document.querySelector('.nav-link[href*="chat"]'),
            'nav-login': document.querySelector('.nav-link[href*="login"]'),
            'nav-register': document.querySelector('.nav-link[href*="register"]')
        };

        Object.entries(trackableElements).forEach(([key, element]) => {
            if (element) {
                element.addEventListener('click', function () {
                    console.log('User interaction: ' + key);
                    DevstralCommon.trackEvent('button_click', key);
                });
            }
        });
    },

    trackEvent(action, label) {
        const event = {
            timestamp: new Date().toISOString(),
            action: action,
            label: label,
            page: window.location.pathname,
            userAgent: navigator.userAgent.substring(0, 100)
        };

        console.log('Event tracked:', event);

        // You can POST this to your analytics server here
        // fetch('/api/analytics/track', { method: 'POST', body: JSON.stringify(event) });
    },

    setupPerformanceMonitoring() {
        window.addEventListener('load', function () {
            const loadTime = performance.timing.loadEventEnd - performance.timing.navigationStart;
            console.log('Page load time: ' + loadTime + 'ms');

            if (loadTime > 3000) {
                console.warn('Page load time is slow, consider optimization');
            }
        });

        let lastFrameTime = performance.now();
        let frameCount = 0;
        let fps = 0;

        function monitorFPS() {
            const currentTime = performance.now();
            frameCount++;

            if (currentTime - lastFrameTime >= 1000) {
                fps = Math.round((frameCount * 1000) / (currentTime - lastFrameTime));
                frameCount = 0;
                lastFrameTime = currentTime;

                if (fps < 30) {
                    console.warn('Low FPS detected: ' + fps + ' fps');
                }
            }

            requestAnimationFrame(monitorFPS);
        }

        setTimeout(() => {
            monitorFPS();
        }, 2000);
    },

    // Utility function to show notifications
    showNotification(message, type, duration) {
        type = type || 'info';
        duration = duration || 3000;

        // Create notification element
        const notification = document.createElement('div');
        notification.className = 'alert alert-' + type + ' alert-dismissible fade show position-fixed';
        notification.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
        notification.innerHTML = message + 
            '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>';

        document.body.appendChild(notification);

        // Auto-remove after duration
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, duration);
    },

    // Utility function to format dates consistently
    formatDate(dateString) {
        try {
            const date = new Date(dateString);
            return date.toLocaleDateString() + ' ' + 
                   date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
        } catch (error) {
            return 'Invalid date';
        }
    },

    // Utility function to debounce function calls
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    },

    // Utility function to validate input
    validateInput(input, type) {
        switch (type) {
            case 'username':
                return /^[a-zA-Z0-9_]{3,20}$/.test(input);
            case 'password':
                return input.length >= 6;
            case 'email':
                return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input);
            default:
                return true;
        }
    },

    // Copy text to clipboard
    async copyToClipboard(text) {
        try {
            await navigator.clipboard.writeText(text);
            this.showNotification('Copied to clipboard!', 'success', 2000);
            return true;
        } catch (error) {
            console.error('Failed to copy to clipboard:', error);
            this.showNotification('Failed to copy to clipboard', 'error', 3000);
            return false;
        }
    },

    // Safe JSON parse
    safeJSONParse(jsonString, defaultValue) {
        try {
            return JSON.parse(jsonString);
        } catch (error) {
            console.warn('Failed to parse JSON:', error);
            return defaultValue || null;
        }
    },

    // Get URL parameters
    getUrlParameter(name) {
        const urlParams = new URLSearchParams(window.location.search);
        return urlParams.get(name);
    },

    // Set URL parameter without page reload
    setUrlParameter(name, value) {
        const url = new URL(window.location);
        url.searchParams.set(name, value);
        window.history.pushState({}, '', url);
    },

    // Remove URL parameter without page reload
    removeUrlParameter(name) {
        const url = new URL(window.location);
        url.searchParams.delete(name);
        window.history.pushState({}, '', url);
    },

    // Check if user is on mobile device
    isMobile() {
        return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
    },

    // Check if user prefers dark mode
    prefersDarkMode() {
        return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    },

    // Escape HTML to prevent XSS
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    // Truncate text with ellipsis
    truncateText(text, maxLength) {
        if (text.length <= maxLength) return text;
        return text.substr(0, maxLength) + '...';
    },

    // Generate random ID
    generateId(prefix) {
        prefix = prefix || 'id';
        return prefix + '-' + Math.random().toString(36).substr(2, 9);
    }
};

document.addEventListener('DOMContentLoaded', () => {
    // Universal logout button handler
    const logoutBtn = document.getElementById('logout-button');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', (e) => {
            e.preventDefault();
            DevstralCommon.logout();
        });
    }

    // Initialize performance monitoring in development
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
        DevstralCommon.setupPerformanceMonitoring();
    }
});