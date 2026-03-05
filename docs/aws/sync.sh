#!/bin/bash
# NorthBuilt AWS Configuration Sync
# Downloads latest configs from setup.northbuilt.com/aws and deploys them
#
# Usage:
#   sync.sh
#
# Logs to ~/Library/Logs/northbuilt-aws-config-sync.log
# When run by launchd, stdout is also redirected to the log file.

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

BASE_URL="https://setup.northbuilt.com/aws"
CONFIG_DIR="$HOME/.northbuilt/aws"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/northbuilt-aws-config-sync.log"
MAX_LOG_SIZE=1048576  # 1MB

export OP_ACCOUNT="${OP_ACCOUNT:-craftcodery.1password.com}"

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
    local line="[$timestamp] [$level] $message"
    echo "$line" >> "$LOG_FILE"
    echo "$line"
}

log_info() { log "INFO" "$1"; }
log_debug() { log "DEBUG" "$1"; }
log_error() { log "ERROR" "$1"; }

# =============================================================================
# Main Sync Logic
# =============================================================================

log_info "=========================================="
log_info "Starting config sync"
log_info "BASE_URL: $BASE_URL"
log_info "CONFIG_DIR: $CONFIG_DIR"
log_info "=========================================="

# -----------------------------------------------------------------------------
# Step 1: Update sync script itself
# -----------------------------------------------------------------------------

log_info "Checking for sync script updates..."
SYNC_PATH="$CONFIG_DIR/sync.sh"

if curl -fsSL "$BASE_URL/sync.sh" -o "$SYNC_PATH.tmp" 2>/dev/null; then
    if ! cmp -s "$SYNC_PATH.tmp" "$SYNC_PATH" 2>/dev/null; then
        mv "$SYNC_PATH.tmp" "$SYNC_PATH"
        chmod +x "$SYNC_PATH"
        log_info "Sync script updated"
    else
        rm -f "$SYNC_PATH.tmp"
        log_debug "Sync script unchanged"
    fi
else
    rm -f "$SYNC_PATH.tmp"
    log_debug "Could not check for sync script updates"
fi

# -----------------------------------------------------------------------------
# Step 2: Download helper script
# -----------------------------------------------------------------------------

log_info "Downloading helper script..."
HELPER_PATH="$CONFIG_DIR/aws-vault-1password"

if curl -fsSL "$BASE_URL/aws-vault-1password" -o "$HELPER_PATH.tmp" 2>/dev/null; then
    mv "$HELPER_PATH.tmp" "$HELPER_PATH"
    chmod +x "$HELPER_PATH"
    log_info "Downloaded aws-vault-1password"
else
    log_error "Failed to download aws-vault-1password"
fi

# Ensure config dir is in PATH
if [[ ":$PATH:" != *":$CONFIG_DIR:"* ]]; then
    SHELL_PROFILE=""
    if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        SHELL_PROFILE="$HOME/.bashrc"
    fi
    if [[ -n "$SHELL_PROFILE" ]] && ! grep -q ".northbuilt/aws" "$SHELL_PROFILE" 2>/dev/null; then
        echo '' >> "$SHELL_PROFILE"
        echo '# NorthBuilt AWS tools' >> "$SHELL_PROFILE"
        echo 'export PATH="$HOME/.northbuilt/aws:$PATH"' >> "$SHELL_PROFILE"
        log_info "Added ~/.northbuilt/aws to PATH in $SHELL_PROFILE"
    fi
fi

# -----------------------------------------------------------------------------
# Step 3: Download AWS config template
# -----------------------------------------------------------------------------

log_info "Downloading AWS config..."
mkdir -p "$HOME/.aws"

if curl -fsSL "$BASE_URL/aws-config" -o "$HOME/.aws/config.tmp" 2>/dev/null; then
    log_debug "Downloaded aws-config template"
else
    log_error "Failed to download aws-config"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 4: Substitute placeholders
# -----------------------------------------------------------------------------

log_info "Substituting placeholders..."

# Replace __HELPER_PATH__
sed -i.bak "s|__HELPER_PATH__|$HELPER_PATH|g" "$HOME/.aws/config.tmp"
log_debug "Substituted __HELPER_PATH__ with $HELPER_PATH"

# Replace __MFA_SERIAL:Item:Vault__ placeholders
# Uses parallel fetches to minimize 1Password CLI calls
if command -v op &> /dev/null && op account list --account "$OP_ACCOUNT" &>/dev/null; then
    log_info "1Password authenticated, fetching MFA serials..."

    # Build account flag
    account_flag=""
    if [ -n "${OP_ACCOUNT:-}" ]; then
        account_flag="--account $OP_ACCOUNT"
    fi

    # Collect all unique placeholders
    placeholders=()
    while IFS= read -r placeholder; do
        [ -n "$placeholder" ] && placeholders+=("$placeholder")
    done < <(grep -o '__MFA_SERIAL:[^_]*__' "$HOME/.aws/config.tmp" 2>/dev/null | sort -u || true)

    mfa_count=${#placeholders[@]}
    log_debug "Found $mfa_count MFA placeholders"

    if [ "$mfa_count" -gt 0 ]; then
        # Create temp directory for parallel fetch results
        tmp_dir=$(mktemp -d)
        trap 'rm -rf "$tmp_dir"' EXIT

        # Launch parallel fetches
        for i in "${!placeholders[@]}"; do
            placeholder="${placeholders[$i]}"
            inner="${placeholder#__MFA_SERIAL:}"
            inner="${inner%__}"
            item="${inner%:*}"
            vault="${inner##*:}"

            log_debug "Fetching: item='$item', vault='$vault'"

            # Fetch in background, save result to temp file
            (
                # shellcheck disable=SC2086
                mfa_arn=$(op item get "$item" --vault "$vault" $account_flag --format json 2>/dev/null | \
                    jq -r '.fields[] | select(.label == "MFA Serial ARN" or .label == "mfa_serial" or .label == "MfaSerial") | .value' | \
                    head -1) || true
                if [ -n "$mfa_arn" ] && [ "$mfa_arn" != "null" ]; then
                    echo "$mfa_arn" > "$tmp_dir/$i"
                fi
            ) &
        done

        # Wait for all background jobs
        wait

        # Apply substitutions from results
        mfa_success=0
        for i in "${!placeholders[@]}"; do
            placeholder="${placeholders[$i]}"
            if [ -f "$tmp_dir/$i" ]; then
                mfa_serial=$(<"$tmp_dir/$i")
                inner="${placeholder#__MFA_SERIAL:}"
                inner="${inner%__}"
                item="${inner%:*}"

                config_content=$(<"$HOME/.aws/config.tmp")
                echo "${config_content//$placeholder/$mfa_serial}" > "$HOME/.aws/config.tmp"
                log_info "Substituted MFA serial for '$item'"
                mfa_success=$((mfa_success + 1))
            fi
        done

        log_info "MFA substitution: $mfa_success/$mfa_count successful"
    fi
else
    log_info "1Password not authenticated, skipping MFA substitution"
fi

# -----------------------------------------------------------------------------
# Step 5: Deploy config
# -----------------------------------------------------------------------------

mv "$HOME/.aws/config.tmp" "$HOME/.aws/config"
rm -f "$HOME/.aws/config.tmp.bak"
chmod 600 "$HOME/.aws/config"
log_info "Deployed ~/.aws/config"

log_info "Sync complete"
log_info "=========================================="
