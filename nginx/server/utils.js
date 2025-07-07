// utils.js - Utility Functions

class Utils {
    // =====================================================
    // STRING UTILITIES
    // =====================================================

    static escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    static unescapeHtml(html) {
        const div = document.createElement('div');
        div.innerHTML = html;
        return div.textContent || div.innerText || '';
    }

    static truncateText(text, maxLength) {
        if (!text || text.length <= maxLength) return text;
        return text.substring(0, maxLength - 3) + '...';
    }

    static capitalizeFirst(str) {
        if (!str) return '';
        return str.charAt(0).toUpperCase() + str.slice(1);
    }

    static generateRandomId(prefix = 'id') {
        return `${prefix}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    static slugify(text) {
        return text
            .toString()
            .toLowerCase()
            .replace(/\s+/g, '-')
            .replace(/[^\w\-]+/g, '')
            .replace(/\-\-+/g, '-')
            .replace(/^-+/, '')
            .replace(/-+$/, '');
    }

    // =====================================================
    // DATE/TIME UTILITIES
    // =====================================================

    static formatTimestamp(timestamp) {
        if (!timestamp) return 'Unknown';
        const date = new Date(timestamp);
        return date.toLocaleString();
    }

    static formatRelativeTime(timestamp) {
        if (!timestamp) return 'Unknown';
        
        const date = new Date(timestamp);
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMs / 3600000);
        const diffDays = Math.floor(diffMs / 86400000);
        const diffWeeks = Math.floor(diffMs / 604800000);

        if (diffMins < 1) return 'Just now';
        if (diffMins < 60) return `${diffMins} minute${diffMins === 1 ? '' : 's'} ago`;
        if (diffHours < 24) return `${diffHours} hour${diffHours === 1 ? '' : 's'} ago`;
        if (diffDays < 7) return `${diffDays} day${diffDays === 1 ? '' : 's'} ago`;
        if (diffWeeks < 4) return `${diffWeeks} week${diffWeeks === 1 ? '' : 's'} ago`;
        
        return date.toLocaleDateString();
    }

    static formatDuration(ms) {
        if (ms < 1000) return `${ms}ms`;
        if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
        if (ms < 3600000) return `${(ms / 60000).toFixed(1)}m`;
        return `${(ms / 3600000).toFixed(1)}h`;
    }

    static getCurrentTimestamp() {
        return new Date().toISOString();
    }

    // =====================================================
    // VALIDATION UTILITIES
    // =====================================================

    static isValidEmail(email) {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    }

    static isValidUsername(username) {
        // 3-50 characters, alphanumeric, underscore, hyphen
        const usernameRegex = /^[a-zA-Z0-9_-]{3,50}$/;
        return usernameRegex.test(username);
    }

    static isValidPassword(password) {
        // At least 6 characters
        return password && password.length >= 6;
    }

    static validateInput(value, type, options = {}) {
        if (!value && options.required) {
            return { valid: false, message: 'This field is required' };
        }

        if (!value) {
            return { valid: true };
        }

        switch (type) {
            case 'username':
                if (!this.isValidUsername(value)) {
                    return { valid: false, message: 'Username must be 3-50 characters, letters, numbers, underscore, and dash only' };
                }
                break;

            case 'password':
                if (!this.isValidPassword(value)) {
                    return { valid: false, message: 'Password must be at least 6 characters' };
                }
                break;

            case 'email':
                if (!this.isValidEmail(value)) {
                    return { valid: false, message: 'Please enter a valid email address' };
                }
                break;

            case 'text':
                if (options.minLength && value.length < options.minLength) {
                    return { valid: false, message: `Must be at least ${options.minLength} characters` };
                }
                if (options.maxLength && value.length > options.maxLength) {
                    return { valid: false, message: `Must be no more than ${options.maxLength} characters` };
                }
                break;
        }

        return { valid: true };
    }

    // =====================================================
    // FORMAT UTILITIES
    // =====================================================

    static formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    static formatNumber(num) {
        return new Intl.NumberFormat().format(num);
    }

    static formatPercentage(value, total) {
        if (total === 0) return '0%';
        return Math.round((value / total) * 100) + '%';
    }

    // =====================================================
    // UI UTILITIES
    // =====================================================

    static showFlashMessage(message, type = 'info', duration = 5000) {
        const alertClass = type === 'error' ? 'danger' : type;
        const iconClass = {
            'success': 'check-circle',
            'danger': 'exclamation-triangle',
            'warning': 'exclamation-triangle',
            'info': 'info-circle'
        }[alertClass] || 'info-circle';
        
        const html = `
            <div class="alert alert-${alertClass} alert-dismissible fade show">
                <i class="bi bi-${iconClass}"></i> ${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        `;
        
        $('#flash-messages').html(html);
        
        // Auto-dismiss
        if (duration > 0) {
            setTimeout(() => {
                $('#flash-messages .alert').alert('close');
            }, duration);
        }
    }

    static showLoadingSpinner(element, text = 'Loading...') {
        const $element = $(element);
        $element.prop('disabled', true);
        $element.data('original-html', $element.html());
        $element.html(`<span class="spinner-border spinner-border-sm" role="status"></span> ${text}`);
    }

    static hideLoadingSpinner(element) {
        const $element = $(element);
        $element.prop('disabled', false);
        const originalHtml = $element.data('original-html');
        if (originalHtml) {
            $element.html(originalHtml);
            $element.removeData('original-html');
        }
    }

    static showModal(title, content, actions = []) {
        const modalId = this.generateRandomId('modal');
        
        let actionsHtml = '';
        if (actions.length === 0) {
            actionsHtml = '<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>';
        } else {
            actionsHtml = actions.map(action => 
                `<button type="button" class="btn btn-${action.type || 'primary'}" 
                 onclick="${action.onclick || ''}" 
                 ${action.dismiss ? 'data-bs-dismiss="modal"' : ''}>
                 ${action.text}
                 </button>`
            ).join(' ');
        }
        
        const modalHtml = `
            <div class="modal fade" id="${modalId}" tabindex="-1">
                <div class="modal-dialog">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h5 class="modal-title">${title}</h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                        </div>
                        <div class="modal-body">
                            ${content}
                        </div>
                        <div class="modal-footer">
                            ${actionsHtml}
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        $('body').append(modalHtml);
        const modal = new bootstrap.Modal(document.getElementById(modalId));
        
        // Clean up modal when hidden
        $(`#${modalId}`).on('hidden.bs.modal', function() {
            $(this).remove();
        });
        
        modal.show();
        return modal;
    }

    static confirmDialog(title, message, onConfirm, onCancel = null) {
        return this.showModal(title, message, [
            {
                text: 'Cancel',
                type: 'secondary',
                dismiss: true,
                onclick: onCancel ? `(${onCancel})()` : ''
            },
            {
                text: 'Confirm',
                type: 'primary',
                dismiss: true,
                onclick: `(${onConfirm})()`
            }
        ]);
    }

    // =====================================================
    // ARRAY/OBJECT UTILITIES
    // =====================================================

    static deepClone(obj) {
        return JSON.parse(JSON.stringify(obj));
    }

    static isEmpty(value) {
        if (value == null) return true;
        if (typeof value === 'string') return value.trim().length === 0;
        if (Array.isArray(value)) return value.length === 0;
        if (typeof value === 'object') return Object.keys(value).length === 0;
        return false;
    }

    static groupBy(array, key) {
        return array.reduce((groups, item) => {
            const group = item[key];
            if (!groups[group]) {
                groups[group] = [];
            }
            groups[group].push(item);
            return groups;
        }, {});
    }

    static sortBy(array, key, direction = 'asc') {
        return array.sort((a, b) => {
            let aVal = a[key];
            let bVal = b[key];
            
            if (typeof aVal === 'string') aVal = aVal.toLowerCase();
            if (typeof bVal === 'string') bVal = bVal.toLowerCase();
            
            if (direction === 'desc') {
                return bVal > aVal ? 1 : -1;
            }
            return aVal > bVal ? 1 : -1;
        });
    }

    static unique(array) {
        return [...new Set(array)];
    }

    static chunk(array, size) {
        const chunks = [];
        for (let i = 0; i < array.length; i += size) {
            chunks.push(array.slice(i, i + size));
        }
        return chunks;
    }

    // =====================================================
    // LOCAL STORAGE UTILITIES
    // =====================================================

    static setLocalStorage(key, value) {
        try {
            localStorage.setItem(key, JSON.stringify(value));
            return true;
        } catch (error) {
            console.error('Error setting localStorage:', error);
            return false;
        }
    }

    static getLocalStorage(key, defaultValue = null) {
        try {
            const item = localStorage.getItem(key);
            return item ? JSON.parse(item) : defaultValue;
        } catch (error) {
            console.error('Error getting localStorage:', error);
            return defaultValue;
        }
    }

    static removeLocalStorage(key) {
        try {
            localStorage.removeItem(key);
            return true;
        } catch (error) {
            console.error('Error removing localStorage:', error);
            return false;
        }
    }

    static clearLocalStorage() {
        try {
            localStorage.clear();
            return true;
        } catch (error) {
            console.error('Error clearing localStorage:', error);
            return false;
        }
    }

    // =====================================================
    // HTTP UTILITIES
    // =====================================================

    static async makeRequest(url, options = {}) {
        const defaultOptions = {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json'
            }
        };

        const finalOptions = { ...defaultOptions, ...options };

        try {
            const response = await fetch(url, finalOptions);
            
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const contentType = response.headers.get('content-type');
            if (contentType && contentType.includes('application/json')) {
                return await response.json();
            } else {
                return await response.text();
            }
        } catch (error) {
            console.error('Request error:', error);
            throw error;
        }
    }

    static buildQueryString(params) {
        return new URLSearchParams(params).toString();
    }

    // =====================================================
    // CRYPTO UTILITIES
    // =====================================================

    static async generateHash(data) {
        const encoder = new TextEncoder();
        const encodedData = encoder.encode(data);
        const hashBuffer = await crypto.subtle.digest('SHA-256', encodedData);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    }

    static generateRandomString(length = 16) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        let result = '';
        for (let i = 0; i < length; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return result;
    }

    static generateUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            const r = Math.random() * 16 | 0;
            const v = c == 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }

    // =====================================================
    // MARKDOWN UTILITIES
    // =====================================================

    static renderMarkdown(text) {
        if (!text) return '';
        
        // Simple markdown renderer - for production, consider using a proper library
        let html = text
            // Headers
            .replace(/^### (.*$)/gim, '<h3>$1</h3>')
            .replace(/^## (.*$)/gim, '<h2>$1</h2>')
            .replace(/^# (.*$)/gim, '<h1>$1</h1>')
            
            // Bold
            .replace(/\*\*(.*)\*\*/gim, '<strong>$1</strong>')
            .replace(/__(.*?)__/gim, '<strong>$1</strong>')
            
            // Italic
            .replace(/\*(.*)\*/gim, '<em>$1</em>')
            .replace(/_(.*?)_/gim, '<em>$1</em>')
            
            // Code blocks
            .replace(/```([\s\S]*?)```/gim, '<pre><code>$1</code></pre>')
            .replace(/`(.*?)`/gim, '<code>$1</code>')
            
            // Links
            .replace(/\[([^\]]+)\]\(([^)]+)\)/gim, '<a href="$2" target="_blank">$1</a>')
            
            // Line breaks
            .replace(/\n\n/gim, '</p><p>')
            .replace(/\n/gim, '<br>');
        
        // Wrap in paragraph tags
        html = '<p>' + html + '</p>';
        
        // Clean up empty paragraphs
        html = html.replace(/<p><\/p>/gim, '');
        
        return html;
    }

    // =====================================================
    // PERFORMANCE UTILITIES
    // =====================================================

    static debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }

    static throttle(func, limit) {
        let inThrottle;
        return function() {
            const args = arguments;
            const context = this;
            if (!inThrottle) {
                func.apply(context, args);
                inThrottle = true;
                setTimeout(() => inThrottle = false, limit);
            }
        };
    }

    static memoize(func) {
        const cache = {};
        return function(...args) {
            const key = JSON.stringify(args);
            if (cache[key]) {
                return cache[key];
            }
            const result = func.apply(this, args);
            cache[key] = result;
            return result;
        };
    }

    // =====================================================
    // ERROR HANDLING
    // =====================================================

    static handleError(error, context = '') {
        console.error(`Error in ${context}:`, error);
        
        let userMessage = 'An unexpected error occurred.';
        
        if (error.message) {
            userMessage = error.message;
        } else if (typeof error === 'string') {
            userMessage = error;
        }
        
        this.showFlashMessage(userMessage, 'error');
        
        return {
            success: false,
            error: userMessage,
            timestamp: this.getCurrentTimestamp()
        };
    }

    static async withErrorHandling(asyncFunc, context = '') {
        try {
            const result = await asyncFunc();
            return { success: true, data: result };
        } catch (error) {
            return this.handleError(error, context);
        }
    }

    // =====================================================
    // BROWSER DETECTION
    // =====================================================

    static getBrowserInfo() {
        const ua = navigator.userAgent;
        let browser = 'Unknown';
        
        if (ua.includes('Chrome')) browser = 'Chrome';
        else if (ua.includes('Firefox')) browser = 'Firefox';
        else if (ua.includes('Safari')) browser = 'Safari';
        else if (ua.includes('Edge')) browser = 'Edge';
        else if (ua.includes('Opera')) browser = 'Opera';
        
        return {
            browser,
            userAgent: ua,
            isMobile: /Mobi|Android/i.test(ua),
            isTablet: /Tablet|iPad/i.test(ua)
        };
    }

    static isMobileDevice() {
        return window.innerWidth <= 768 || /Mobi|Android/i.test(navigator.userAgent);
    }

    // =====================================================
    // DOWNLOAD/EXPORT UTILITIES
    // =====================================================

    static downloadJSON(data, filename = 'data.json') {
        const json = JSON.stringify(data, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        this.downloadBlob(blob, filename);
    }

    static downloadText(text, filename = 'data.txt') {
        const blob = new Blob([text], { type: 'text/plain' });
        this.downloadBlob(blob, filename);
    }

    static downloadBlob(blob, filename) {
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }

    // =====================================================
    // COPY TO CLIPBOARD
    // =====================================================

    static async copyToClipboard(text) {
        try {
            await navigator.clipboard.writeText(text);
            this.showFlashMessage('Copied to clipboard!', 'success', 2000);
            return true;
        } catch (error) {
            console.error('Copy failed:', error);
            // Fallback method
            const textArea = document.createElement('textarea');
            textArea.value = text;
            document.body.appendChild(textArea);
            textArea.select();
            try {
                document.execCommand('copy');
                this.showFlashMessage('Copied to clipboard!', 'success', 2000);
                return true;
            } catch (fallbackError) {
                this.showFlashMessage('Failed to copy to clipboard', 'error');
                return false;
            } finally {
                document.body.removeChild(textArea);
            }
        }
    }
}

// Make Utils available globally
window.Utils = Utils;

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = Utils;
}