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
        if (!this.artifacts.has(artifactId)) {
            console.warn(`⚠️ Cannot display artifact ${artifactId} - not found`);
            return;
        }
        
        const artifact = this.artifacts.get(artifactId);
        this.activeArtifact = artifactId;
        
        // Use the existing code panel to display
        if (window.sharedChatInstance && window.sharedChatInstance.codePanel) {
            window.sharedChatInstance.codePanel.showCode(
                artifact.content, 
                artifact.language, 
                artifact.filename || artifactId,
                artifactId
            );
        }
        
        console.log(`👁️ Displaying artifact: ${artifactId}`);
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
        return this.streamingArtifact !== null;
    }
    
    getCurrentStreamingArtifact() {
        return this.streamingArtifact;
    }
    
    clearAllArtifacts() {
        this.artifacts.clear();
        this.counter = 0;
        this.activeArtifact = null;
        this.streamingArtifact = null;
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
        const codeDisplay = document.getElementById('code-display');
        const lineNumbers = document.getElementById('code-line-numbers');
        const editorContainer = document.getElementById('code-editor-container');
        const placeholder = document.querySelector('.code-panel-placeholder');
        const copyBtn = document.getElementById('copy-code-btn');
        const closeBtn = document.getElementById('close-code-btn');
        
        if (codeDisplay && placeholder && lineNumbers && editorContainer) {
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
            
            console.log('📋 Code displayed in panel with line numbers:', codeContent.substring(0, 50) + '...');
        }
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
            
            while ((match = codeBlockPattern.exec(content)) !== null) {
                const fullMatch = match[0];
                const language = match[1] || '';
                const codeContent = match[2];
                
                // Create or update artifact
                let artifactId;
                if (this.artifactManager.isStreaming()) {
                    // Update existing streaming artifact
                    artifactId = this.artifactManager.getCurrentStreamingArtifact();
                    this.artifactManager.updateArtifact(artifactId, codeContent, false);
                } else {
                    // Create new artifact
                    artifactId = this.artifactManager.createArtifact(language);
                    this.artifactManager.updateArtifact(artifactId, codeContent, true);
                }
                
                // Replace code block with button placeholder
                const buttonPlaceholder = this.createCodeButtonPlaceholder(artifactId, language);
                const startIndex = match.index + offset;
                const endIndex = startIndex + fullMatch.length;
                
                processed = processed.substring(0, startIndex) + 
                           buttonPlaceholder + 
                           processed.substring(endIndex);
                
                offset += buttonPlaceholder.length - fullMatch.length;
            }
            
            return marked.parse(processed);
        } catch (error) {
            console.warn('⚠️ Markdown processing error:', error);
            return content;
        }
    }
    
    createCodeButtonPlaceholder(artifactId, language = '') {
        const artifact = this.artifactManager.getArtifact(artifactId);
        const displayName = language ? `${language} code` : 'Code';
        const lines = artifact ? artifact.content.split('\n').length : 0;
        
        return `<div class="code-artifact-button" data-artifact-id="${artifactId}" data-language="${language}">
            <div class="code-artifact-info">
                <i class="bi bi-file-earmark-code"></i>
                <span class="code-artifact-name">${artifactId}</span>
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
            
            button.addEventListener('click', () => {
                this.artifactManager.displayArtifact(artifactId);
                console.log(`📁 Code artifact ${artifactId} clicked, displaying in panel`);
            });
        });
    }
    
    updateStreamingMessageWithArtifacts(messageDiv, content) {
        const streamingEl = messageDiv.querySelector('.streaming-content');
        if (streamingEl) {
            // Check if we're inside a code block
            const codeBlockMatch = content.match(/```(\w+)?\n([\s\S]*)$/);
            
            if (codeBlockMatch) {
                // We're streaming inside a code block
                const language = codeBlockMatch[1] || '';
                const codeContent = codeBlockMatch[2];
                
                // Ensure we have a streaming artifact
                if (!this.artifactManager.isStreaming()) {
                    const artifactId = this.artifactManager.createArtifact(language);
                    this.artifactManager.setStreamingArtifact(artifactId);
                }
                
                // Update the streaming artifact
                const streamingArtifactId = this.artifactManager.getCurrentStreamingArtifact();
                this.artifactManager.updateArtifact(streamingArtifactId, codeContent, false);
                
                // Update code panel if it's active
                if (window.sharedChatInstance && window.sharedChatInstance.codePanel && 
                    window.sharedChatInstance.codePanel.currentArtifactId === streamingArtifactId) {
                    window.sharedChatInstance.codePanel.updateStreamingCode(codeContent);
                }
                
                // Process the content up to the code block start
                const preCodeContent = content.substring(0, content.lastIndexOf('```'));
                const processedContent = this.processMarkdownWithArtifacts(preCodeContent);
                streamingEl.innerHTML = processedContent + '<span class="cursor blink">▋</span>';
            } else {
                // Regular markdown content
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