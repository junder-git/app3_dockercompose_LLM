const DevstralCommon = {
    async logout() {
        try {
            await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });

            // Clear cookies
            const cookies = ['access_token', 'session', 'auth_token'];
            cookies.forEach(name => {
                document.cookie = `${name}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax`;
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

    async loadUser() {
        try {
            const response = await fetch('/api/auth/me', { credentials: 'include' });
            const data = await response.json();
            if (data.success) {
                if (document.getElementById('navbar-username')) {
                    document.getElementById('navbar-username').textContent = data.username;
                }
                if (data.is_admin && document.getElementById('admin-nav')) {
                    document.getElementById('admin-nav').style.display = 'block';
                }
                if (document.getElementById('user-nav')) {
                    document.getElementById('user-nav').style.display = 'block';
                }
                if (document.getElementById('guest-nav')) {
                    document.getElementById('guest-nav').style.display = 'none';
                }
                if (document.getElementById('guest-nav-2')) {
                    document.getElementById('guest-nav-2').style.display = 'none';
                }
            } else {
                this.showGuest();
            }
        } catch (error) {
            console.warn('Failed to load user info:', error);
            this.showGuest();
        }
    },

    showGuest() {
        if (document.getElementById('guest-nav')) {
            document.getElementById('guest-nav').style.display = 'block';
        }
        if (document.getElementById('guest-nav-2')) {
            document.getElementById('guest-nav-2').style.display = 'block';
        }
        if (document.getElementById('user-nav')) {
            document.getElementById('user-nav').style.display = 'none';
        }
        if (document.getElementById('admin-nav')) {
            document.getElementById('admin-nav').style.display = 'none';
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
            card.style.animationDelay = `${index * 0.1}s`;
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
                    console.log(`User interaction: ${key}`);
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
            console.log(`Page load time: ${loadTime}ms`);

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
                    console.warn(`Low FPS detected: ${fps} fps`);
                }
            }

            requestAnimationFrame(monitorFPS);
        }

        setTimeout(() => {
            monitorFPS();
        }, 2000);
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
});
