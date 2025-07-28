// =============================================================================
// nginx/static/js/is_shared_code.js - ENHANCED WITH PRISM.JS AND EXPAND/COLLAPSE
// =============================================================================

// =============================================================================
// CODE PANEL MANAGEMENT
// =============================================================================

class CodePanelManager {
    constructor() {
        this.setupCodePanel();
        this.currentArtifactId = null;
    }
    
    setupCodePanel() {
        // Set up copy button
        const copyBtn = document.getElementById('copy-code-btn');
        if (copyBtn) {
            copyBtn.addEventListener('click', () => this.copyCode());
        }
        
        // Set up close button
        const closeBtn = document.getElementById('close-code-btn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => this.hideCode());
        }
    }
    
    showCode(codeContent, language = '', filename = '', artifactId = null) {
        console.log(`🔍 CodePanel.showCode called:`, {
            contentLength: codeContent ? codeContent.length : 0,
            language,
            filename,
            artifactId,
            contentPreview: codeContent ? codeContent.substring(0, 100) + '...' : 'No content'
        });
        
        const codeDisplay = document.getElementById('code-display');
        const lineNumbers = document.getElementById('code-line-numbers');
        const editorContainer = document.getElementById('code-editor-container');
        const placeholder = document.querySelector('.code-panel-placeholder');
        const copyBtn = document.getElementById('copy-code-btn');
        const closeBtn = document.getElementById('close-code-btn');
        
        if (!codeDisplay || !lineNumbers || !editorContainer || !placeholder) {
            console.error('❌ Code panel elements not found:', {
                codeDisplay: !!codeDisplay,
                lineNumbers: !!lineNumbers,
                editorContainer: !!editorContainer,
                placeholder: !!placeholder
            });
            return;
        }
        
        if (!codeContent || codeContent.trim() === '') {
            console.warn('⚠️ No code content provided or content is empty');
            return;
        }
        
        // Hide placeholder and show editor
        placeholder.style.display = 'none';
        editorContainer.style.display = 'flex';
        
        this.currentArtifactId = artifactId;
        
        // Set code content
        codeDisplay.value = codeContent;
        codeDisplay.style.color = '#cccccc'; // Ensure text is visible
        
        // Generate line numbers
        const lines = codeContent.split('\n');
        const lineNumberText = lines.map((_, index) => index + 1).join('\n');
        lineNumbers.value = lineNumberText;
        
        // Sync scroll between line numbers and code
        const syncScroll = () => {
            lineNumbers.scrollTop = codeDisplay.scrollTop;
        };
        
        // Remove existing listeners to prevent duplicates
        codeDisplay.removeEventListener('scroll', syncScroll);
        codeDisplay.addEventListener('scroll', syncScroll);
        
        // Update header title
        const headerTitle = document.querySelector('.code-panel-header h6');
        if (headerTitle) {
            const icon = '<i class="bi bi-code-square"></i>';
            if (filename && filename !== artifactId) {
                headerTitle.innerHTML = `${icon} ${filename}`;
            } else if (artifactId) {
                headerTitle.innerHTML = `${icon} ${artifactId}${language ? ` (${language})` : ''}`;
            } else if (language) {
                headerTitle.innerHTML = `${icon} ${language.toUpperCase()} Code`;
            } else {
                headerTitle.innerHTML = `${icon} Code Viewer`;
            }
        }
        
        if (copyBtn) copyBtn.style.display = 'inline-block';
        if (closeBtn) closeBtn.style.display = 'inline-block';
        
        console.log('✅ Code displayed in panel successfully');
        
        // Force a repaint to ensure content is visible
        setTimeout(() => {
            codeDisplay.scrollTop = 0;
            lineNumbers.scrollTop = 0;
        }, 10);
    }
    
    updateStreamingCode(codeContent) {
        const codeDisplay = document.getElementById('code-display');
        const lineNumbers = document.getElementById('code-line-numbers');
        
        if (codeDisplay && lineNumbers) {
            // Update code content with streaming cursor
            codeDisplay.value = codeContent + '▋';
            
            // Update line numbers
            const lines = (codeContent + '▋').split('\n');
            const lineNumberText = lines.map((_, index) => index + 1).join('\n');
            lineNumbers.value = lineNumberText;
            
            // Auto-scroll to bottom during streaming
            codeDisplay.scrollTop = codeDisplay.scrollHeight;
            lineNumbers.scrollTop = lineNumbers.scrollHeight;
        }
    }
    
    hideCode() {
        const editorContainer = document.getElementById('code-editor-container');
        const placeholder = document.querySelector('.code-panel-placeholder');
        const copyBtn = document.getElementById('copy-code-btn');
        const closeBtn = document.getElementById('close-code-btn');
        const codeDisplay = document.getElementById('code-display');
        const lineNumbers = document.getElementById('code-line-numbers');
        
        if (editorContainer && placeholder) {
            placeholder.style.display = 'block';
            editorContainer.style.display = 'none';
            
            this.currentArtifactId = null;
            
            if (codeDisplay) codeDisplay.value = '';
            if (lineNumbers) lineNumbers.value = '';
            
            if (copyBtn) copyBtn.style.display = 'none';
            if (closeBtn) closeBtn.style.display = 'none';
            
            // Reset header title
            const headerTitle = document.querySelector('.code-panel-header h6');
            if (headerTitle) {
                headerTitle.innerHTML = '<i class="bi bi-code-square"></i> Code Viewer';
            }
        }
    }
    
    async copyCode() {
        const codeDisplay = document.getElementById('code-display');
        if (codeDisplay && codeDisplay.value) {
            try {
                // Remove streaming cursor if present
                const codeContent = codeDisplay.value.replace(/▋$/, '');
                await navigator.clipboard.writeText(codeContent);
                
                // Show feedback
                const copyBtn = document.getElementById('copy-code-btn');
                if (copyBtn) {
                    const originalText = copyBtn.innerHTML;
                    copyBtn.innerHTML = '<i class="bi bi-check"></i> Copied!';
                    copyBtn.classList.add('btn-success');
                    copyBtn.classList.remove('btn-outline-secondary');
                    
                    setTimeout(() => {
                        copyBtn.innerHTML = originalText;
                        copyBtn.classList.remove('btn-success');
                        copyBtn.classList.add('btn-outline-secondary');
                    }, 2000);
                }
                
                console.log('📋 Code copied to clipboard');
            } catch (error) {
                console.error('❌ Failed to copy code:', error);
            }
        }
    }
}

// =============================================================================
// ENHANCED MARKDOWN PROCESSING WITH PRISM.JS AND EXPAND/COLLAPSE
// =============================================================================

class CodeMarkdownProcessor {
    constructor() {
        this.expandedBlocks = new Set();
        this.initializePrism();
    }
    
    initializePrism() {
        // Ensure Prism.js is loaded
        if (typeof Prism === 'undefined') {
            console.warn('⚠️ Prism.js not loaded - syntax highlighting disabled');
            return;
        }
        
        // Configure Prism for manual highlighting
        Prism.manual = true;
        console.log('🎨 Prism.js initialized for manual highlighting');
    }
    
    createInlineCodeBlock(codeContent, language = '', lineCount = 0) {
        // Generate unique ID for this code block
        const blockId = `inline-code-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        
        // Normalize language name for Prism.js
        const prismLanguage = this.normalizePrismLanguage(language);
        
        // Determine if block should be collapsible (> 10 lines)
        const isCollapsible = lineCount > 10;
        const previewLines = isCollapsible ? codeContent.split('\n').slice(0, 5).join('\n') + '\n// ... ' + (lineCount - 5) + ' more lines' : codeContent;
        
        return `<div class="enhanced-code-block ${isCollapsible ? 'collapsible' : ''}" data-code-id="${blockId}" data-language="${prismLanguage}" data-full-code="${this.escapeHtml(codeContent)}">
            <div class="code-block-header">
                <div class="code-block-info">
                    <i class="bi bi-file-earmark-code text-primary"></i>
                    <span class="language-badge">${language || 'text'}</span>
                    <span class="line-count">${lineCount} lines</span>
                </div>
                <div class="code-block-actions">
                    ${isCollapsible ? `<button class="btn btn-sm btn-outline-secondary expand-btn" onclick="toggleCodeBlock('${blockId}')">
                        <i class="bi bi-arrows-expand"></i> <span class="expand-text">Expand</span>
                    </button>` : ''}
                    <button class="btn btn-sm btn-outline-primary copy-btn" onclick="copyEnhancedCode('${blockId}')">
                        <i class="bi bi-clipboard"></i> Copy
                    </button>
                </div>
            </div>
            <div class="code-block-content">
                <pre class="code-pre"><code class="language-${prismLanguage} code-content">${this.escapeHtml(isCollapsible ? previewLines : codeContent)}</code></pre>
            </div>
        </div>`;
    }
    
    normalizePrismLanguage(language) {
        if (!language) return 'text';
        
        // Map common language aliases to Prism.js language names
        const languageMap = {
            'js': 'javascript',
            'jsx': 'javascript',
            'ts': 'typescript',
            'tsx': 'typescript',
            'py': 'python',
            'sh': 'bash',
            'shell': 'bash',
            'yml': 'yaml',
            'dockerfile': 'docker',
            'compose.yml': 'yaml',
            'compose.yaml': 'yaml',
            'docker-compose': 'yaml',
            'htm': 'html',
            'xml': 'markup',
            'svg': 'markup',
            'md': 'markdown',
            'rb': 'ruby',
            'cs': 'csharp',
            'cpp': 'cpp',
            'c++': 'cpp',
            'rs': 'rust',
            'go': 'go',
            'php': 'php',
            'sql': 'sql',
            'json': 'json',
            'scss': 'scss',
            'sass': 'sass',
            'less': 'less'
        };
        
        const normalizedLanguage = language.toLowerCase().trim();
        return languageMap[normalizedLanguage] || normalizedLanguage;
    }
    
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    
    applySyntaxHighlighting(container = document) {
        // Apply Prism.js syntax highlighting to code blocks
        if (typeof Prism === 'undefined') {
            console.warn('⚠️ Prism.js not available for syntax highlighting');
            return;
        }
        
        // Find all code elements that haven't been highlighted yet
        const codeElements = container.querySelectorAll('code[class*="language-"]:not(.prism-highlighted)');
        codeElements.forEach(codeEl => {
            try {
                // Mark as highlighted to prevent re-processing
                codeEl.classList.add('prism-highlighted');
                
                // Apply Prism highlighting
                Prism.highlightElement(codeEl);
                
                console.log(`🎨 Applied syntax highlighting to ${codeEl.className}`);
            } catch (error) {
                console.warn('⚠️ Failed to highlight code element:', error);
            }
        });
        
        // Also apply to enhanced code blocks
        const enhancedBlocks = container.querySelectorAll('.enhanced-code-block:not(.prism-processed)');
        enhancedBlocks.forEach(block => {
            const codeEl = block.querySelector('code');
            if (codeEl && !codeEl.classList.contains('prism-highlighted')) {
                try {
                    codeEl.classList.add('prism-highlighted');
                    Prism.highlightElement(codeEl);
                    block.classList.add('prism-processed');
                    console.log(`🎨 Applied syntax highlighting to enhanced code block`);
                } catch (error) {
                    console.warn('⚠️ Failed to highlight enhanced code block:', error);
                }
            }
        });
    }
}

// =============================================================================
// GLOBAL FUNCTIONS FOR CODE BLOCK INTERACTIONS
// =============================================================================

// Enhanced copy function with better feedback
window.copyEnhancedCode = async function(blockId) {
    const codeBlock = document.querySelector(`[data-code-id="${blockId}"]`);
    if (!codeBlock) {
        console.error(`Code block ${blockId} not found`);
        return;
    }
    
    const copyBtn = codeBlock.querySelector('.copy-btn');
    const fullCode = codeBlock.getAttribute('data-full-code');
    
    if (!fullCode || !copyBtn) {
        console.error('Code content or copy button not found');
        return;
    }
    
    try {
        // Decode HTML entities
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = fullCode;
        const decodedCode = tempDiv.textContent || tempDiv.innerText || '';
        
        await navigator.clipboard.writeText(decodedCode);
        
        // Show success feedback with animation
        const originalContent = copyBtn.innerHTML;
        copyBtn.innerHTML = '<i class="bi bi-check-circle-fill text-success"></i> Copied!';
        copyBtn.classList.add('btn-success');
        copyBtn.classList.remove('btn-outline-primary');
        
        // Add success animation
        copyBtn.style.transform = 'scale(1.05)';
        
        setTimeout(() => {
            copyBtn.innerHTML = originalContent;
            copyBtn.classList.remove('btn-success');
            copyBtn.classList.add('btn-outline-primary');
            copyBtn.style.transform = 'scale(1)';
        }, 2000);
        
        console.log('📋 Enhanced code copied to clipboard');
        
        // Show toast notification if available
        if (typeof sharedInterface !== 'undefined') {
            sharedInterface.showSuccess('Code copied to clipboard!');
        }
    } catch (error) {
        console.error('❌ Failed to copy enhanced code:', error);
        
        // Show error feedback
        const originalContent = copyBtn.innerHTML;
        copyBtn.innerHTML = '<i class="bi bi-x-circle-fill text-danger"></i> Failed';
        copyBtn.classList.add('btn-danger');
        copyBtn.classList.remove('btn-outline-primary');
        
        setTimeout(() => {
            copyBtn.innerHTML = originalContent;
            copyBtn.classList.remove('btn-danger');
            copyBtn.classList.add('btn-outline-primary');
        }, 2000);
        
        if (typeof sharedInterface !== 'undefined') {
            sharedInterface.showError('Failed to copy code: ' + error.message);
        }
    }
};

// Toggle expand/collapse for code blocks
window.toggleCodeBlock = function(blockId) {
    const codeBlock = document.querySelector(`[data-code-id="${blockId}"]`);
    if (!codeBlock) {
        console.error(`Code block ${blockId} not found`);
        return;
    }
    
    const expandBtn = codeBlock.querySelector('.expand-btn');
    const codeContent = codeBlock.querySelector('.code-content');
    const fullCode = codeBlock.getAttribute('data-full-code');
    const language = codeBlock.getAttribute('data-language');
    
    if (!expandBtn || !codeContent || !fullCode) {
        console.error('Required elements not found for toggle');
        return;
    }
    
    const isExpanded = codeBlock.classList.contains('expanded');
    
    if (isExpanded) {
        // Collapse
        const lines = fullCode.split('\n');
        const previewLines = lines.slice(0, 5).join('\n') + '\n// ... ' + (lines.length - 5) + ' more lines';
        
        // Decode HTML entities for preview
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = previewLines;
        const decodedPreview = tempDiv.textContent || tempDiv.innerText || '';
        
        codeContent.textContent = decodedPreview;
        codeBlock.classList.remove('expanded');
        
        expandBtn.innerHTML = '<i class="bi bi-arrows-expand"></i> <span class="expand-text">Expand</span>';
        
        console.log(`📁 Collapsed code block ${blockId}`);
    } else {
        // Expand
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = fullCode;
        const decodedCode = tempDiv.textContent || tempDiv.innerText || '';
        
        codeContent.textContent = decodedCode;
        codeBlock.classList.add('expanded');
        
        expandBtn.innerHTML = '<i class="bi bi-arrows-collapse"></i> <span class="expand-text">Collapse</span>';
        
        console.log(`📂 Expanded code block ${blockId}`);
        
        // Smooth scroll to show more content
        codeBlock.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
    
    // Re-apply syntax highlighting after content change
    if (typeof Prism !== 'undefined') {
        try {
            codeContent.classList.remove('prism-highlighted');
            Prism.highlightElement(codeContent);
            console.log(`🎨 Re-applied syntax highlighting after toggle`);
        } catch (error) {
            console.warn('⚠️ Failed to re-highlight after toggle:', error);
        }
    }
};

// Legacy function for backward compatibility
window.copyInlineCode = window.copyEnhancedCode;

// =============================================================================
// GLOBAL EXPORTS
// =============================================================================

if (typeof window !== 'undefined') {
    window.CodePanelManager = CodePanelManager;
    window.CodeMarkdownProcessor = CodeMarkdownProcessor;
    
    console.log('📦 Enhanced code artifact management loaded with Prism.js support');
}

// Auto-apply syntax highlighting when DOM changes
if (typeof MutationObserver !== 'undefined') {
    const codeProcessor = new CodeMarkdownProcessor();
    
    const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
            if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                mutation.addedNodes.forEach((node) => {
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        // Apply syntax highlighting to new code elements
                        codeProcessor.applySyntaxHighlighting(node);
                    }
                });
            }
        });
    });
    
    // Start observing when DOM is ready
    document.addEventListener('DOMContentLoaded', () => {
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
        
        // Initial highlighting pass
        codeProcessor.applySyntaxHighlighting();
        
        console.log('👁️ Code syntax highlighting observer started');
    });
}