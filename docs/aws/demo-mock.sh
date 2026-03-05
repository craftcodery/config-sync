#!/usr/bin/env bash
# Mock setup script for VHS demo - simulates the enhanced setup experience
# This creates a beautiful demo without actually running installations

set -euo pipefail

# Brand colors
TEAL="38"
GREEN="42"
WHITE="255"
GRAY="245"
HEX_TEAL="#00a5a5"
HEX_TEAL_DARK="#1a5c5c"
HEX_GREEN="#00d787"

CURRENT_STEP=0
TOTAL_STEPS=8

# Clear and show logo
clear
echo ""

# Main logo block
logo=$(gum style \
    --foreground "$WHITE" \
    --background "$HEX_TEAL_DARK" \
    --border double \
    --border-foreground "$TEAL" \
    --padding "1 3" \
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
    "╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═╝             ")

tagline=$(gum style \
    --foreground "$TEAL" \
    --italic \
    --padding "0 2" \
    "AWS Config Sync • Powered by 1Password")

gum join --vertical --align center "$logo" "$tagline"
echo ""
sleep 0.3

# Helper functions
show_step() {
    local title="$1"
    ((CURRENT_STEP++))
    echo ""

    local badge
    badge=$(gum style \
        --foreground "$WHITE" \
        --background "$HEX_TEAL" \
        --padding "0 1" \
        --bold \
        "STEP $CURRENT_STEP/$TOTAL_STEPS")

    local step_title
    step_title=$(gum style \
        --foreground "$WHITE" \
        --bold \
        --padding "0 1" \
        "$title")

    gum join --horizontal --align center "$badge" "$step_title"

    local progress=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((progress / 5))
    local empty=$((20 - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    gum style --foreground "$TEAL" --faint "    $bar $progress%"
}

show_success() {
    gum style --foreground "$GREEN" --margin "0 1" "✓ $1"
}

# Step 1: Homebrew
show_step "Installing Homebrew"
sleep 0.15
show_success "Homebrew already installed"

# Step 2: UI toolkit
show_step "Installing UI toolkit"
sleep 0.15
show_success "gum already installed"

# Step 3: CLI tools
show_step "Installing CLI tools"
gum spin --spinner meter --spinner.foreground "$TEAL" --title "Installing AWS CLI..." -- sleep 0.3
show_success "AWS CLI ready"
gum spin --spinner meter --spinner.foreground "$TEAL" --title "Installing jq..." -- sleep 0.2
show_success "jq ready"
gum spin --spinner meter --spinner.foreground "$TEAL" --title "Installing glow..." -- sleep 0.2
show_success "glow ready"
gum spin --spinner meter --spinner.foreground "$TEAL" --title "Installing 1Password CLI..." -- sleep 0.25
show_success "1Password CLI ready"

# Step 4: Verify 1Password
show_step "Verifying 1Password"
sleep 0.2
show_success "1Password CLI connected"

# Step 5: Configure environment
show_step "Configuring environment"
sleep 0.15
show_success "OP_ACCOUNT already configured"
show_success "PATH already configured"

# Step 6: Build native apps
show_step "Building native apps"
gum spin --spinner globe --spinner.foreground "$TEAL" --title "Downloading credential helper..." -- sleep 0.25
gum spin --spinner dot --spinner.foreground "$TEAL" --title "Compiling credential helper..." -- sleep 0.4
show_success "Credential helper built"
gum spin --spinner globe --spinner.foreground "$TEAL" --title "Downloading menu bar app..." -- sleep 0.25
gum spin --spinner dot --spinner.foreground "$TEAL" --title "Compiling menu bar app..." -- sleep 0.5
gum spin --spinner globe --spinner.foreground "$TEAL" --title "Downloading icons..." -- sleep 0.15
show_success "Menu bar app built"

# Step 7: Cleanup
show_step "Cleaning up"
sleep 0.15
show_success "Cleanup complete"

# Step 8: Launch
show_step "Launching app"
sleep 0.15
show_success "Menu bar app launched"
gum spin --spinner pulse --spinner.foreground "$GREEN" --title "Running initial sync..." -- sleep 0.4

# Final banner
echo ""

header=$(gum style \
    --foreground "$GREEN" \
    --bold \
    --align center \
    "✓ Setup Complete!")

info=$(gum style \
    --foreground "$WHITE" \
    --padding "1 0" \
    "Look for the NorthBuilt icon in your menu bar." \
    "" \
    "$(gum style --foreground "$TEAL" --bold "Test your AWS access:")" \
    "  $(gum style --foreground "$GRAY" "aws s3 ls")" \
    "" \
    "$(gum style --foreground "$TEAL" --bold "Use a client profile:")" \
    "  $(gum style --foreground "$GRAY" "aws s3 ls --profile donatefordough")" \
    "" \
    "$(gum style --foreground "$TEAL" --bold "Sync schedule:")" \
    "  $(gum style --foreground "$GRAY" "Automatic every hour, or click icon to sync now")" \
    "" \
    "$(gum style --foreground "$TEAL" --bold "Enable Launch at Login:")" \
    "  $(gum style --foreground "$GRAY" "Click NorthBuilt icon → Launch at Login")")

content=$(gum join --vertical --align center "$header" "$info")

gum style \
    --border double \
    --border-foreground "$GREEN" \
    --padding "1 3" \
    --margin "0 1" \
    "$content"

echo ""
