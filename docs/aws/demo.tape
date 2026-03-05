# VHS Demo for NorthBuilt AWS Config Sync
# https://github.com/charmbracelet/vhs
# Regenerate with: vhs demo.tape

Output demo.gif

Require gum

# Shell and typography
Set Shell "zsh"
Set FontFamily "JetBrains Mono"
Set FontSize 14
Set LetterSpacing 1
Set LineHeight 1.4

# Dimensions optimized for the tall logo
Set Width 720
Set Height 900
Set Padding 25

# Window styling for polished macOS look
Set Margin 40
Set MarginFill "#0f172a"
Set WindowBar Colorful
Set WindowBarSize 40
Set BorderRadius 10

# Color theme
Set Theme "Catppuccin Mocha"
Set CursorBlink false

# Animation settings
Set TypingSpeed 50ms
Set Framerate 50
Set PlaybackSpeed 1.0
Set LoopOffset 60%

# Setup clean environment
Hide
Type "export PS1='$ ' && clear"
Enter
Show

Sleep 400ms

# Type the install command (this is what users will see)
Type "curl -fsSL https://setup.northbuilt.com/aws | bash"
Sleep 500ms
Enter

# Hide the actual execution, run our mock instead
Hide
Ctrl+C
Type "./demo-mock.sh"
Enter
Show

# Wait for the mock script to complete
Sleep 12s
