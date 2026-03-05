# VHS Demo for NorthBuilt AWS Config Sync
# https://github.com/charmbracelet/vhs
# Regenerate with: vhs demo.tape

Output demo.gif

Require gum
Require curl

Set Shell "zsh"
Set FontSize 14
Set Width 750
Set Height 680
Set Theme "Catppuccin Mocha"
Set Padding 15
Set Framerate 24
Set TypingSpeed 50ms
Set WindowBar Colorful
Set WindowBarSize 40
Set BorderRadius 8

# Clean prompt
Hide
Type "export PS1='$ ' && clear"
Enter
Show
Sleep 300ms

# Type and run the actual setup command
Type "curl -fsSL https://setup.northbuilt.com/aws | bash"
Sleep 800ms
Enter

# Wait for script to complete (adjust based on actual runtime)
Sleep 120s
