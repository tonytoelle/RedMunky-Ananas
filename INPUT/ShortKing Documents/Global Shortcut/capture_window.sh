#!/bin/zsh
# Capture a window and open it immediately in Preview for annotation

filepath="$HOME/Desktop/Screenshot $(date +%Y-%m-%d_at_%H.%M.%S).png"

# Capture interactive window and open in Preview if successful
screencapture -i -w "$filepath" && open -a Preview "$filepath"
