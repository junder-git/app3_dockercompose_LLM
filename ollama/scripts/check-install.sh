#!/bin/bash
# scripts/check-install.sh - Optimized binary-only installation with caching

set -euo pipefail

log() { echo "$(date '+%H:%M:%S') $1"; }
error() { echo "❌ $1" >&2; exit 1; }

# Validate environment
[[ -z "${OLLAMA_VERSION:-}" ]] && error "OLLAMA_VERSION not set"

CACHE_DIR="/ollama-cache"
VERSION_FILE="$CACHE_DIR/version"
BINARY_PATH="/usr/local/bin/ollama"

log "🔍 Checking Ollama installation..."

# Function to download Ollama binary directly
download_ollama() {
    local version="$1"
    local temp_dir=$(mktemp -d)
    
    # Add 'v' prefix if not present
    if [[ "${version#v}" == "${version}" ]]; then
        version_tag="v${version}"
    else
        version_tag="${version}"
    fi
    
    log "📥 Downloading Ollama ${version_tag}..."
    
    local download_url="https://github.com/ollama/ollama/releases/download/${version_tag}/ollama-linux-amd64.tgz"
    
    if curl -fsSL "$download_url" | tar -xzf - -C "$temp_dir"; then
        # Move binary to final location
        if [[ -f "$temp_dir/bin/ollama" ]]; then
            cp "$temp_dir/bin/ollama" "$BINARY_PATH"
        elif [[ -f "$temp_dir/ollama" ]]; then
            cp "$temp_dir/ollama" "$BINARY_PATH"
        else
            error "Downloaded archive doesn't contain expected binary"
        fi
        
        chmod +x "$BINARY_PATH"
        rm -rf "$temp_dir"
        
        log "✅ Download completed"
        return 0
    else
        rm -rf "$temp_dir"
        error "Failed to download Ollama ${version_tag}"
    fi
}

# Check if we have a cached version
if [[ -f "$VERSION_FILE" && -f "$CACHE_DIR/ollama" ]]; then
    cached_version=$(cat "$VERSION_FILE")
    log "📦 Found cached Ollama version: $cached_version"
    
    if [[ "$cached_version" == "$OLLAMA_VERSION" ]]; then
        log "✅ Cached version matches required version ($OLLAMA_VERSION)"
        
        # Copy from cache to system location
        if [[ ! -f "$BINARY_PATH" ]] || ! timeout 5 ollama --version >/dev/null 2>&1; then
            log "📋 Copying Ollama from cache..."
            cp "$CACHE_DIR/ollama" "$BINARY_PATH"
            chmod +x "$BINARY_PATH"
            log "✅ Ollama binary restored from cache"
        else
            log "✅ Ollama binary already ready"
        fi
        
        # Verify it works
        if timeout 10 ollama --version >/dev/null 2>&1; then
            log "✅ Ollama is ready (cached)"
            exec /scripts/init-ollama.sh
        else
            log "⚠️  Cached binary broken, reinstalling..."
            rm -f "$VERSION_FILE" "$CACHE_DIR/ollama"
        fi
    else
        log "🔄 Version mismatch: cached=$cached_version, required=$OLLAMA_VERSION"
        rm -f "$VERSION_FILE" "$CACHE_DIR/ollama"
    fi
fi

# Install if not cached or version mismatch
if [[ ! -f "$VERSION_FILE" || ! -f "$CACHE_DIR/ollama" ]]; then
    log "📥 Installing Ollama version $OLLAMA_VERSION..."
    
    if download_ollama "$OLLAMA_VERSION"; then
        log "✅ Installation completed"
        
        # Cache the binary and version
        if [[ -f "$BINARY_PATH" ]]; then
            log "💾 Caching Ollama binary..."
            cp "$BINARY_PATH" "$CACHE_DIR/ollama"
            echo "$OLLAMA_VERSION" > "$VERSION_FILE"
            log "✅ Binary cached for future use"
        fi
    else
        error "Installation failed"
    fi
fi

# Final verification
if timeout 10 ollama --version >/dev/null 2>&1; then
    version_output=$(ollama --version 2>/dev/null || echo "unknown")
    log "🎯 Ollama ready! Version: $version_output"
else
    error "Ollama installation verification failed"
fi

# Start the main service
exec /scripts/init-ollama.sh