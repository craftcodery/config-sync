#!/bin/bash
# NorthBuilt Configuration Sync
# Pulls latest configs from GitHub and deploys to correct locations
#
# Usage:
#   sync.sh              # Interactive mode (shows gum UI)
#   sync.sh --launchd    # Background mode (verbose logging, no UI)
#   sync.sh --verbose    # Interactive mode with verbose output
#
# Environment Variables:
#   CONFIG_DIR   - Override config directory (default: ~/.craftcodery-config)
#   OP_ACCOUNT   - 1Password account (default: craftcodery.1password.com)

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Allow override for testing, default to ~/.craftcodery-config
CONFIG_DIR="${CONFIG_DIR:-$HOME/.craftcodery-config}"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/craftcodery-config-sync.log"
MAX_LOG_SIZE=1048576  # 1MB - rotate log if larger

# Default OP_ACCOUNT if not set
export OP_ACCOUNT="${OP_ACCOUNT:-craftcodery.1password.com}"

# =============================================================================
# Parse Arguments
# =============================================================================

LAUNCHD_MODE=false
VERBOSE=false

for arg in "$@"; do
    case $arg in
        --launchd)
            LAUNCHD_MODE=true
            VERBOSE=true
            ;;
        --verbose|-v)
            VERBOSE=true
            ;;
    esac
done

# =============================================================================
# Logging Functions
# =============================================================================

# Ensure log directory exists
mkdir -p "$LOG_DIR"

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

log_info() {
    log "INFO" "$1"
}

log_debug() {
    log "DEBUG" "$1"
}

log_warn() {
    log "WARN" "$1"
}

log_error() {
    log "ERROR" "$1"
}

# =============================================================================
# UI Functions (gum-based, only in interactive mode)
# =============================================================================

# Check if running interactively (with a TTY) and gum is available
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

show_warn() {
    log_warn "$1"
    if [ "$INTERACTIVE" = true ]; then
        gum style --foreground 214 "⚠ $1"
    fi
}

error() {
    log_error "$1"
    if [ "$INTERACTIVE" = true ]; then
        gum style --foreground 196 "✗ $1"
    fi
}

spin() {
    local title="$1"
    shift
    log_debug "Running: $*"
    if [ "$INTERACTIVE" = true ]; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        "$@" 2>&1 | while read -r line; do
            log_debug "$line"
        done
        return "${PIPESTATUS[0]}"
    fi
}

# =============================================================================
# Main Sync Logic
# =============================================================================

log_info "=========================================="
log_info "Starting config sync"
log_info "CONFIG_DIR: $CONFIG_DIR"
log_info "OP_ACCOUNT: $OP_ACCOUNT"
log_info "LAUNCHD_MODE: $LAUNCHD_MODE"
log_info "INTERACTIVE: $INTERACTIVE"
log_info "=========================================="

# Header (only in interactive mode)
if [ "$INTERACTIVE" = true ]; then
    gum style \
        --border rounded \
        --border-foreground 39 \
        --padding "0 2" \
        --margin "1 0" \
        "Syncing NorthBuilt Configuration..."
fi

# -----------------------------------------------------------------------------
# Step 1: Pull latest from GitHub
# -----------------------------------------------------------------------------

if [ -d "$CONFIG_DIR/.git" ]; then
    log_info "Git repository found, pulling latest..."
    cd "$CONFIG_DIR"

    if git pull --ff-only 2>&1 | while read -r line; do log_debug "git: $line"; done; then
        show "Git pull successful"
    else
        error "Git pull failed (may be offline or have conflicts)"
    fi
else
    log_warn "Not in git repository ($CONFIG_DIR/.git not found), skipping git pull"
fi

# -----------------------------------------------------------------------------
# Step 2: Determine helper script install location
# -----------------------------------------------------------------------------

HELPER_PATH=""
if sudo -n true 2>/dev/null; then
    HELPER_PATH="/usr/local/bin/aws-vault-1password"
    log_debug "Using system path: $HELPER_PATH (sudo available)"
else
    HELPER_PATH="$HOME/.local/bin/aws-vault-1password"
    log_debug "Using user path: $HELPER_PATH (no sudo)"
fi

# -----------------------------------------------------------------------------
# Step 3: Deploy helper script
# -----------------------------------------------------------------------------

HELPER_SCRIPT="$CONFIG_DIR/bin/aws-vault-1password"
if [ -f "$HELPER_SCRIPT" ]; then
    log_info "Deploying helper script..."

    if [ "$HELPER_PATH" = "/usr/local/bin/aws-vault-1password" ]; then
        sudo mkdir -p /usr/local/bin 2>/dev/null || true
        sudo cp "$HELPER_SCRIPT" /usr/local/bin/
        sudo chmod +x /usr/local/bin/aws-vault-1password
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
                log_info "Added ~/.local/bin to PATH in $SHELL_PROFILE"
            fi
        fi
    fi
else
    error "Helper script not found: $HELPER_SCRIPT"
fi

# -----------------------------------------------------------------------------
# Step 4: Deploy AWS config with substitutions
# -----------------------------------------------------------------------------

# Function to fetch MFA Serial ARN from 1Password
# Note: This function only outputs the MFA ARN to stdout (no logging to stdout)
fetch_mfa_serial() {
    local item="$1"
    local vault="$2"

    # Log to file only (not stdout, since we capture this function's output)
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] Fetching MFA serial for '$item' from vault '$vault'" >> "$LOG_FILE"

    local account_flag=""
    if [ -n "${OP_ACCOUNT:-}" ]; then
        account_flag="--account $OP_ACCOUNT"
    fi

    # Fetch the item and extract MFA Serial ARN field
    # shellcheck disable=SC2086
    local mfa_arn
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

mkdir -p "$HOME/.aws"
if [ -f "$CONFIG_DIR/aws/config" ]; then
    log_info "Deploying AWS config..."

    # Start with the template
    cp "$CONFIG_DIR/aws/config" "$HOME/.aws/config"
    log_debug "Copied template to ~/.aws/config"

    # Replace __HELPER_PATH__ placeholder with actual path
    sed -i.bak "s|__HELPER_PATH__|$HELPER_PATH|g" "$HOME/.aws/config"
    log_debug "Substituted __HELPER_PATH__ with $HELPER_PATH"

    # Replace __MFA_SERIAL:Item:Vault__ placeholders with actual MFA serial ARNs
    # Only do this if 1Password CLI is available and we're signed in
    if command -v op &> /dev/null; then
        log_debug "1Password CLI found, checking authentication..."

        if op account list --account "$OP_ACCOUNT" &>/dev/null; then
            log_info "1Password authenticated, fetching MFA serials..."

            # Find all MFA serial placeholders and replace them
            mfa_count=0
            mfa_success=0

            while IFS= read -r placeholder; do
                if [ -n "$placeholder" ]; then
                    mfa_count=$((mfa_count + 1))

                    # Extract item and vault from placeholder format: __MFA_SERIAL:Item Name:Vault Name__
                    # Remove the __MFA_SERIAL: prefix and __ suffix
                    inner="${placeholder#__MFA_SERIAL:}"
                    inner="${inner%__}"

                    # Split by colon - item is before last colon, vault is after
                    item="${inner%:*}"
                    vault="${inner##*:}"

                    log_debug "Processing placeholder: item='$item', vault='$vault'"

                    # Fetch MFA serial from 1Password
                    mfa_serial=$(fetch_mfa_serial "$item" "$vault")

                    if [ -n "$mfa_serial" ]; then
                        # Read file, replace placeholder (literal string), write back
                        config_content=$(<"$HOME/.aws/config")
                        echo "${config_content//$placeholder/$mfa_serial}" > "$HOME/.aws/config"
                        log_info "Substituted MFA serial for '$item': $mfa_serial"
                        mfa_success=$((mfa_success + 1))
                    else
                        log_warn "Could not fetch MFA serial for '$item' in vault '$vault'"
                    fi
                fi
            done < <(grep -o '__MFA_SERIAL:[^_]*__' "$HOME/.aws/config" 2>/dev/null | sort -u || true)

            log_info "MFA serial substitution complete: $mfa_success/$mfa_count successful"
            show "Deployed ~/.aws/config ($mfa_success MFA serials from 1Password)"
        else
            log_warn "1Password not authenticated for account $OP_ACCOUNT"
            show_warn "Deployed ~/.aws/config (MFA serials not substituted - 1Password not authenticated)"
        fi
    else
        log_warn "1Password CLI not installed"
        show_warn "Deployed ~/.aws/config (MFA serials not substituted - 1Password CLI not installed)"
    fi

    # Clean up backup file
    rm -f "$HOME/.aws/config.bak"
    chmod 600 "$HOME/.aws/config"
    log_debug "Set permissions on ~/.aws/config"
else
    error "AWS config not found: $CONFIG_DIR/aws/config"
fi

# -----------------------------------------------------------------------------
# Step 5: Summary
# -----------------------------------------------------------------------------

log_info "Config sync complete"
log_info "=========================================="

# Summary (only in interactive mode)
if [ "$INTERACTIVE" = true ]; then
    echo ""
    gum style \
        --foreground 42 \
        --bold \
        "✓ Sync complete!"
    echo ""
    gum style \
        --foreground 245 \
        "View logs: cat $LOG_FILE"
fi
