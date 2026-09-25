#!/bin/zsh
# Quit foreground applications, hide excluded ones (including closing Finder windows).
# The script is run by ShortKing through zsh, so keep all state in this process.

EXCLUDED=(
  "com.apple.finder"
  "com.redmunky.ananas"
  "com.redmunky.shortking"
  "com.redmunky.ogle.versib.v8"

  "ca.spreadspace.Hidden"
  "ca.spreadspace.HiddenBar"
)

typeset -A seen

while IFS= read -r bid; do
  [[ -z "$bid" ]] && continue
  [[ -n "${seen[$bid]-}" ]] && continue
  seen[$bid]=1
  
  skip=false
  for ex in "${EXCLUDED[@]}"; do
    if [[ "$bid" == "$ex" ]]; then
      skip=true
      break
    fi
  done
  
  if $skip; then
    # Jika Finder, tutup seluruh jendela Finder yang terbuka
    if [[ "$bid" == "com.apple.finder" ]]; then
      osascript -e 'tell application "Finder" to close every window' &
    # Jika aplikasi exclude lainnya (selain RedMunky Ananas), sembunyikan aplikasinya
    elif [[ "$bid" != "com.redmunky.ananas" && "$bid" != "com.redmunky.shortking" ]]; then
      osascript -e "tell application \"System Events\" to set visible of every process whose bundle identifier is \"$bid\" to false" &
    fi
  else
    # Quit ordinary apps
    osascript -e "tell application id \"$bid\" to quit" &
  fi
done < <(lsappinfo list | grep -B 4 'type="Foreground"' | grep 'bundleID=' | sed -E 's/.*bundleID="([^"]*)".*/\1/' | sort -u)

wait
