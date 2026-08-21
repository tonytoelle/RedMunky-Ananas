#!/bin/zsh
# Quit all foreground applications except essential ones

EXCLUDED=(
  "com.apple.finder"
  "com.redmunky.shortking"
  "com.google.antigravity"
  "com.googlecode.iterm2"
  "com.apple.Terminal"
)

while IFS= read -r bid; do
  [[ -z "$bid" ]] && continue
  skip=false
  for ex in "${EXCLUDED[@]}"; do
    [[ "$bid" == "$ex" ]] && skip=true && break
  done
  $skip && continue
  osascript -e "tell application id \"$bid\" to quit" &
done < <(lsappinfo list | grep -B 4 'type="Foreground"' | grep 'bundleID=' | sed -E 's/.*bundleID="([^"]*)".*/\1/')

wait
