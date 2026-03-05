# VHS Demo for NorthBuilt AWS Config Sync
# https://github.com/charmbracelet/vhs

Output demo.gif

Set Shell "zsh"
Set FontSize 16
Set Width 900
Set Height 500
Set Theme "Catppuccin Mocha"
Set Padding 20
Set Framerate 30

# Title
Type "# NorthBuilt AWS Config Sync"
Sleep 500ms
Enter
Type "# Automatic AWS credentials via 1Password"
Sleep 500ms
Enter
Enter
Sleep 1s

# Show the setup command
Type "# One-line setup:"
Sleep 300ms
Enter
Type "curl -fsSL https://setup.northbuilt.com/aws | bash"
Sleep 1s
Enter
Sleep 500ms

# Simulate setup output
Type "# Installing tools and compiling native Swift app..."
Sleep 500ms
Enter
Sleep 1s

# Clear and show usage
Type "clear"
Enter
Sleep 500ms

# Show AWS commands working
Type "# After setup, AWS commands just work:"
Sleep 300ms
Enter
Enter
Type "aws s3 ls"
Sleep 500ms
Enter
Sleep 1s
Type "# Credentials fetched automatically from 1Password"
Sleep 300ms
Enter
Enter
Sleep 1s

# Show profile usage
Type "# Use different profiles for different clients:"
Sleep 300ms
Enter
Type "aws s3 ls --profile donatefordough"
Sleep 500ms
Enter
Sleep 500ms
Type "aws s3 ls --profile retina"
Sleep 500ms
Enter
Sleep 500ms
Type "aws s3 ls --profile act"
Sleep 500ms
Enter
Sleep 1s
Enter

# Show menu bar info
Type "clear"
Enter
Sleep 500ms
Type "# Menu bar app features:"
Sleep 300ms
Enter
Type "#   - Syncs automatically every hour"
Sleep 200ms
Enter
Type "#   - Shows sync status"
Sleep 200ms
Enter
Type "#   - Manual sync with Cmd+S"
Sleep 200ms
Enter
Type "#   - Self-updates from source"
Sleep 200ms
Enter
Type "#   - Network-aware (skips when offline)"
Sleep 200ms
Enter
Type "#   - Launch at Login support"
Sleep 200ms
Enter
Enter
Sleep 2s

# End
Type "# Learn more: https://setup.northbuilt.com/aws"
Sleep 500ms
Enter
Sleep 2s
