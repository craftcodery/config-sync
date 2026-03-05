# VHS Demo for NorthBuilt AWS Config Sync
# https://github.com/charmbracelet/vhs
# Regenerate with: vhs demo.tape

Output demo.gif

Require gum

Set Shell "zsh"
Set FontSize 13
Set Width 680
Set Height 750
Set Theme "Catppuccin Mocha"
Set Padding 15
Set Framerate 24
Set TypingSpeed 40ms
Set WindowBar Colorful
Set WindowBarSize 40
Set BorderRadius 10

# Setup clean environment
Hide
Type "export PS1='$ ' && clear"
Enter
Show

Sleep 500ms

# Type the curl command
Type "curl -fsSL https://setup.northbuilt.com/aws | bash"
Sleep 600ms
Enter

# Hide the actual execution, run our mock instead
Hide
Ctrl+C
Type "./demo-mock.sh"
Enter
Show

# Wait for the mock script to complete
Sleep 10s
