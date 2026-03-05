# VHS Demo for NorthBuilt AWS Config Sync
# https://github.com/charmbracelet/vhs
# Regenerate with: vhs demo.tape

Output demo.gif

Require gum

Set Shell "zsh"
Set FontSize 14
Set Width 750
Set Height 650
Set Theme "Catppuccin Mocha"
Set Padding 15
Set Framerate 24
Set TypingSpeed 30ms
Set WindowBar Colorful
Set WindowBarSize 40
Set BorderRadius 8

# Hide setup
Hide
Type "export PS1='$ ' && clear"
Enter
Show
Sleep 300ms

# Show ASCII logo
Hide
Type "./demo-output.sh logo"
Enter
Show
Sleep 800ms

Hide
Type "./demo-output.sh tagline"
Enter
Show
Sleep 1.5s

# Setup section
Hide
Type "./demo-output.sh setup"
Enter
Show
Sleep 300ms

Hide
Type "./demo-output.sh setup-cmd"
Enter
Show
Sleep 2s

# Usage section
Hide
Type "./demo-output.sh usage"
Enter
Show
Sleep 300ms

Hide
Type "./demo-output.sh cmd 'aws s3 ls'"
Enter
Show
Sleep 500ms

Hide
Type "./demo-output.sh cmd 'aws s3 ls --profile donatefordough'"
Enter
Show
Sleep 500ms

Hide
Type "./demo-output.sh cmd 'aws s3 ls --profile retina'"
Enter
Show
Sleep 600ms

# Features section
Hide
Type "./demo-output.sh features"
Enter
Show
Sleep 2s

# URL
Hide
Type "./demo-output.sh url"
Enter
Show
Sleep 2s
