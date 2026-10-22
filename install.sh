#!/usr/bin/env bash
# QsDock installer
#   ./install.sh            -> English interface
#   ./install.sh --lang tr  -> Turkish interface
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
QS="$HOME/.config/quickshell"
STAMP="$(date +%Y%m%d-%H%M%S)"
LANG_CHOICE="en"
[ "${1:-}" = "--lang" ] && LANG_CHOICE="${2:-en}"

echo ":: Checking dependencies"
missing=()
for cmd in qs hyprctl nmcli bluetoothctl powerprofilesctl curl wal; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "   missing commands: ${missing[*]}"
    echo "   (see README -> Dependencies; the dock still installs, those features just won't work)"
fi

echo ":: Copying Quickshell configs to $QS"
mkdir -p "$QS"
for d in "$DIR"/quickshell/*/; do
    name="$(basename "$d")"
    if [ -e "$QS/$name" ]; then
        mv "$QS/$name" "$QS/$name.backup-$STAMP"
        echo "   backed up existing $name -> $name.backup-$STAMP"
    fi
    cp -r "$d" "$QS/$name"
    echo "   $name"
done
chmod +x "$QS/battery/battery-data.sh"

echo ":: Installing helper to ~/.local/bin"
install -Dm755 "$DIR/bin/dock-reserve" "$HOME/.local/bin/dock-reserve"

if [ ! -f "$QS/settings.json" ]; then
    sed "s/\"lang\": \"en\"/\"lang\": \"$LANG_CHOICE\"/" "$DIR/settings.example.json" > "$QS/settings.json"
    echo ":: Created $QS/settings.json (lang: $LANG_CHOICE)"
else
    echo ":: Kept your existing $QS/settings.json"
fi

# the standalone menus (apps, sound, battery, notifications) open inside the dock when this says "dock"
printf 'dock' > "$QS/bar-choice"

cat <<'EOF'

Done! Add these to your Hyprland autostart and restart Hyprland:

  # hyprland.lua
  hl.exec_cmd("qs -c dock -d")
  hl.exec_cmd("qs -c notifications -d")
  hl.exec_cmd("qs -c wifi-panel -d")

  # hyprland.conf
  exec-once = qs -c dock -d
  exec-once = qs -c notifications -d
  exec-once = qs -c wifi-panel -d

(appmenu, audio and battery are optional: start them the same way if you
 want keybinds for them, see README -> Keybinds)

Stop any other notification daemon first (mako, dunst, swaync), only one can run.
Settings (language, name, monitors, wallpapers, prayer times): ~/.config/quickshell/settings.json
EOF
