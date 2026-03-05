#!/bin/bash
# NorthBuilt Configuration Sync
# Downloads latest configs from setup.northbuilt.com and deploys them
#
# Usage:
#   sync.sh              # Interactive mode
#   sync.sh --launchd    # Background mode (for launchd service)
#   sync.sh --verbose    # Verbose output
#
# This script is downloaded and run by the setup process.
# It fetches configs from GitHub Pages (no git required).

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

BASE_URL="https://setup.northbuilt.com"
CONFIG_DIR="$HOME/.northbuilt"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/northbuilt-sync.log"
MAX_LOG_SIZE=1048576  # 1MB

export OP_ACCOUNT="${OP_ACCOUNT:-craftcodery.1password.com}"

# =============================================================================
# Parse Arguments
# =============================================================================

LAUNCHD_MODE=false
VERBOSE=false

for arg in "$@"; do
    case $arg in
        --launchd) LAUNCHD_MODE=true; VERBOSE=true ;;
        --verbose|-v) VERBOSE=true ;;
    esac
done

# =============================================================================
# Logging
# =============================================================================

mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"

# Rotate log if too large
if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "$LOG_FILE.old"
fi

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ]; then
        echo "[$timestamp] [$level] $message"
    fi
}

log_info() { log "INFO" "$1"; }
log_debug() { log "DEBUG" "$1"; }
log_error() { log "ERROR" "$1"; }

# =============================================================================
# UI (only in interactive mode)
# =============================================================================

INTERACTIVE=false
if [ -t 1 ] && [ "$LAUNCHD_MODE" = false ] && command -v gum &> /dev/null; then
    INTERACTIVE=true
fi

show() {
    log_info "$1"
    if [ "$INTERACTIVE" = true ]; then
        gum style --foreground 42 "✓ $1"
    fi
}

show_error() {
    log_error "$1"
    if [ "$INTERACTIVE" = true ]; then
        gum style --foreground 196 "✗ $1"
    fi
}

# =============================================================================
# Main Sync Logic
# =============================================================================

log_info "=========================================="
log_info "Starting config sync"
log_info "BASE_URL: $BASE_URL"
log_info "CONFIG_DIR: $CONFIG_DIR"
log_info "=========================================="

if [ "$INTERACTIVE" = true ]; then
    gum style \
        --border rounded \
        --border-foreground 39 \
        --padding "0 2" \
        --margin "1 0" \
        "Syncing NorthBuilt Configuration..."
fi

# -----------------------------------------------------------------------------
# Step 1: Download helper script
# -----------------------------------------------------------------------------

log_info "Downloading helper script..."
HELPER_PATH="$CONFIG_DIR/aws-vault-1password"

if curl -fsSL "$BASE_URL/aws-vault-1password" -o "$HELPER_PATH.tmp" 2>/dev/null; then
    mv "$HELPER_PATH.tmp" "$HELPER_PATH"
    chmod +x "$HELPER_PATH"
    show "Downloaded aws-vault-1password"
else
    show_error "Failed to download aws-vault-1password"
fi

# Ensure config dir is in PATH
if [[ ":$PATH:" != *":$CONFIG_DIR:"* ]]; then
    SHELL_PROFILE=""
    if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        SHELL_PROFILE="$HOME/.bashrc"
    fi
    if [[ -n "$SHELL_PROFILE" ]] && ! grep -q ".northbuilt" "$SHELL_PROFILE" 2>/dev/null; then
        echo '' >> "$SHELL_PROFILE"
        echo '# NorthBuilt tools' >> "$SHELL_PROFILE"
        echo 'export PATH="$HOME/.northbuilt:$PATH"' >> "$SHELL_PROFILE"
        log_info "Added ~/.northbuilt to PATH in $SHELL_PROFILE"
    fi
fi

# -----------------------------------------------------------------------------
# Step 2: Download AWS config template
# -----------------------------------------------------------------------------

log_info "Downloading AWS config..."
mkdir -p "$HOME/.aws"

if curl -fsSL "$BASE_URL/aws-config" -o "$HOME/.aws/config.tmp" 2>/dev/null; then
    log_debug "Downloaded aws-config template"
else
    show_error "Failed to download aws-config"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 3: Substitute placeholders
# -----------------------------------------------------------------------------

log_info "Substituting placeholders..."

# Replace __HELPER_PATH__
sed -i.bak "s|__HELPER_PATH__|$HELPER_PATH|g" "$HOME/.aws/config.tmp"
log_debug "Substituted __HELPER_PATH__ with $HELPER_PATH"

# Function to fetch MFA Serial ARN from 1Password
fetch_mfa_serial() {
    local item="$1"
    local vault="$2"

    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] Fetching MFA serial for '$item' from vault '$vault'" >> "$LOG_FILE"

    local account_flag=""
    if [ -n "${OP_ACCOUNT:-}" ]; then
        account_flag="--account $OP_ACCOUNT"
    fi

    local mfa_arn
    # shellcheck disable=SC2086
    mfa_arn=$(op item get "$item" --vault "$vault" $account_flag --format json 2>/dev/null | \
        jq -r '.fields[] | select(.label == "MFA Serial ARN" or .label == "mfa_serial" or .label == "MfaSerial") | .value' | \
        head -1) || true

    if [ -n "$mfa_arn" ] && [ "$mfa_arn" != "null" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] Found MFA serial: $mfa_arn" >> "$LOG_FILE"
        echo "$mfa_arn"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] No MFA serial found for '$item'" >> "$LOG_FILE"
        echo ""
    fi
}

# Replace __MFA_SERIAL:Item:Vault__ placeholders
if command -v op &> /dev/null && op account list --account "$OP_ACCOUNT" &>/dev/null; then
    log_info "1Password authenticated, fetching MFA serials..."

    mfa_count=0
    mfa_success=0

    while IFS= read -r placeholder; do
        if [ -n "$placeholder" ]; then
            mfa_count=$((mfa_count + 1))

            inner="${placeholder#__MFA_SERIAL:}"
            inner="${inner%__}"
            item="${inner%:*}"
            vault="${inner##*:}"

            log_debug "Processing: item='$item', vault='$vault'"

            mfa_serial=$(fetch_mfa_serial "$item" "$vault")

            if [ -n "$mfa_serial" ]; then
                config_content=$(<"$HOME/.aws/config.tmp")
                echo "${config_content//$placeholder/$mfa_serial}" > "$HOME/.aws/config.tmp"
                log_info "Substituted MFA serial for '$item'"
                mfa_success=$((mfa_success + 1))
            fi
        fi
    done < <(grep -o '__MFA_SERIAL:[^_]*__' "$HOME/.aws/config.tmp" 2>/dev/null | sort -u || true)

    log_info "MFA substitution: $mfa_success/$mfa_count successful"
else
    log_info "1Password not authenticated, skipping MFA substitution"
fi

# -----------------------------------------------------------------------------
# Step 4: Deploy config
# -----------------------------------------------------------------------------

mv "$HOME/.aws/config.tmp" "$HOME/.aws/config"
rm -f "$HOME/.aws/config.tmp.bak"
chmod 600 "$HOME/.aws/config"
show "Deployed ~/.aws/config"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

log_info "Sync complete"
log_info "=========================================="

if [ "$INTERACTIVE" = true ]; then
    echo ""
    gum style --foreground 42 --bold "✓ Sync complete!"
    echo ""
fi
