// =============================================================================
// nginx/static/js/is_shared_code.js - CODE ARTIFACT MANAGEMENT SYSTEM
// =============================================================================

// =============================================================================
// CODE ARTIFACT MANAGEMENT SYSTEM
// =============================================================================

class CodeArtifactManager {
    constructor() {
        this.artifacts = new Map(); // Store code artifacts: code_1, code_2, etc.
        this.counter = 0;
        this.activeArtifact = null;
        this.streamingArtifact = null;
        this.pendingCodeBlock = null; // For temporary storage during streaming
    }
    
    createArtifact(language = '', filename = '') {
        this.counter++;
        const artifactId = `code_${this.counter}`;
        
        const artifact = {
            id: artifactId,
            content: '',
            language: language,
            filename: filename,
            isStreaming: false,
            version: 1
        };
        
        this.artifacts.set(artifactId, artifact);
        console.log(`📦 Created code artifact: ${artifactId}`);
        return artifactId;
    }
    
    createPendingCodeBlock(language = '') {
        // Create a temporary holding area for streaming content
        this.pendingCodeBlock = {
            content: '',
            language: language,
            isActive: true
        };
        console.log(`📋 Created pending code block for language: ${language}`);
        return this.pendingCodeBlock;
    }
    
    updatePendingCodeBlock(content) {
        if (this.pendingCodeBlock && this.pendingCodeBlock.isActive) {
            this.pendingCodeBlock.content = content;
            
            // Update code panel if it's showing pending content
            if (window.sharedChatInstance && window.sharedChatInstance.codePanel && 
                window.sharedChatInstance.codePanel.currentArtifactId === 'pending') {
                window.sharedChatInstance.codePanel.updateStreamingCode(content);
            }
            
            return true;
        }
        return false;
    }
    
    finalizePendingCodeBlock() {
        if (this.pendingCodeBlock && this.pendingCodeBlock.isActive) {
            // Create actual artifact from pending content
            const artifactId = this.createArtifact(this.pendingCodeBlock.language);
            this.updateArtifact(artifactId, this.pendingCodeBlock.content, true);
            
            // Clear pending block
            const finalContent = this.pendingCodeBlock.content;
            this.pendingCodeBlock = null;
            
            console.log(`✅ Finalized pending code block as ${artifactId}`);
            return { artifactId, content: finalContent };
        }
        return null;
    }
    
    updateArtifact(artifactId, content, isComplete = false) {
        if (!this.artifacts.has(artifactId)) {
            console.warn(`⚠️ Artifact ${artifactId} not found`);
            return;
        }
        
        const artifact = this.artifacts.get(artifactId);
        artifact.content = content;
        artifact.isStreaming = !isComplete;
        
        // If this is the active artifact in the code panel, update the display
        if (this.activeArtifact === artifactId) {
            this.displayArtifact(artifactId);
        }
        
        console.log(`📝 Updated artifact ${artifactId} (${content.length} chars)`);
    }
    
    displayArtifact(artifactId) {
        if (artifactId === 'pending' && this.pendingCodeBlock) {
            // Show pending content
            this.activeArtifact = 'pending';
            if (window.sharedChatInstance && window.sharedChatInstance.codePanel) {
                window.sharedChatInstance.codePanel.showCode(
                    this.pendingCodeBlock.content, 
                    this.pendingCodeBlock.language, 
                    'pending',
                    'pending'
                );
                console.log(`👁️ Displaying pending code block with ${this.pendingCodeBlock.content.length} chars`);
            }
            return;
        }
        
        if (!this.artifacts.has(artifactId)) {
            console.warn(`⚠️ Cannot display artifact ${artifactId} - not found`);
            return;
        }
        
        const artifact = this.artifacts.get(artifactId);
        this.activeArtifact = artifactId;
        
        // Use the code panel manager directly
        if (window.sharedChatInstance && window.sharedChatInstance.codePanel) {
            window.sharedChatInstance.codePanel.showCode(
                artifact.content, 
                artifact.language, 
                artifact.filename || artifactId,
                artifactId
            );
            console.log(`👁️ Displaying artifact: ${artifactId} with ${artifact.content.length} chars`);
        } else {
            console.error('❌ Code panel manager not available');
        }
    }
    
    getArtifact(artifactId) {
        return this.artifacts.get(artifactId);
    }
    
    getAllArtifacts() {
        return Array.from(this.artifacts.values());
    }
    
    setStreamingArtifact(artifactId) {
        this.streamingArtifact = artifactId;
        if (this.artifacts.has(artifactId)) {
            this.artifacts.get(artifactId).isStreaming = true;
        }
    }
    
    finishStreaming(artifactId) {
        this.streamingArtifact = null;
        if (this.artifacts.has(artifactId)) {
            this.artifacts.get(artifactId).isStreaming = false;
        }
    }
    
    isStreaming() {
        return this.streamingArtifact !== null || (this.pendingCodeBlock && this.pendingCodeBlock.isActive);
    }
    
    getCurrentStreamingArtifact() {
        return this.streamingArtifact;
    }
    
    clearAllArtifacts() {
        this.artifacts.clear();
        this.counter = 0;
        this.activeArtifact = null;
        this.streamingArtifact = null;
        this.pendingCodeBlock = null;
        console.log('🗑️ All code artifacts cleared');
    }
}

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
            artifactId
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
        
        if (!codeContent) {
            console.warn('⚠️ No code content provided');
            return;
        }
        
        placeholder.style.display = 'none';
        editorContainer.style.display = 'flex';
        
        this.currentArtifactId = artifactId;
        
        // Set code content
        codeDisplay.value = codeContent;
        
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
                
                // Only create artifacts for code blocks with 16+ lines
                if (lineCount >= 16) {
                    // Check if this is the finalization of a pending code block
                    let artifactId;
                    if (this.artifactManager.pendingCodeBlock && 
                        this.artifactManager.pendingCodeBlock.language === language &&
                        this.artifactManager.pendingCodeBlock.content.trim() === codeContent.trim()) {
                        
                        // Finalize the pending block
                        const result = this.artifactManager.finalizePendingCodeBlock();
                        if (result) {
                            artifactId = result.artifactId;
                            console.log(`✅ Finalized pending code block as ${artifactId} (${lineCount} lines)`);
                        }
                    } else {
                        // Create new artifact for large complete code blocks
                        artifactId = this.artifactManager.createArtifact(language);
                        this.artifactManager.updateArtifact(artifactId, codeContent, true);
                        console.log(`📦 Created artifact ${artifactId} for large code block (${lineCount} lines)`);
                    }
                    
                    // Replace code block with button placeholder
                    const buttonPlaceholder = this.createCodeButtonPlaceholder(artifactId, language);
                    const startIndex = match.index + offset;
                    const endIndex = startIndex + fullMatch.length;
                    
                    processed = processed.substring(0, startIndex) + 
                               buttonPlaceholder + 
                               processed.substring(endIndex);
                    
                    offset += buttonPlaceholder.length - fullMatch.length;
                } else {
                    // Small code block - leave as regular markdown
                    console.log(`📄 Keeping small code block inline (${lineCount} lines)`);
                    // No replacement needed - let markdown handle it normally
                }
            }
            
            return marked.parse(processed);
        } catch (error) {
            console.warn('⚠️ Markdown processing error:', error);
            return content;
        }
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
                    
                    if (lineCount < 16) {
                        // Small code block - show inline with streaming indicator
                        streamingPlaceholder = `<div class="code-streaming-inline">
                            <div class="code-inline-content">
                                <pre class="streaming-code"><code>${codeContent}</code></pre>
                            </div>
                            <div class="streaming-indicator">
                                <i class="bi bi-arrow-right"></i> Streaming to code panel
                            </div>
                        </div>`;
                    } else {
                        // Large code block - show artifact placeholder
                        streamingPlaceholder = `<div class="code-streaming-placeholder">
                            <div class="code-artifact-info">
                                <i class="bi bi-file-earmark-code"></i>
                                <span class="code-artifact-name">Streaming code...</span>
                                <span class="code-artifact-meta">${language || 'Code'} • ${lineCount} lines • View in panel →</span>
                            </div>
                        </div>`;
                    }
                    
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
// GLOBAL EXPORTS
// =============================================================================

if (typeof window !== 'undefined') {
    window.CodeArtifactManager = CodeArtifactManager;
    window.CodePanelManager = CodePanelManager;
    window.CodeMarkdownProcessor = CodeMarkdownProcessor;
    
    console.log('📦 Code artifact management loaded and available globally');
}