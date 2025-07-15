#!/bin/bash
# scripts/check-install.sh - Smart installation with volume caching

set -euo pipefail

log() { echo "$(date '+%H:%M:%S') $1"; }
error() { echo "❌ $1" >&2; exit 1; }

# Validate environment
[[ -z "${OLLAMA_VERSION:-}" ]] && error "OLLAMA_VERSION not set"

CACHE_DIR="/ollama-cache"
VERSION_FILE="$CACHE_DIR/version"
BINARY_PATH="/usr/local/bin/ollama"

log "🔍 Checking Ollama installation..."

# Check if we have a cached version
if [[ -f "$VERSION_FILE" && -f "$CACHE_DIR/ollama" ]]; then
    cached_version=$(cat "$VERSION_FILE")
    log "📦 Found cached Ollama version: $cached_version"
    
    if [[ "$cached_version" == "$OLLAMA_VERSION" ]]; then
        log "✅ Cached version matches required version ($OLLAMA_VERSION)"
        
        # Copy from cache to system location
        if [[ ! -f "$BINARY_PATH" ]]; then
            log "📋 Copying Ollama from cache to system location..."
            cp "$CACHE_DIR/ollama" "$BINARY_PATH"
            chmod +x "$BINARY_PATH"
            log "✅ Ollama binary restored from cache"
        else
            log "✅ Ollama binary already in place"
        fi
        
        # Verify it works
        if ollama --version >/dev/null 2>&1; then
            log "✅ Ollama is ready (cached)"
        else
            log "⚠️  Cached binary seems broken, will reinstall"
            rm -f "$VERSION_FILE" "$CACHE_DIR/ollama"
        fi
    else
        log "🔄 Version mismatch: cached=$cached_version, required=$OLLAMA_VERSION"
        log "🗑️  Clearing cache..."
        rm -f "$VERSION_FILE" "$CACHE_DIR/ollama"
    fi
fi

# Install if not cached or version mismatch
if [[ ! -f "$VERSION_FILE" || ! -f "$CACHE_DIR/ollama" ]]; then
    log "📥 Installing Ollama version $OLLAMA_VERSION..."
    
    # Run the install script
    export OLLAMA_VERSION="$OLLAMA_VERSION"
    if /scripts/install-ollama.sh; then
        log "✅ Installation completed"
        
        # Cache the binary and version
        if [[ -f "$BINARY_PATH" ]]; then
            log "💾 Caching Ollama binary..."
            cp "$BINARY_PATH" "$CACHE_DIR/ollama"
            echo "$OLLAMA_VERSION" > "$VERSION_FILE"
            log "✅ Binary cached for future use"
        else
            log "⚠️  Binary not found at expected location"
        fi
    else
        error "Installation failed"
    fi
fi

# Final verification
if ! ollama --version >/dev/null 2>&1; then
    error "Ollama installation verification failed"
fi

log "🎯 Ollama $OLLAMA_VERSION ready!"

# Start the main initialization script
exec /scripts/init-ollama.sh