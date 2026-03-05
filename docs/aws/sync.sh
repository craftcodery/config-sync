#!/bin/bash
# NorthBuilt AWS Configuration Sync
# Downloads latest configs from setup.northbuilt.com/aws and deploys them
#
# Usage:
#   sync.sh
#
# Security:
#   - All downloads are verified against CHECKSUMS before deployment
#   - If any checksum fails, sync is aborted and existing files are kept
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
DOWNLOAD_DIR=""  # Set during execution

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
    echo "[$timestamp] [$level] $message"
}

log_info() { log "INFO" "$1"; }
log_debug() { log "DEBUG" "$1"; }
log_error() { log "ERROR" "$1"; }

# =============================================================================
# Checksum Verification
# =============================================================================

# Parse CHECKSUMS file and return expected hash for a filename
get_expected_checksum() {
    local checksums_file="$1"
    local filename="$2"
    grep -E "^[a-f0-9]+[[:space:]]+${filename}$" "$checksums_file" | awk '{print $1}' | head -1
}

# Verify a file against expected checksum
verify_checksum() {
    local file="$1"
    local expected="$2"
    local actual
    actual=$(shasum -a 256 "$file" | awk '{print $1}')

    if [ "$actual" = "$expected" ]; then
        return 0
    else
        log_error "Checksum mismatch for $(basename "$file")"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        return 1
    fi
}

# =============================================================================
# Download with Verification
# =============================================================================

download_and_verify() {
    local filename="$1"
    local checksums_file="$2"
    local dest="$DOWNLOAD_DIR/$filename"

    # Download file
    if ! curl -fsSL "$BASE_URL/$filename" -o "$dest" 2>/dev/null; then
        log_error "Failed to download $filename"
        return 1
    fi

    # Get expected checksum
    local expected
    expected=$(get_expected_checksum "$checksums_file" "$filename")

    if [ -z "$expected" ]; then
        log_error "No checksum found for $filename in CHECKSUMS"
        return 1
    fi

    # Verify checksum
    if ! verify_checksum "$dest" "$expected"; then
        return 1
    fi

    log_info "Verified $filename"
    return 0
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    if [ -n "$DOWNLOAD_DIR" ] && [ -d "$DOWNLOAD_DIR" ]; then
        rm -rf "$DOWNLOAD_DIR"
    fi
}
trap cleanup EXIT

# =============================================================================
# Main Sync Logic
# =============================================================================

log_info "=========================================="
log_info "Starting config sync"
log_info "BASE_URL: $BASE_URL"
log_info "CONFIG_DIR: $CONFIG_DIR"
log_info "=========================================="

# Create temp directory for downloads
DOWNLOAD_DIR=$(mktemp -d)
log_debug "Download directory: $DOWNLOAD_DIR"

# -----------------------------------------------------------------------------
# Step 1: Download and parse CHECKSUMS
# -----------------------------------------------------------------------------

log_info "Downloading CHECKSUMS..."
CHECKSUMS_FILE="$DOWNLOAD_DIR/CHECKSUMS"

if ! curl -fsSL "$BASE_URL/CHECKSUMS" -o "$CHECKSUMS_FILE" 2>/dev/null; then
    log_error "Failed to download CHECKSUMS file"
    log_error "Sync aborted - cannot verify file integrity"
    exit 1
fi

log_info "CHECKSUMS downloaded"

# -----------------------------------------------------------------------------
# Step 2: Download and verify all files
# -----------------------------------------------------------------------------

log_info "Downloading and verifying files..."

VERIFY_FAILED=0

# Download sync.sh
if ! download_and_verify "sync.sh" "$CHECKSUMS_FILE"; then
    VERIFY_FAILED=1
fi

# Download aws-vault-1password
if ! download_and_verify "aws-vault-1password" "$CHECKSUMS_FILE"; then
    VERIFY_FAILED=1
fi

# Download aws-config
if ! download_and_verify "aws-config" "$CHECKSUMS_FILE"; then
    VERIFY_FAILED=1
fi

# Abort if any verification failed
if [ "$VERIFY_FAILED" -eq 1 ]; then
    log_error "One or more files failed verification"
    log_error "Sync aborted - keeping existing files"
    log_info "=========================================="
    exit 1
fi

log_info "All files verified successfully"

# -----------------------------------------------------------------------------
# Step 3: Deploy verified files
# -----------------------------------------------------------------------------

log_info "Deploying verified files..."

# Deploy sync.sh (self-update)
SYNC_PATH="$CONFIG_DIR/sync.sh"
if ! cmp -s "$DOWNLOAD_DIR/sync.sh" "$SYNC_PATH" 2>/dev/null; then
    cp "$DOWNLOAD_DIR/sync.sh" "$SYNC_PATH"
    chmod +x "$SYNC_PATH"
    log_info "Updated sync.sh"
else
    log_debug "sync.sh unchanged"
fi

# Deploy aws-vault-1password
HELPER_PATH="$CONFIG_DIR/aws-vault-1password"
if ! cmp -s "$DOWNLOAD_DIR/aws-vault-1password" "$HELPER_PATH" 2>/dev/null; then
    cp "$DOWNLOAD_DIR/aws-vault-1password" "$HELPER_PATH"
    chmod +x "$HELPER_PATH"
    log_info "Updated aws-vault-1password"
else
    log_debug "aws-vault-1password unchanged"
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
# Step 4: Process AWS config template
# -----------------------------------------------------------------------------

log_info "Processing AWS config..."
mkdir -p "$HOME/.aws"

cp "$DOWNLOAD_DIR/aws-config" "$HOME/.aws/config.tmp"

# Replace __HELPER_PATH__
sed -i.bak "s|__HELPER_PATH__|$HELPER_PATH|g" "$HOME/.aws/config.tmp"
log_debug "Substituted __HELPER_PATH__ with $HELPER_PATH"

# Replace __MFA_SERIAL:Item:Vault__ placeholders
if command -v op &> /dev/null && op account list --account "$OP_ACCOUNT" &>/dev/null; then
    log_info "1Password authenticated, fetching MFA serials..."

    account_flag="--account $OP_ACCOUNT"

    # Collect all unique placeholders
    placeholders=()
    while IFS= read -r placeholder; do
        [ -n "$placeholder" ] && placeholders+=("$placeholder")
    done < <(grep -o '__MFA_SERIAL:[^_]*__' "$HOME/.aws/config.tmp" 2>/dev/null | sort -u || true)

    mfa_count=${#placeholders[@]}
    log_debug "Found $mfa_count MFA placeholders"

    if [ "$mfa_count" -gt 0 ]; then
        # Create temp directory for parallel fetch results
        mfa_tmp_dir=$(mktemp -d)

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
                    echo "$mfa_arn" > "$mfa_tmp_dir/$i"
                fi
            ) &
        done

        # Wait for all background jobs
        wait

        # Apply substitutions from results
        mfa_success=0
        for i in "${!placeholders[@]}"; do
            placeholder="${placeholders[$i]}"
            if [ -f "$mfa_tmp_dir/$i" ]; then
                mfa_serial=$(<"$mfa_tmp_dir/$i")
                inner="${placeholder#__MFA_SERIAL:}"
                inner="${inner%__}"
                item="${inner%:*}"

                config_content=$(<"$HOME/.aws/config.tmp")
                echo "${config_content//$placeholder/$mfa_serial}" > "$HOME/.aws/config.tmp"
                log_info "Substituted MFA serial for '$item'"
                mfa_success=$((mfa_success + 1))
            fi
        done

        rm -rf "$mfa_tmp_dir"
        log_info "MFA substitution: $mfa_success/$mfa_count successful"
    fi
else
    log_info "1Password not authenticated, skipping MFA substitution"
fi

# -----------------------------------------------------------------------------
# Step 5: Deploy config (only if no unsubstituted placeholders remain)
# -----------------------------------------------------------------------------

if grep -q '__MFA_SERIAL:' "$HOME/.aws/config.tmp" 2>/dev/null; then
    log_error "Config has unsubstituted MFA placeholders - keeping previous config"
    log_info "This usually means 1Password is locked. Unlock it and run sync again."
    rm -f "$HOME/.aws/config.tmp" "$HOME/.aws/config.tmp.bak"
    log_info "Sync aborted"
    log_info "=========================================="
    exit 1
fi

mv "$HOME/.aws/config.tmp" "$HOME/.aws/config"
rm -f "$HOME/.aws/config.tmp.bak"
chmod 600 "$HOME/.aws/config"
log_info "Deployed ~/.aws/config"

log_info "Sync complete"
log_info "=========================================="
