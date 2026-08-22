#!/bin/zsh
# Trigger the native Preview -> Tools -> Annotate -> Rectangle menu action

osascript -e '
tell application "System Events"
    tell process "Preview"
        set frontmost to true
        try
            # Click Tools -> Annotate -> Rectangle
            click menu item "Rectangle" of menu 1 of menu item "Annotate" of menu 1 of menu bar item "Tools" of menu bar 1
        on error err
            log err
        end try
    end tell
end tell
'
