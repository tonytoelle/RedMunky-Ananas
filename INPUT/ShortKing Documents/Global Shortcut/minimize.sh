#!/bin/zsh
# Minimize the frontmost window of the active application without System Events

osascript -e '
try
    tell application (path to frontmost application as text)
        set miniaturized of window 1 to true
    end tell
end try
'
