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
    constructor(artifactManager) {
        this.artifactManager = artifactManager;
    }
    
    processMarkdownWithArtifacts(content) {
        if (!window.marked || !content) return content;
        
        try {
            // Process markdown but intercept code blocks
            let processed = content;
            
            // Pattern to match code blocks: ```language\ncode\n```
            const codeBlockPattern = /```(\w+)?\n([\s\S]*?)```/g;
            let match;
            let offset = 0;
            
            // Reset regex index to avoid issues with global regex
            codeBlockPattern.lastIndex = 0;
            
            while ((match = codeBlockPattern.exec(content)) !== null) {
                const fullMatch = match[0];
                const language = match[1] || '';
                const codeContent = match[2];
                const lineCount = codeContent.split('\n').length;
                console.log(`🔍 Processing code block: ${lineCount} lines, language: ${language || 'none'}`);
                // Small code block - create custom inline display with copy button
                const inlineCodeBlock = this.createInlineCodeBlock(codeContent, language, lineCount);
                const startIndex = match.index + offset;
                const endIndex = startIndex + fullMatch.length;
                
                processed = processed.substring(0, startIndex) + 
                            inlineCodeBlock + 
                            processed.substring(endIndex);
                
                offset += inlineCodeBlock.length - fullMatch.length;
                console.log(`📄 Created inline code block (${lineCount} lines)`);
            }
            
            return marked.parse(processed);
        } catch (error) {
            console.warn('⚠️ Markdown processing error:', error);
            return content;
        }
    }
    
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
    
    createCodeButtonPlaceholder(artifactId, language = '', isStreaming = false) {
        const artifact = this.artifactManager.getArtifact(artifactId);
        const displayName = language ? `${language} code` : 'Code';
        const lines = artifact ? artifact.content.split('\n').length : 0;
        const streamingIndicator = isStreaming ? ' (streaming...)' : '';
        
        return `<div class="code-artifact-button" data-artifact-id="${artifactId}" data-language="${language}">
            <div class="code-artifact-info">
                <i class="bi bi-file-earmark-code"></i>
                <span class="code-artifact-name">${artifactId}${streamingIndicator}</span>
                <span class="code-artifact-meta">${displayName} • ${lines} lines</span>
            </div>
            <div class="code-artifact-action">
                <i class="bi bi-eye"></i> View
            </div>
        </div>`;
    }
    
    setupCodeArtifactHandlers(messageDiv) {
        const artifactButtons = messageDiv.querySelectorAll('.code-artifact-button');
        artifactButtons.forEach(button => {
            const artifactId = button.dataset.artifactId;
            const language = button.dataset.language;
            
            // Remove any existing listeners to prevent duplicates
            button.replaceWith(button.cloneNode(true));
            const newButton = messageDiv.querySelector(`[data-artifact-id="${artifactId}"]`);
            
            if (newButton) {
                newButton.addEventListener('click', () => {
                    console.log(`🖱️ Code artifact button clicked: ${artifactId}`);
                    this.artifactManager.displayArtifact(artifactId);
                });
            }
        });
        
        // Apply syntax highlighting to any new inline code blocks
        this.applySyntaxHighlighting(messageDiv);
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
    
    updateStreamingMessageWithArtifacts(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Check if we're inside a code block that's being streamed
            const openCodeBlock = content.lastIndexOf('```');
            const closeCodeBlock = content.indexOf('```', openCodeBlock + 3);
            
            // We're streaming inside a code block if there's an unmatched opening ```
            if (openCodeBlock !== -1 && closeCodeBlock === -1) {
                const beforeCode = content.substring(0, openCodeBlock);
                const afterTripleBacktick = content.substring(openCodeBlock + 3);
                const newlineIndex = afterTripleBacktick.indexOf('\n');
                
                if (newlineIndex !== -1) {
                    const language = afterTripleBacktick.substring(0, newlineIndex).trim();
                    const codeContent = afterTripleBacktick.substring(newlineIndex + 1);
                    
                    // Only create/update pending block once per code block
                    if (!this.artifactManager.pendingCodeBlock || 
                        this.artifactManager.pendingCodeBlock.language !== language) {
                        this.artifactManager.createPendingCodeBlock(language);
                        // Immediately show pending content in code panel
                        this.artifactManager.displayArtifact('pending');
                        console.log(`📋 Started streaming to pending code block (${language})`);
                    }
                    
                    // Update pending content and code panel
                    this.artifactManager.updatePendingCodeBlock(codeContent);
                    
                    // Check line count for artifact creation threshold
                    const lineCount = codeContent.split('\n').length;
                    
                    // Process the content before the code block + show placeholder based on size
                    const processedBeforeCode = this.processMarkdownWithArtifacts(beforeCode);
                    let streamingPlaceholder;
                    // Small code block - show inline with streaming indicator and syntax highlighting
                    const prismLanguage = this.normalizePrismLanguage(language);
                    streamingPlaceholder = `<div class="code-streaming-inline">
                        <div class="inline-code-header">
                            <span class="inline-code-info">
                                <i class="bi bi-file-earmark-code"></i>
                                ${language || 'Code'} • ${lineCount} lines • Streaming...
                            </span>
                            <span class="streaming-indicator-text">
                                <i class="bi bi-arrow-right"></i> Also in code panel
                            </span>
                        </div>
                        <div class="inline-code-content">
                            <pre><code class="language-${prismLanguage} prism-highlighted">${this.escapeHtml(codeContent)}</code></pre>
                        </div>
                    </div>`;                    
                    streamingEl.innerHTML = processedBeforeCode + streamingPlaceholder + '<span class="cursor blink">▋</span>';
                } else {
                    // Still determining language, just show regular markdown
                    const processedContent = this.processMarkdownWithArtifacts(content);
                    streamingEl.innerHTML = processedContent + '<span class="cursor blink">▋</span>';
                }
            } else {
                // Regular markdown content (no active code block)
                const processedContent = this.processMarkdownWithArtifacts(content);
                streamingEl.innerHTML = processedContent + '<span class="cursor blink">▋</span>';
            }
            
            // Setup handlers for any new artifact buttons
            this.setupCodeArtifactHandlers(messageDiv);
            
            // Smart scroll if available
            if (window.sharedChatInstance && window.sharedChatInstance.smartScroll) {
                window.sharedChatInstance.smartScroll();
            }
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
    window.CodeArtifactManager = CodeArtifactManager;
    window.CodePanelManager = CodePanelManager;
    window.CodeMarkdownProcessor = CodeMarkdownProcessor;
    
    console.log('📦 Code artifact management loaded and available globally');
}