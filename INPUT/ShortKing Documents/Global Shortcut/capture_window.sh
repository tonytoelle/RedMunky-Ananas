#!/bin/zsh
# Capture a window and open it immediately in Preview for annotation

filepath="$HOME/Desktop/Screenshot $(date +%Y-%m-%d_at_%H.%M.%S).png"

# Capture interactive window and open in Preview if successful
if screencapture -i -w "$filepath"; then
    open -a Preview "$filepath"
    sleep 0.5
    osascript -e '
    tell application "System Events"
        tell process "Preview"
            set frontmost to true
            try
                if exists menu item "Show Markup Toolbar" of menu 1 of menu bar item "View" of menu bar 1 then
                    click menu item "Show Markup Toolbar" of menu 1 of menu bar item "View" of menu bar 1
                else
                    keystroke "a" using {command down, shift down}
                end if
                
                delay 0.3
                
                tell window 1
                    if exists toolbar 2 then
                        if exists button "Sketch" of toolbar 2 then
                            click button "Sketch" of toolbar 2
                        else if exists button "Sketsa" of toolbar 2 then
                            click button "Sketsa" of toolbar 2
                        else
                            click button 3 of toolbar 2
                        end if
                    end if
                end tell
            on error
                keystroke "a" using {command down, shift down}
            end try
        end tell
    end tell
    '
fi
