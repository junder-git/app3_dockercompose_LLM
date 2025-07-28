// =============================================================================
// nginx/static/js/is_shared_code.js - CODE ARTIFACT MANAGEMENT SYSTEM
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
// MARKDOWN PROCESSING WITH CODE ARTIFACT HANDLING
// =============================================================================

class CodeMarkdownProcessor {   
    createInlineCodeBlock(codeContent, language = '', lineCount = 0) {
        // Generate unique ID for this code block
        const blockId = `inline-code-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        
        // Normalize language name for Prism.js
        const prismLanguage = this.normalizePrismLanguage(language);
        
        return `<div class="inline-code-block" data-code-id="${blockId}">
            <div class="inline-code-header">
                <span class="inline-code-info">
                    <i class="bi bi-file-earmark-code"></i>
                    ${language ? `${language} • ` : ''}${lineCount} lines
                </span>
                <button class="inline-code-copy-btn" onclick="copyInlineCode('${blockId}')">
                    <i class="bi bi-clipboard"></i> Copy
                </button>
            </div>
            <div class="inline-code-content">
                <pre><code class="language-${prismLanguage}">${this.escapeHtml(codeContent)}</code></pre>
            </div>
        </div>`;
    }
    
    normalizePrismLanguage(language) {
        if (!language) return 'none';
        
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
        if (window.Prism) {
            // Find all code elements that haven't been highlighted yet
            const codeElements = container.querySelectorAll('code[class*="language-"]:not(.prism-highlighted)');
            codeElements.forEach(codeEl => {
                // Mark as highlighted to prevent re-processing
                codeEl.classList.add('prism-highlighted');
                
                // Apply Prism highlighting
                window.Prism.highlightElement(codeEl);
                
                console.log(`🎨 Applied syntax highlighting to ${codeEl.className}`);
            });
        } else {
            console.warn('⚠️ Prism.js not available for syntax highlighting');
        }
    }
}

// =============================================================================
// GLOBAL EXPORTS AND COPY FUNCTION
// =============================================================================

// Global function for copying inline code
window.copyInlineCode = async function(blockId) {
    const codeBlock = document.querySelector(`[data-code-id="${blockId}"]`);
    if (!codeBlock) {
        console.error(`Code block ${blockId} not found`);
        return;
    }
    
    const codeContent = codeBlock.querySelector('code');
    const copyBtn = codeBlock.querySelector('.inline-code-copy-btn');
    
    if (!codeContent || !copyBtn) {
        console.error('Code content or copy button not found');
        return;
    }
    
    try {
        await navigator.clipboard.writeText(codeContent.textContent);
        
        // Show success feedback
        const originalContent = copyBtn.innerHTML;
        copyBtn.innerHTML = '<i class="bi bi-check"></i> Copied!';
        copyBtn.classList.add('copied');
        
        setTimeout(() => {
            copyBtn.innerHTML = originalContent;
            copyBtn.classList.remove('copied');
        }, 2000);
        
        console.log('📋 Inline code copied to clipboard');
    } catch (error) {
        console.error('❌ Failed to copy inline code:', error);
        
        // Show error feedback
        const originalContent = copyBtn.innerHTML;
        copyBtn.innerHTML = '<i class="bi bi-x"></i> Failed';
        copyBtn.style.background = 'var(--danger-color)';
        
        setTimeout(() => {
            copyBtn.innerHTML = originalContent;
            copyBtn.style.background = '';
        }, 2000);
    }
};

if (typeof window !== 'undefined') {
    window.CodePanelManager = CodePanelManager;
    window.CodeMarkdownProcessor = CodeMarkdownProcessor;
    
    console.log('📦 Code artifact management loaded and available globally');
}