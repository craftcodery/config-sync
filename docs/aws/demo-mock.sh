#!/usr/bin/env bash
# Mock setup script for VHS demo - simulates the enhanced setup experience
# This creates a beautiful demo without actually running installations

set -euo pipefail

# 80s Retro Synthwave Color Palette
HEX_PINK="#ff71ce"
HEX_PURPLE="#b967ff"
HEX_CYAN="#01cdfe"
HEX_GREEN="#05ffa1"
HEX_GRAY="#6c6783"
HEX_WHITE="#f0e6ff"
HEX_BG="#1a1a2e"

CURRENT_STEP=0
TOTAL_STEPS=8

# Terminal dimensions
TERM_LINES=$(tput lines)
TERM_COLS=$(tput cols)
PROGRESS_LINE=$((TERM_LINES - 1))  # Last line of terminal

# Setup scroll region (excludes bottom line for progress bar)
setup_scroll_region() {
    # Set scroll region from line 0 to TERM_LINES-2 (leaving last line for progress)
    printf '\033[0;%dr' $((TERM_LINES - 1))
    # Move cursor to top of scroll region
    tput cup 0 0
}

# Reset scroll region to full terminal
reset_scroll_region() {
    printf '\033[r'
}

# Draw progress bar at fixed bottom position (no flicker - direct overwrite)
draw_progress() {
    local progress=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local bar_width=30
    local filled=$((progress * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Save cursor, move to bottom line, draw, restore cursor
    tput sc
    tput cup $PROGRESS_LINE 0
    # Build the entire line and print at once (reduces flicker)
    local status_text
    status_text=$(printf "  %s %3d%%  ─  Step %d of %d" "$bar" "$progress" "$CURRENT_STEP" "$TOTAL_STEPS")
    # Pad to full width to overwrite any previous content
    printf '\033[38;2;1;205;254m%s%*s\033[0m' "$status_text" $((TERM_COLS - ${#status_text})) ""
    tput rc
}

# Initialize display with scroll region and bottom progress bar
init_display() {
    clear
    setup_scroll_region
    draw_progress
}

# Cleanup on exit
cleanup() {
    reset_scroll_region
}
trap cleanup EXIT

# Initialize
init_display

# Main logo block with synthwave neon pink
logo=$(gum style \
    --foreground "$HEX_PINK" \
    --background "$HEX_BG" \
    --border double \
    --border-foreground "$HEX_PURPLE" \
    --padding "0 2" \
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
    --foreground "$HEX_CYAN" \
    --italic \
    --padding "0 2" \
    "NorthBuilt Config Sync")

echo ""
gum join --vertical --align center "$logo" "$tagline"
echo ""

sleep 0.8

# Helper functions
show_step() {
    local title="$1"
    ((CURRENT_STEP++))
    draw_progress

    echo ""

    # Step badge with synthwave purple background
    local badge
    badge=$(gum style \
        --foreground "$HEX_WHITE" \
        --background "$HEX_PURPLE" \
        --padding "0 1" \
        --bold \
        "STEP $CURRENT_STEP/$TOTAL_STEPS")

    # Title with pink accent
    local step_title
    step_title=$(gum style \
        --foreground "$HEX_PINK" \
        --bold \
        --padding "0 1" \
        "$title")

    gum join --horizontal --align center "$badge" "$step_title"
}

show_success() {
    gum style --foreground "$HEX_GREEN" --margin "0 1" "✓ $1"
}

# Step 1: Homebrew
show_step "Installing Homebrew"
sleep 0.4
show_success "Homebrew already installed"

# Step 2: UI toolkit
show_step "Installing UI toolkit"
sleep 0.4
show_success "gum already installed"

# Step 3: CLI tools
show_step "Installing CLI tools"
gum spin --spinner meter --spinner.foreground "$HEX_PURPLE" --title "Installing AWS CLI..." -- sleep 0.8
show_success "AWS CLI ready"
gum spin --spinner meter --spinner.foreground "$HEX_PURPLE" --title "Installing jq..." -- sleep 0.5
show_success "jq ready"
gum spin --spinner meter --spinner.foreground "$HEX_PURPLE" --title "Installing glow..." -- sleep 0.5
show_success "glow ready"
gum spin --spinner meter --spinner.foreground "$HEX_PURPLE" --title "Installing 1Password CLI..." -- sleep 0.6
show_success "1Password CLI ready"

# Step 4: Verify 1Password
show_step "Verifying 1Password"
sleep 0.5
show_success "1Password CLI connected"

# Step 5: Configure environment
show_step "Configuring environment"
sleep 0.4
show_success "OP_ACCOUNT already configured"
sleep 0.2
show_success "PATH already configured"

# Step 6: Build native apps
show_step "Building native apps"
gum spin --spinner globe --spinner.foreground "$HEX_CYAN" --title "Downloading credential helper..." -- sleep 0.6
gum spin --spinner dot --spinner.foreground "$HEX_PINK" --title "Compiling credential helper..." -- sleep 1.0
show_success "Credential helper built"
gum spin --spinner globe --spinner.foreground "$HEX_CYAN" --title "Downloading menu bar app..." -- sleep 0.6
gum spin --spinner dot --spinner.foreground "$HEX_PINK" --title "Compiling menu bar app..." -- sleep 1.2
gum spin --spinner globe --spinner.foreground "$HEX_CYAN" --title "Downloading icons..." -- sleep 0.4
show_success "Menu bar app built"

# Step 7: Cleanup
show_step "Cleaning up"
sleep 0.5
show_success "Cleanup complete"

# Step 8: Launch
show_step "Launching app"
sleep 0.4
show_success "Menu bar app launched"
gum spin --spinner pulse --spinner.foreground "$HEX_GREEN" --title "Running initial sync..." -- sleep 1.0

# Final banner with synthwave colors
echo ""

header=$(gum style \
    --foreground "$HEX_GREEN" \
    --bold \
    --align center \
    "✓ Setup Complete!")

info=$(gum style \
    --foreground "$HEX_WHITE" \
    --padding "0 0" \
    "Look for the NorthBuilt icon in your menu bar." \
    "" \
    "$(gum style --foreground "$HEX_PINK" --bold "Test your AWS access:")" \
    "  $(gum style --foreground "$HEX_GRAY" "aws s3 ls")" \
    "" \
    "$(gum style --foreground "$HEX_PINK" --bold "Use a client profile:")" \
    "  $(gum style --foreground "$HEX_GRAY" "aws s3 ls --profile donatefordough")" \
    "" \
    "$(gum style --foreground "$HEX_PINK" --bold "Sync schedule:")" \
    "  $(gum style --foreground "$HEX_GRAY" "Automatic every hour, or click icon to sync now")" \
    "" \
    "$(gum style --foreground "$HEX_PINK" --bold "Enable Launch at Login:")" \
    "  $(gum style --foreground "$HEX_GRAY" "Click NorthBuilt icon → Launch at Login")")

content=$(gum join --vertical --align center "$header" "$info")

gum style \
    --border double \
    --border-foreground "$HEX_GREEN" \
    --padding "1 3" \
    --margin "0 1" \
    "$content"

echo ""

# Hold on final screen so viewers can read
sleep 2
