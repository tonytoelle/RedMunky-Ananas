#!/bin/zsh
# Change screen brightness by simulating hardware keys
# Args: "up" or "down"

action=$1

osascript -e "
tell application \"System Events\"
    if \"$action\" is \"up\" then
        key code 144
    else
        key code 145
    end if
end tell
"
