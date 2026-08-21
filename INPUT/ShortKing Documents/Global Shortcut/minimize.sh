#!/bin/zsh
# Minimize the frontmost window of the active application

osascript -e '
tell application "System Events"
    set frontmostProcess to first process whose frontmost is true
    tell frontmostProcess
        if (count of windows) > 0 then
            set miniaturized of window 1 to true
        end if
    end tell
end tell
'
