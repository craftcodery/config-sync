#!/bin/bash
# NorthBuilt Configuration Sync
# Pulls latest configs from GitHub and deploys to correct locations

set -euo pipefail

# Allow override for testing, default to ~/.craftcodery-config
CONFIG_DIR="${CONFIG_DIR:-$HOME/.craftcodery-config}"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/craftcodery-config-sync.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Check if running interactively (with a TTY) and gum is available
INTERACTIVE=false
if [ -t 1 ] && command -v gum &> /dev/null; then
    INTERACTIVE=true
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

show() {
    if [ "$INTERACTIVE" = true ]; then
        gum style --foreground 42 "✓ $1"
    fi
    log "$1"
}

spin() {
    local title="$1"
    shift
    if [ "$INTERACTIVE" = true ]; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        "$@" 2>/dev/null || true
    fi
}

error() {
    if [ "$INTERACTIVE" = true ]; then
        gum style --foreground 196 "✗ $1"
    fi
    log "ERROR: $1"
}

# Header (only in interactive mode)
if [ "$INTERACTIVE" = true ]; then
    gum style \
        --border rounded \
        --border-foreground 39 \
        --padding "0 2" \
        --margin "1 0" \
        "Syncing NorthBuilt Configuration..."
fi

log "Starting config sync..."

# Pull latest from GitHub (only if in git repo)
if [ -d "$CONFIG_DIR/.git" ]; then
    cd "$CONFIG_DIR"
    if spin "Pulling latest configuration..." git pull --ff-only; then
        show "Git pull successful"
    else
        error "Git pull failed (may be offline or no changes)"
    fi
else
    log "Not in git repository, skipping git pull"
fi

# Determine helper script install location
# Try /usr/local/bin first (if we have sudo), fall back to ~/.local/bin
HELPER_PATH=""
if sudo -n true 2>/dev/null; then
    HELPER_PATH="/usr/local/bin/aws-vault-1password"
else
    HELPER_PATH="$HOME/.local/bin/aws-vault-1password"
fi

# Deploy helper scripts first (need path for config substitution)
HELPER_SCRIPT="$CONFIG_DIR/bin/aws-vault-1password"
if [ -f "$HELPER_SCRIPT" ]; then
    if [ "$HELPER_PATH" = "/usr/local/bin/aws-vault-1password" ]; then
        sudo mkdir -p /usr/local/bin 2>/dev/null || true
        sudo cp "$HELPER_SCRIPT" /usr/local/bin/ 2>/dev/null
        sudo chmod +x /usr/local/bin/aws-vault-1password 2>/dev/null
        show "Deployed /usr/local/bin/aws-vault-1password"
    else
        mkdir -p "$HOME/.local/bin"
        cp "$HELPER_SCRIPT" "$HOME/.local/bin/"
        chmod +x "$HOME/.local/bin/aws-vault-1password"
        show "Deployed $HOME/.local/bin/aws-vault-1password"

        # Ensure ~/.local/bin is in PATH
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            SHELL_PROFILE=""
            if [[ -f "$HOME/.zshrc" ]]; then
                SHELL_PROFILE="$HOME/.zshrc"
            elif [[ -f "$HOME/.bashrc" ]]; then
                SHELL_PROFILE="$HOME/.bashrc"
            fi
            if [[ -n "$SHELL_PROFILE" ]] && ! grep -q '.local/bin' "$SHELL_PROFILE" 2>/dev/null; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_PROFILE"
                log "Added ~/.local/bin to PATH in $SHELL_PROFILE"
            fi
        fi
    fi
else
    error "Helper script not found: $HELPER_SCRIPT"
fi

# Deploy AWS config with path substitution
mkdir -p "$HOME/.aws"
if [ -f "$CONFIG_DIR/aws/config" ]; then
    # Replace __HELPER_PATH__ placeholder with actual path
    sed "s|__HELPER_PATH__|$HELPER_PATH|g" "$CONFIG_DIR/aws/config" > "$HOME/.aws/config"
    chmod 600 "$HOME/.aws/config"
    show "Deployed ~/.aws/config"
else
    error "AWS config not found: $CONFIG_DIR/aws/config"
fi

# Check if OP_ACCOUNT is set, remind user if not
if [ -z "${OP_ACCOUNT:-}" ]; then
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        gum style \
            --foreground 214 \
            "Note: OP_ACCOUNT is not set. For 1Password integration, add to ~/.zshrc:" \
            "  export OP_ACCOUNT=\"craftcodery.1password.com\""
    fi
    log "OP_ACCOUNT not set"
fi

log "Config sync complete"

# Summary (only in interactive mode)
if [ "$INTERACTIVE" = true ]; then
    echo ""
    gum style \
        --foreground 42 \
        --bold \
        "✓ Sync complete!"
fi
