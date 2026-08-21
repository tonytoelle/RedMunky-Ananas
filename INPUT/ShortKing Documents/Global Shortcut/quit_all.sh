#!/bin/zsh
# Quit foreground applications, hide excluded ones (except Finder & ShortKing itself)

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
    if [[ "$bid" == "$ex" ]]; then
      skip=true
      break
    fi
  done
  
  if $skip; then
    # Menggunakan system events untuk menyembunyikan secara global (hanya jika bukan Finder/ShortKing)
    if [[ "$bid" != "com.apple.finder" && "$bid" != "com.redmunky.shortking" ]]; then
      # Cara paling aman menyembunyikan aplikasi tanpa memicu error window
      osascript -e "tell application \"System Events\" to set visible of every process whose bundle identifier is \"$bid\" to false" 2>/dev/null &
    fi
  else
    # Quit ordinary apps
    osascript -e "tell application id \"$bid\" to quit" &
  fi
done < <(lsappinfo list | grep -B 4 'type="Foreground"' | grep 'bundleID=' | sed -E 's/.*bundleID="([^"]*)".*/\1/')

wait
