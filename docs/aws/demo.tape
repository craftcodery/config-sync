# VHS Demo for NorthBuilt AWS Config Sync
# https://github.com/charmbracelet/vhs
# Regenerate with: vhs demo.tape

Output demo.gif

Require gum

# Shell and typography
Set Shell "zsh"
Set FontSize 13
Set LineHeight 1.3

# Dimensions - wide enough to prevent text wrapping
Set Width 850
Set Height 480
Set Padding 20

# Window styling (commented out - available if needed)
# Set Margin 40
# Set MarginFill "#0f172a"
# Set WindowBar Colorful
# Set WindowBarSize 40
# Set BorderRadius 10

# Color theme - 80s Retro Synthwave palette
# Custom theme matching the script's color scheme
Set Theme { "name": "Synthwave", "black": "#16213e", "red": "#fe4a49", "green": "#05ffa1", "yellow": "#fffb96", "blue": "#707ff5", "magenta": "#ff71ce", "cyan": "#01cdfe", "white": "#f0e6ff", "brightBlack": "#6c6783", "brightRed": "#ff6b6b", "brightGreen": "#00ffaa", "brightYellow": "#ffff99", "brightBlue": "#8b9fff", "brightMagenta": "#f2a1f2", "brightCyan": "#66d9ff", "brightWhite": "#ffffff", "background": "#1a1a2e", "foreground": "#f0e6ff", "selection": "#3d3d5c", "cursor": "#ff71ce" }
Set CursorBlink false

# Animation settings
Set TypingSpeed 25ms
Set Framerate 50
Set PlaybackSpeed 1.0
Set LoopOffset 0%

# Setup clean environment
Hide
Type "export PS1='$ ' && clear"
Enter
Show

Sleep 100ms

# Type the install command (purely visual - never actually executed)
Type "curl -fsSL https://config.northbuilt.com/aws | bash"
Sleep 500ms
Enter

# Hide immediately, run mock script, wait for it to clear screen before showing
Hide
Sleep 100ms
Ctrl+C
Type "./demo-mock.sh"
Enter
Sleep 500ms
Show

# Wait for the mock script to complete
Sleep 15s
