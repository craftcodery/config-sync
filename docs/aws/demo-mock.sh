#!/usr/bin/env bash
# Mock setup script for VHS demo - simulates the real setup experience
# This creates a beautiful demo without actually running installations

set -euo pipefail

# Brand colors
TEAL="39"
GREEN="42"

# Display the ASCII art logo with gum
echo ""
gum style \
    --foreground 255 \
    --background "#1a5c5c" \
    --border double \
    --border-foreground "$TEAL" \
    --padding "1 2" \
    --margin "0 1" \
    --bold \
    "███╗   ██╗ ██████╗ ██████╗ ████████╗██╗  ██╗" \
    "████╗  ██║██╔═══██╗██╔══██╗╚══██╔══╝██║  ██║" \
    "██╔██╗ ██║██║   ██║██████╔╝   ██║   ███████║" \
    "██║╚██╗██║██║   ██║██╔══██╗   ██║   ██╔══██║" \
    "██║ ╚████║╚██████╔╝██║  ██║   ██║   ██║  ██║" \
    "╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝" \
    "██████╗ ██╗   ██╗██╗██╗  ████████╗          " \
    "██╔══██╗██║   ██║██║██║  ╚══██╔══╝          " \
    "██████╔╝██║   ██║██║██║     ██║             " \
    "██╔══██╗██║   ██║██║██║     ██║             " \
    "██████╔╝╚██████╔╝██║███████╗██║             " \
    "╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═╝             "

gum style \
    --foreground "$TEAL" \
    --margin "0 1" \
    --italic \
    "AWS Config Sync"

echo ""
sleep 0.3

# Phase 1: Homebrew
gum style --foreground "$GREEN" --margin "0 1" "✓ Homebrew already installed"
sleep 0.2

# Phase 2: Install tools
echo ""
gum style \
    --border rounded \
    --border-foreground "$TEAL" \
    --padding "0 2" \
    --margin "0 1" \
    "Installing required tools..."

gum spin --spinner dot --title "Installing AWS CLI..." -- sleep 0.5
gum spin --spinner dot --title "Installing jq..." -- sleep 0.3
gum spin --spinner dot --title "Installing glow..." -- sleep 0.3
gum spin --spinner dot --title "Installing 1Password CLI..." -- sleep 0.4

gum style --foreground "$GREEN" --margin "0 1" "✓ All tools installed"
sleep 0.2

# Phase 3: Verify 1Password
echo ""
gum style \
    --border rounded \
    --border-foreground "$TEAL" \
    --padding "0 2" \
    --margin "0 1" \
    "Verifying 1Password CLI..."

sleep 0.3
gum style --foreground "$GREEN" --margin "0 1" "✓ 1Password CLI connected"
gum style --foreground "$GREEN" --margin "0 1" "✓ OP_ACCOUNT configured"
sleep 0.2

# Phase 4: Build Swift apps
echo ""
gum style \
    --border rounded \
    --border-foreground "$TEAL" \
    --padding "0 2" \
    --margin "0 1" \
    "Building native applications..."

gum spin --spinner dot --title "Downloading credential helper source..." -- sleep 0.3
gum spin --spinner dot --title "Compiling credential helper..." -- sleep 0.6

gum style --foreground "$GREEN" --margin "0 1" "✓ Credential helper compiled"

gum spin --spinner dot --title "Downloading menu bar app source..." -- sleep 0.3
gum spin --spinner dot --title "Compiling menu bar app..." -- sleep 0.8
gum spin --spinner dot --title "Downloading app icons..." -- sleep 0.2

gum style --foreground "$GREEN" --margin "0 1" "✓ Menu bar app built"
sleep 0.2

# Phase 5: Launch app
echo ""
gum style \
    --border rounded \
    --border-foreground "$TEAL" \
    --padding "0 2" \
    --margin "0 1" \
    "Starting menu bar app..."

sleep 0.3
gum style --foreground "$GREEN" --margin "0 1" "✓ Menu bar app launched"

gum spin --spinner dot --title "Running initial sync..." -- sleep 0.6

# Final banner
echo ""
gum style \
    --border double \
    --border-foreground "$GREEN" \
    --padding "1 2" \
    --margin "0 1" \
    --bold \
    "✓ Setup Complete!" \
    "" \
    "Look for the NorthBuilt icon in your menu bar." \
    "" \
    "Test your AWS access:" \
    "  aws s3 ls" \
    "" \
    "Use a client profile:" \
    "  aws s3 ls --profile donatefordough" \
    "" \
    "The menu bar app syncs automatically every hour."

echo ""
