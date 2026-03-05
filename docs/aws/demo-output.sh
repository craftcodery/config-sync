#!/bin/bash
# Demo output script for VHS recording
# Uses gum for beautiful styled output

TEAL="#1a5c5c"
WHITE="#ffffff"

case "$1" in
  logo)
    gum style \
      --foreground "$WHITE" \
      --background "$TEAL" \
      --border double \
      --border-foreground "$WHITE" \
      --padding "1 3" \
      --margin "1" \
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
    ;;
  logo-simple)
    gum style \
      --foreground "$WHITE" \
      --background "$TEAL" \
      --border double \
      --border-foreground "$WHITE" \
      --padding "1 4" \
      --margin "1" \
      --bold \
      --align center \
      "  NORTH  " \
      "  BUILT  "
    ;;
  tagline)
    gum style \
      --foreground 212 \
      --italic \
      "AWS Config Sync • Automatic 1Password Integration"
    ;;
  setup)
    echo ""
    gum style \
      --foreground 86 \
      --bold \
      "📦 One-line setup:"
    ;;
  setup-cmd)
    gum style \
      --foreground 255 \
      --background 236 \
      --padding "0 2" \
      --margin "0 2" \
      'curl -fsSL https://setup.northbuilt.com/aws | bash'
    ;;
  usage)
    echo ""
    gum style \
      --foreground 86 \
      --bold \
      "✨ After setup, AWS commands just work:"
    ;;
  cmd)
    gum style \
      --foreground 45 \
      --margin "0 2" \
      "$ $2"
    ;;
  features)
    echo ""
    gum style \
      --foreground 86 \
      --bold \
      "🖥️  Menu bar app features:"
    echo ""
    gum style \
      --foreground 255 \
      --margin "0 4" \
      "• Hourly automatic sync" \
      "• Self-updates from source" \
      "• Network-aware" \
      "• Failure notifications" \
      "• Launch at Login"
    ;;
  url)
    echo ""
    gum style \
      --foreground 39 \
      --bold \
      "🔗 https://setup.northbuilt.com/aws"
    ;;
esac
