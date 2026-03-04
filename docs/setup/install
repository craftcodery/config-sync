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
# Phase 4: Configure OP_ACCOUNT for 1Password multi-account support
# =============================================================================

# Determine shell profile
SHELL_PROFILE=""
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_PROFILE="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_PROFILE="$HOME/.bashrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
    SHELL_PROFILE="$HOME/.bash_profile"
fi

# Check if OP_ACCOUNT is already set
if [ -z "${OP_ACCOUNT:-}" ] && [ -n "$SHELL_PROFILE" ]; then
    if ! grep -q "OP_ACCOUNT" "$SHELL_PROFILE" 2>/dev/null; then
        gum style \
            --border rounded \
            --border-foreground 39 \
            --padding "0 2" \
            --margin "1 0" \
            "Configuring 1Password account..."

        # Add OP_ACCOUNT to shell profile
        echo '' >> "$SHELL_PROFILE"
        echo '# 1Password account for AWS credential helper (NorthBuilt)' >> "$SHELL_PROFILE"
        echo 'export OP_ACCOUNT="craftcodery.1password.com"' >> "$SHELL_PROFILE"

        # Export for current session
        export OP_ACCOUNT="craftcodery.1password.com"

        gum style --foreground 42 "✓ OP_ACCOUNT configured in $SHELL_PROFILE"
    else
        gum style --foreground 42 "✓ OP_ACCOUNT already configured"
    fi
else
    if [ -n "${OP_ACCOUNT:-}" ]; then
        gum style --foreground 42 "✓ OP_ACCOUNT already set: $OP_ACCOUNT"
    fi
fi

# =============================================================================
# Phase 5: Set up configuration repository
# =============================================================================

CONFIG_DIR="$HOME/.craftcodery-config"

gum style \
    --border rounded \
    --border-foreground 39 \
    --padding "0 2" \
    --margin "1 0" \
    "Setting up configuration repository..."

# Detect if we're running from within the repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/sync.sh" ] && [ -f "$SCRIPT_DIR/bin/aws-vault-1password" ]; then
    # Running from within the repo - use this location
    if [ "$SCRIPT_DIR" != "$CONFIG_DIR" ]; then
        # Create symlink to this repo
        rm -rf "$CONFIG_DIR" 2>/dev/null || true
        ln -sf "$SCRIPT_DIR" "$CONFIG_DIR"
        gum style --foreground 42 "✓ Linked config: $CONFIG_DIR → $SCRIPT_DIR"
    else
        gum spin --spinner dot --title "Updating config repository..." -- \
            git -C "$CONFIG_DIR" pull --ff-only 2>/dev/null || true
        gum style --foreground 42 "✓ Configuration repository updated"
    fi
elif [ -d "$CONFIG_DIR" ]; then
    # Config dir exists, update it
    gum spin --spinner dot --title "Updating config repository..." -- \
        git -C "$CONFIG_DIR" pull --ff-only 2>/dev/null || true
    gum style --foreground 42 "✓ Configuration repository updated"
else
    # Fresh install via curl | bash - clone the repo
    gum spin --spinner dot --title "Cloning config repository..." -- \
        git clone https://github.com/craftcodery/northbuilt-workstation-config.git "$CONFIG_DIR"
    gum style --foreground 42 "✓ Configuration repository cloned"
fi

# =============================================================================
# Phase 6: Deploy configurations
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
    env CONFIG_DIR="$CONFIG_DIR" OP_ACCOUNT="${OP_ACCOUNT:-craftcodery.1password.com}" "$CONFIG_DIR/sync.sh"

gum style --foreground 42 "✓ Configurations deployed"

# =============================================================================
# Phase 7: Set up automatic sync via launchd
# =============================================================================

gum style \
    --border rounded \
    --border-foreground 39 \
    --padding "0 2" \
    --margin "1 0" \
    "Setting up automatic sync service..."

LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.craftcodery.config-sync.plist"
LOG_DIR="$HOME/Library/Logs"

mkdir -p "$LAUNCHD_DIR"
mkdir -p "$LOG_DIR"

# Unload existing agent if present
launchctl unload "$LAUNCHD_DIR/$PLIST_NAME" 2>/dev/null || true

# Generate plist with absolute paths (launchd doesn't expand $HOME)
cat > "$LAUNCHD_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.craftcodery.config-sync</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-l</string>
        <string>-c</string>
        <string>$HOME/.craftcodery-config/sync.sh --launchd</string>
    </array>

    <key>StartInterval</key>
    <integer>3600</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>ThrottleInterval</key>
    <integer>60</integer>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>$HOME</string>
        <key>OP_ACCOUNT</key>
        <string>craftcodery.1password.com</string>
    </dict>

    <key>WorkingDirectory</key>
    <string>$HOME</string>

    <key>StandardOutPath</key>
    <string>$LOG_DIR/craftcodery-config-sync-launchd.log</string>

    <key>StandardErrorPath</key>
    <string>$LOG_DIR/craftcodery-config-sync-launchd.log</string>
</dict>
</plist>
EOF

# Load the agent
launchctl load "$LAUNCHD_DIR/$PLIST_NAME"

gum style --foreground 42 "✓ Automatic sync service configured (runs hourly)"

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
    "Your workstation is now configured!" \
    "" \
    "Test your NorthBuilt AWS access:" \
    "  aws sts get-caller-identity" \
    "" \
    "Use a client profile:" \
    "  aws sts get-caller-identity --profile donatefordough" \
    "" \
    "Sync runs automatically every hour." \
    "Manual sync: ~/.craftcodery-config/sync.sh" \
    "View logs:   cat ~/Library/Logs/craftcodery-config-sync.log" \
    "" \
    "Documentation: glow ~/.craftcodery-config/README.md"

echo ""
gum style --foreground 245 "Happy building! 🚀"
echo ""
