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