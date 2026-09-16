#!/bin/zsh
# Trigger the native macOS Window -> Move & Resize -> Left tiling action

osascript -e '
tell application "System Events"
    set frontmostProcess to first process whose frontmost is true
    tell frontmostProcess
        try
            click menu item "Left" of menu 1 of menu item "Move & Resize" of menu 1 of menu bar item "Window" of menu bar 1
        end try
    end tell
end tell
'
