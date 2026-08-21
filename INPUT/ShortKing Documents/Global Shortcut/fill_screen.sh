#!/bin/zsh
# Maximize/Zoom the frontmost window to fill the screen

osascript -e '
tell application "System Events"
    set frontApp to first application process whose frontmost is true
    if (count of windows of frontApp) > 0 then
        set frontWindow to front window of frontApp
        try
            click (first button of frontWindow whose subrole is "AXZoomButton")
        on error
            try
                set value of attribute "AXZoomButton" of frontWindow to true
            end try
        end try
    end if
end tell
'
