#!/bin/bash
# NorthBuilt Workstation Setup
# Run: curl -fsSL https://raw.githubusercontent.com/craftcodery/northbuilt-workstation-config/main/setup.sh | bash

set -euo pipefail

# Colors for pre-gum output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}           ${GREEN}NorthBuilt Workstation Setup${NC}                        ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Phase 1: Install Homebrew (required for everything else)
# =============================================================================

if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}▶ Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    # Add to shell profile for future sessions
    SHELL_PROFILE=""
    if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        SHELL_PROFILE="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
        SHELL_PROFILE="$HOME/.bash_profile"
    fi

    if [[ -n "$SHELL_PROFILE" ]]; then
        if [[ -f /opt/homebrew/bin/brew ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_PROFILE"
        elif [[ -f /usr/local/bin/brew ]]; then
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$SHELL_PROFILE"
        fi
    fi

    echo -e "${GREEN}✓ Homebrew installed${NC}"
else
    echo -e "${GREEN}✓ Homebrew already installed${NC}"
fi

# =============================================================================
# Phase 2: Install gum first (for pretty output in rest of script)
# =============================================================================

if ! command -v gum &> /dev/null; then
    echo -e "${YELLOW}▶ Installing gum (CLI toolkit)...${NC}"
    brew install gum > /dev/null 2>&1
    echo -e "${GREEN}✓ gum installed${NC}"
fi

# =============================================================================
# From here on, we use gum for beautiful output
# =============================================================================

gum style \
    --border rounded \
    --border-foreground 39 \
    --padding "0 2" \
    --margin "1 0" \
    "Installing required tools..."

# Install all tools with spinner
gum spin --spinner dot --title "Installing AWS CLI..." -- brew install awscli 2>/dev/null || true
gum spin --spinner dot --title "Installing aws-vault..." -- brew install aws-vault 2>/dev/null || true
gum spin --spinner dot --title "Installing jq..." -- brew install jq 2>/dev/null || true
gum spin --spinner dot --title "Installing glow..." -- brew install glow 2>/dev/null || true
gum spin --spinner dot --title "Installing 1Password CLI..." -- brew install --cask 1password-cli 2>/dev/null || true

gum style --foreground 42 "✓ All tools installed"

# =============================================================================
# Phase 3: Verify 1Password CLI integration
# =============================================================================

gum style \
    --border rounded \
    --border-foreground 39 \
    --padding "0 2" \
    --margin "1 0" \
    "Verifying 1Password CLI..."

if ! op account list &> /dev/null; then
    gum style \
        --border rounded \
        --border-foreground 196 \
        --foreground 196 \
        --padding "1 2" \
        --margin "1 0" \
        "⚠️  1Password CLI needs to be connected to the 1Password app." \
        "" \
        "Please complete these steps:" \
        "  1. Open 1Password app" \
        "  2. Go to Settings → Developer" \
        "  3. Enable 'Integrate with 1Password CLI'" \
        "" \
        "After enabling, re-run this script."
    exit 1
fi

gum style --foreground 42 "✓ 1Password CLI connected"

# =============================================================================
# Phase 4: Clone/update configuration repository
# =============================================================================

CONFIG_DIR="$HOME/.craftcodery-config"

gum style \
    --border rounded \
    --border-foreground 39 \
    --padding "0 2" \
    --margin "1 0" \
    "Setting up configuration repository..."

if [ -d "$CONFIG_DIR" ]; then
    gum spin --spinner dot --title "Updating config repository..." -- \
        git -C "$CONFIG_DIR" pull --ff-only 2>/dev/null || true
    gum style --foreground 42 "✓ Configuration repository updated"
else
    gum spin --spinner dot --title "Cloning config repository..." -- \
        git clone https://github.com/craftcodery/northbuilt-workstation-config.git "$CONFIG_DIR"
    gum style --foreground 42 "✓ Configuration repository cloned"
fi

# =============================================================================
# Phase 5: Deploy configurations
# =============================================================================

gum style \
    --border rounded \
    --border-foreground 39 \
    --padding "0 2" \
    --margin "1 0" \
    "Deploying configurations..."

# Make sync script executable and run it
chmod +x "$CONFIG_DIR/sync.sh"
gum spin --spinner dot --title "Deploying AWS config and helper scripts..." -- \
    "$CONFIG_DIR/sync.sh"

gum style --foreground 42 "✓ Configurations deployed"

# =============================================================================
# Phase 6: Set up automatic sync via launchd
# =============================================================================

LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.craftcodery.config-sync.plist"
mkdir -p "$LAUNCHD_DIR"

# Unload existing agent if present
launchctl unload "$LAUNCHD_DIR/$PLIST_NAME" 2>/dev/null || true

# Copy and load new agent
cp "$CONFIG_DIR/launchd/$PLIST_NAME" "$LAUNCHD_DIR/"
launchctl load "$LAUNCHD_DIR/$PLIST_NAME"

gum style --foreground 42 "✓ Automatic sync configured (every 4 hours)"

# =============================================================================
# Complete!
# =============================================================================

echo ""
gum style \
    --border double \
    --border-foreground 42 \
    --foreground 42 \
    --padding "1 3" \
    --margin "1 0" \
    --bold \
    "✓ Setup Complete!"

echo ""
gum style \
    --border rounded \
    --border-foreground 39 \
    --padding "1 2" \
    --margin "0 0 1 0" \
    "Next steps:" \
    "" \
    "  1. Run 'aws sso login' to authenticate with NorthBuilt AWS" \
    "  2. Test with 'aws sts get-caller-identity'" \
    "  3. For client accounts: 'aws s3 ls --profile client-acme'" \
    "" \
    "  Configurations will sync automatically every 4 hours." \
    "  View docs: glow ~/.craftcodery-config/README.md"

# Offer to run initial SSO login
echo ""
if gum confirm "Would you like to authenticate with NorthBuilt AWS now?"; then
    echo ""
    aws sso login
    echo ""
    gum style --foreground 42 "✓ Authenticated with NorthBuilt AWS"
fi

echo ""
gum style --foreground 245 "Happy building!"
echo ""
